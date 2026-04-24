import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../core/network/socket_service.dart';
import '../auth/auth_controller.dart';

enum CallSessionState {
  calling,
  ringing,
  connecting,
  connected,
}

class CallPeer {
  const CallPeer({
    required this.username,
    required this.displayName,
    this.avatar,
  });

  final String username;
  final String displayName;
  final String? avatar;

  factory CallPeer.fromMap(Map<String, dynamic> json) {
    final username = (json['username'] ?? '').toString();
    final displayName = (json['fullName'] ??
            json['full_name'] ??
            json['displayName'] ??
            username)
        .toString();
    return CallPeer(
      username: username,
      displayName: displayName.isEmpty ? username : displayName,
      avatar: json['avatar']?.toString(),
    );
  }
}

class IncomingCallData {
  const IncomingCallData({
    required this.callId,
    required this.caller,
    required this.offer,
    required this.isVideo,
  });

  final String callId;
  final CallPeer caller;
  final Map<String, dynamic> offer;
  final bool isVideo;
}

class CallController extends ChangeNotifier {
  CallController({
    required SocketService socketService,
    required AuthController authController,
  })  : _socketService = socketService,
        _authController = authController {
    _subscription = _socketService.packets.listen(_handlePacket);
  }

  static const Map<String, dynamic> _rtcConfiguration =
      <String, dynamic>{
    'sdpSemantics': 'unified-plan',
    'iceCandidatePoolSize': 4,
    'bundlePolicy': 'max-bundle',
    'rtcpMuxPolicy': 'require',
    'iceServers': <Map<String, dynamic>>[
      <String, dynamic>{'urls': 'stun:stun.l.google.com:19302'},
      <String, dynamic>{'urls': 'stun:stun1.l.google.com:19302'},
      <String, dynamic>{'urls': 'stun:stun2.l.google.com:19302'},
      <String, dynamic>{'urls': 'stun:stun3.l.google.com:19302'},
      <String, dynamic>{'urls': 'stun:stun4.l.google.com:19302'},
      <String, dynamic>{'urls': 'stun:stun.cloudflare.com:3478'},
      <String, dynamic>{'urls': 'stun:global.stun.twilio.com:3478'},
      <String, dynamic>{
        'urls': 'turn:3.77.233.184:3478',
        'username': 'bootchat',
        'credential': 'Bootchat2024!',
      },
      <String, dynamic>{
        'urls': 'turn:3.77.233.184:3478?transport=tcp',
        'username': 'bootchat',
        'credential': 'Bootchat2024!',
      },
      <String, dynamic>{
        'urls': 'turn:63.183.168.37:3478?transport=udp',
        'username': 'bootchat',
        'credential': 'Bootchat2024!',
      },
      <String, dynamic>{
        'urls': 'turn:63.183.168.37:3478?transport=tcp',
        'username': 'bootchat',
        'credential': 'Bootchat2024!',
      },
      <String, dynamic>{
        'urls': 'turns:63.183.168.37:5349?transport=tcp',
        'username': 'bootchat',
        'credential': 'Bootchat2024!',
      },
    ],
  };
  static const Duration _socketRecoveryGrace = Duration(seconds: 50);
  static const Duration _peerDisconnectGrace = Duration(seconds: 12);
  static const MethodChannel _callAudioChannel =
      MethodChannel('bootchat/call_audio');
  static const Map<String, dynamic> _sdpAnswerConstraints =
      <String, dynamic>{
    'mandatory': <String, dynamic>{
      'OfferToReceiveAudio': true,
      'OfferToReceiveVideo': true,
    },
    'optional': <dynamic>[],
  };

  final SocketService _socketService;
  final AuthController _authController;

  late final StreamSubscription<SocketPacket> _subscription;

  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  final List<RTCIceCandidate> _pendingCandidates = <RTCIceCandidate>[];

  Timer? _ringingTimeout;
  Timer? _clearErrorTimer;
  Timer? _socketRecoveryTimer;
  Timer? _peerDisconnectTimer;

  CallSessionState? _state;
  CallPeer? _remotePeer;
  IncomingCallData? _incomingCall;

  bool _remoteDescriptionReady = false;
  bool _isVideo = false;
  bool _isMuted = false;
  bool _isCameraOff = false;
  bool _disposed = false;
  bool _isAwaitingSocketRecovery = false;

  String? _callId;
  String? _targetUsername;
  String? _initiatorUsername;
  DateTime? _connectedAt;
  String? _errorKey;
  int _errorVersion = 0;

  CallSessionState? get state => _state;
  CallPeer? get remotePeer => _remotePeer;
  IncomingCallData? get incomingCall => _incomingCall;
  MediaStream? get localStream => _localStream;
  MediaStream? get remoteStream => _remoteStream;
  bool get isVideo => _isVideo;
  bool get isMuted => _isMuted;
  bool get isCameraOff => _isCameraOff;
  bool get hasSession => _state != null;
  bool get hasIncomingCall => _incomingCall != null;
  bool get canToggleCamera => _isVideo;
  DateTime? get connectedAt => _connectedAt;
  String? get errorKey => _errorKey;
  int get errorVersion => _errorVersion;

  Future<void> startCall(
    CallPeer peer, {
    required bool video,
  }) async {
    debugPrint('Call start requested: ${peer.username} (video=$video)');
    if (hasSession || hasIncomingCall) {
      _publishError('call_busy');
      return;
    }

    final currentUser = _authController.user;
    if (currentUser == null) {
      _publishError('call_failed');
      return;
    }
    if (!_socketService.isConnected) {
      _publishError('call_not_connected');
      return;
    }

    _clearError();
    _remotePeer = peer;
    _callId = _buildCallId(currentUser.username, peer.username);
    _targetUsername = peer.username;
    _initiatorUsername = currentUser.username;
    _state = CallSessionState.calling;
    _incomingCall = null;
    _isVideo = video;
    _isMuted = false;
    _isCameraOff = false;
    _connectedAt = null;
    _notify();

    try {
      final stream = await navigator.mediaDevices.getUserMedia(
        _mediaConstraints(video),
      );
      _enableLocalTracks(stream);
      _localStream = stream;
      await _configureAudioRoute(video);

      final pc = await _createPeerConnection(peer.username);
      for (final track in stream.getTracks()) {
        await pc.addTrack(track, stream);
      }

      final offer = await pc.createOffer(_sdpOfferConstraints(video));
      await pc.setLocalDescription(offer);
      debugPrint('Call offer created and set locally.');

      _socketService.emit('CALL_OFFER', <String, dynamic>{
        'callId': _callId,
        'target': peer.username,
        'caller': <String, dynamic>{
          'username': currentUser.username,
          'fullName': currentUser.displayName,
          'avatar': currentUser.avatar,
        },
        'offer': _sessionToMap(offer),
        'isVideo': video,
      });

      _state = CallSessionState.ringing;
      _startRingingTimeout();
      _notify();
    } catch (error) {
      await _resetSession();
      _publishError(_errorKeyFor(error));
    }
  }

  Future<void> acceptIncomingCall() async {
    final incoming = _incomingCall;
    if (incoming == null) {
      return;
    }
    debugPrint('Accepting incoming call from ${incoming.caller.username}');
    if (!_socketService.isConnected) {
      _publishError('call_not_connected');
      return;
    }

    _clearError();
    await _stopIncomingRingtone();
    _remotePeer = incoming.caller;
    _callId = incoming.callId;
    _targetUsername = incoming.caller.username;
    _initiatorUsername = incoming.caller.username;
    _state = CallSessionState.connecting;
    _incomingCall = null;
    _isVideo = incoming.isVideo;
    _isMuted = false;
    _isCameraOff = false;
    _connectedAt = null;
    _notify();

    try {
      final stream = await navigator.mediaDevices.getUserMedia(
        _mediaConstraints(incoming.isVideo),
      );
      _enableLocalTracks(stream);
      _localStream = stream;
      await _configureAudioRoute(incoming.isVideo);

      final pc = await _createPeerConnection(incoming.caller.username);
      for (final track in stream.getTracks()) {
        await pc.addTrack(track, stream);
      }

      await _applyRemoteDescription(incoming.offer);

      final answer = await pc.createAnswer(_sdpAnswerConstraints);
      await pc.setLocalDescription(answer);
      debugPrint('Call answer created and set locally.');

      _socketService.emit('CALL_ANSWER', <String, dynamic>{
        'callId': incoming.callId,
        'target': incoming.caller.username,
        'answer': _sessionToMap(answer),
        'user': <String, dynamic>{
          'username': _authController.user?.username,
          'full_name': _authController.user?.displayName,
          'avatar': _authController.user?.avatar,
        },
      });

      _notify();
    } catch (error) {
      _socketService.emit('CALL_REJECT', <String, dynamic>{
        'callId': incoming.callId,
        'target': incoming.caller.username,
        'isVideo': incoming.isVideo,
      });
      await _resetSession();
      _publishError(_errorKeyFor(error));
    }
  }

  void rejectIncomingCall() {
    final incoming = _incomingCall;
    if (incoming == null) {
      return;
    }

    _socketService.emit('CALL_REJECT', <String, dynamic>{
      'callId': incoming.callId,
      'target': incoming.caller.username,
      'isVideo': incoming.isVideo,
    });
    unawaited(_stopIncomingRingtone());
    _incomingCall = null;
    _remotePeer = null;
    _notify();
  }

  Future<void> hangUp() async {
    final target = _targetUsername;
    if (target != null && (hasSession || hasIncomingCall)) {
      final duration = _connectedAt == null
          ? 0
          : DateTime.now().difference(_connectedAt!).inSeconds;
      _socketService.emit('CALL_END', <String, dynamic>{
        'callId': _callId,
        'target': target,
        'duration': duration,
        'isVideo': _isVideo,
        'callerUsername':
            _initiatorUsername ?? _authController.user?.username ?? target,
      });
    }
    await _resetSession();
  }

  Future<void> toggleMute() async {
    final stream = _localStream;
    if (stream == null) {
      return;
    }

    _isMuted = !_isMuted;
    for (final track in stream.getAudioTracks()) {
      track.enabled = !_isMuted;
    }
    _notify();
  }

  Future<void> toggleCamera() async {
    if (!_isVideo) {
      return;
    }
    final stream = _localStream;
    if (stream == null) {
      return;
    }

    _isCameraOff = !_isCameraOff;
    for (final track in stream.getVideoTracks()) {
      track.enabled = !_isCameraOff;
    }
    _notify();
  }

  void clearError() {
    _clearError();
    _notify();
  }

  void _handlePacket(SocketPacket packet) {
    switch (packet.event) {
      case 'CALL_OFFER':
        _handleCallOffer(packet.payload);
        break;
      case 'CALL_ANSWER':
        unawaited(_handleCallAnswer(packet.payload));
        break;
      case 'ICE_CANDIDATE':
        unawaited(_handleIceCandidate(packet.payload));
        break;
      case 'CALL_REJECT':
        if (_matchesActiveCall(_asMap(packet.payload)['callId'])) {
          unawaited(_handleRemoteEnded('call_rejected'));
        }
        break;
      case 'CALL_END':
        if (_matchesActiveCall(_asMap(packet.payload)['callId'])) {
          unawaited(_handleRemoteEnded());
        }
        break;
      case 'CALL_BLOCKED':
        _cancelSocketRecovery();
        unawaited(_handleRemoteEnded('call_blocked'));
        break;
      case 'CALL_NOT_DELIVERED':
        _cancelSocketRecovery();
        unawaited(_handleCallNotDelivered());
        break;
      case 'CALL_SESSION_SYNC':
        _handleCallSessionSync(packet.payload);
        break;
      case 'CALL_PARTICIPANT_RECONNECTING':
        _handleParticipantReconnecting(packet.payload);
        break;
      case 'CALL_PARTICIPANT_REJOINED':
        _handleParticipantRejoined(packet.payload);
        break;
      case 'connect':
        _handleSocketConnected();
        break;
      case 'disconnect':
      case 'connect_error':
      case 'error':
        if (hasSession || hasIncomingCall) {
          _scheduleSocketRecovery();
        }
        break;
    }
  }

  void _handleCallOffer(dynamic payload) {
    final data = _asMap(payload);
    final caller = CallPeer.fromMap(_asMap(data['caller']));
    if (caller.username.isEmpty) {
      return;
    }

    if (hasSession || hasIncomingCall) {
      _socketService.emit('CALL_REJECT', <String, dynamic>{
        'callId': data['callId']?.toString(),
        'target': caller.username,
        'isVideo': data['isVideo'] == true,
      });
      return;
    }

    final callId = (data['callId'] ?? '').toString().trim();
    _incomingCall = IncomingCallData(
      callId: callId.isEmpty
          ? _buildCallId(caller.username, _authController.user?.username ?? 'call')
          : callId,
      caller: caller,
      offer: _asMap(data['offer']),
      isVideo: data['isVideo'] == true,
    );
    _clearError();
    unawaited(_startIncomingRingtone());
    _notify();
  }

  Future<void> _handleCallAnswer(dynamic payload) async {
    if (_peerConnection == null) {
      return;
    }

    final data = _asMap(payload);
    if (!_matchesActiveCall(data['callId'])) {
      return;
    }
    final answer = _asMap(data['answer']);
    if (answer.isEmpty) {
      return;
    }

    _clearRingingTimeout();
    debugPrint('Received call answer.');
    await _applyRemoteDescription(answer);
  }

  Future<void> _handleIceCandidate(dynamic payload) async {
    final data = _asMap(payload);
    if (!_matchesActiveCall(data['callId'])) {
      return;
    }
    final candidateData = _asMap(data['candidate']);
    final candidate = _candidateFromMap(candidateData);
    if (candidate == null) {
      return;
    }

    final pc = _peerConnection;
    if (pc != null && _remoteDescriptionReady) {
      await pc.addCandidate(candidate);
      return;
    }
    _pendingCandidates.add(candidate);
  }

  Future<void> _handleCallNotDelivered() async {
    if (!hasSession) {
      return;
    }

    final target = _targetUsername;
    if (target != null) {
      _socketService.emit('CALL_END', <String, dynamic>{
        'callId': _callId,
        'target': target,
        'duration': 0,
        'isVideo': _isVideo,
        'callerUsername':
            _initiatorUsername ?? _authController.user?.username ?? target,
      });
    }
    await _resetSession();
    _publishError('call_not_delivered');
  }

  Future<void> _handleRemoteEnded([String? errorKey]) async {
    _cancelSocketRecovery();
    _cancelPeerDisconnectTimer();
    await _resetSession();
    if (errorKey != null) {
      _publishError(errorKey);
    }
  }

  void _handleSocketConnected() {
    _cancelSocketRecovery();

    final username = _authController.user?.username;
    final activeCallId = _callId ?? _incomingCall?.callId;
    if (username == null ||
        username.isEmpty ||
        (activeCallId == null && !hasSession && !hasIncomingCall)) {
      return;
    }

    _socketService.emit('CALL_SESSION_SYNC_REQUEST', <String, dynamic>{
      'username': username,
      'callId': activeCallId,
    });
  }

  void _handleCallSessionSync(dynamic payload) {
    final data = _asMap(payload);
    final syncedCallId = data['callId']?.toString().trim();
    if (syncedCallId == null || syncedCallId.isEmpty) {
      return;
    }

    final peer = CallPeer.fromMap(_asMap(data['peer']));
    if (peer.username.isNotEmpty) {
      _remotePeer = peer;
      _targetUsername = peer.username;
    }

    _callId = syncedCallId;
    _isVideo = data['isVideo'] == true;
    final startedAt = _parseTimestamp(data['startedAt']);
    _connectedAt ??= startedAt;

    switch ((data['status'] ?? '').toString()) {
      case 'connected':
        _state = CallSessionState.connected;
        break;
      case 'ringing':
      default:
        _state ??= CallSessionState.connecting;
        break;
    }

    _clearError();
    _cancelSocketRecovery();
    _cancelPeerDisconnectTimer();
    _notify();
  }

  void _handleParticipantReconnecting(dynamic payload) {
    final data = _asMap(payload);
    if (!_matchesActiveCall(data['callId'])) {
      return;
    }
    _schedulePeerDisconnectTimer();
  }

  void _handleParticipantRejoined(dynamic payload) {
    final data = _asMap(payload);
    if (!_matchesActiveCall(data['callId'])) {
      return;
    }
    _cancelPeerDisconnectTimer();
    _clearError();
    _notify();
  }

  Future<RTCPeerConnection> _createPeerConnection(
    String targetUsername,
  ) async {
    final pc = await createPeerConnection(_rtcConfiguration);
    debugPrint('PeerConnection created for $targetUsername');

    pc.onTrack = (RTCTrackEvent event) async {
      event.track.enabled = true;
      MediaStream stream;
      if (event.streams.isNotEmpty) {
        stream = event.streams.first;
      } else {
        stream = _remoteStream ??
            await createLocalMediaStream('bootchat-remote-$targetUsername');
        await stream.addTrack(event.track);
      }
      _enableRemoteTracks(stream);
      _remoteStream = stream;
      _markConnected();
      _notify();
    };

    pc.onAddStream = (MediaStream stream) {
      _enableRemoteTracks(stream);
      _remoteStream = stream;
      _markConnected();
      _notify();
    };

    pc.onIceCandidate = (RTCIceCandidate candidate) {
      if (candidate.candidate == null || candidate.candidate!.isEmpty) {
        return;
      }
      _socketService.emit('ICE_CANDIDATE', <String, dynamic>{
        'callId': _callId,
        'target': targetUsername,
        'candidate': _candidateToMap(candidate),
      });
    };

    pc.onIceConnectionState = (RTCIceConnectionState state) {
      debugPrint('ICE connection state: $state');
      if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
          state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        _cancelPeerDisconnectTimer();
        _markConnected();
        _notify();
        return;
      }

      if (state == RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
        _schedulePeerDisconnectTimer();
        return;
      }

      if (state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
        unawaited(_handleRemoteEnded('call_connection_failed'));
      }
    };

    pc.onConnectionState = (RTCPeerConnectionState state) {
      debugPrint('Peer connection state: $state');
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _cancelPeerDisconnectTimer();
        _markConnected();
        _notify();
        return;
      }

      if (state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        _schedulePeerDisconnectTimer();
        return;
      }

      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        unawaited(_handleRemoteEnded('call_connection_failed'));
      }
    };

    _peerConnection = pc;
    return pc;
  }

  void _markConnected() {
    _clearRingingTimeout();
    unawaited(_stopIncomingRingtone());
    _cancelSocketRecovery();
    _cancelPeerDisconnectTimer();
    _connectedAt ??= DateTime.now();
    _state = CallSessionState.connected;
  }

  Future<void> _applyRemoteDescription(Map<String, dynamic> session) async {
    final pc = _peerConnection;
    final description = _sessionFromMap(session);
    if (pc == null || description == null) {
      return;
    }

    await pc.setRemoteDescription(description);
    _remoteDescriptionReady = true;

    while (_pendingCandidates.isNotEmpty) {
      await pc.addCandidate(_pendingCandidates.removeAt(0));
    }
  }

  void _startRingingTimeout() {
    _clearRingingTimeout();
    _ringingTimeout = Timer(const Duration(seconds: 30), () async {
      final target = _targetUsername;
      if (target != null) {
        _socketService.emit('CALL_END', <String, dynamic>{
          'callId': _callId,
          'target': target,
          'duration': 0,
          'isVideo': _isVideo,
          'callerUsername':
              _initiatorUsername ?? _authController.user?.username ?? target,
        });
      }
      await _resetSession();
      _publishError('call_not_delivered');
    });
  }

  Future<void> _resetSession() async {
    _clearRingingTimeout();
    await _stopIncomingRingtone();
    _cancelSocketRecovery();
    _cancelPeerDisconnectTimer();
    _pendingCandidates.clear();
    _remoteDescriptionReady = false;
    await _restoreAudioRoute();

    final pc = _peerConnection;
    _peerConnection = null;
    await pc?.close();

    final localStream = _localStream;
    _localStream = null;
    if (localStream != null) {
      for (final track in localStream.getTracks()) {
        track.stop();
      }
      localStream.dispose();
    }

    final remoteStream = _remoteStream;
    _remoteStream = null;
    remoteStream?.dispose();

    _state = null;
    _remotePeer = null;
    _incomingCall = null;
    _callId = null;
    _targetUsername = null;
    _initiatorUsername = null;
    _connectedAt = null;
    _isVideo = false;
    _isMuted = false;
    _isCameraOff = false;
    _isAwaitingSocketRecovery = false;
    _notify();
  }

  Map<String, dynamic> _mediaConstraints(bool video) {
    return <String, dynamic>{
      'audio': <String, dynamic>{
        'echoCancellation': true,
        'noiseSuppression': true,
        'autoGainControl': true,
        'channelCount': 1,
        'googEchoCancellation': true,
        'googNoiseSuppression': true,
        'googAutoGainControl': true,
        'googHighpassFilter': true,
      },
      'video': video
          ? <String, dynamic>{
              'facingMode': 'user',
            }
          : false,
    };
  }

  Map<String, dynamic> _sdpOfferConstraints(bool video) {
    return <String, dynamic>{
      'mandatory': <String, dynamic>{
        'OfferToReceiveAudio': true,
        'OfferToReceiveVideo': video,
      },
      'optional': <dynamic>[],
    };
  }

  Map<String, dynamic> _sessionToMap(RTCSessionDescription description) {
    return <String, dynamic>{
      'sdp': description.sdp,
      'type': description.type,
    };
  }

  RTCSessionDescription? _sessionFromMap(Map<String, dynamic> json) {
    final sdp = json['sdp']?.toString();
    final type = json['type']?.toString();
    if (sdp == null || sdp.isEmpty || type == null || type.isEmpty) {
      return null;
    }
    return RTCSessionDescription(sdp, type);
  }

  Map<String, dynamic> _candidateToMap(RTCIceCandidate candidate) {
    return <String, dynamic>{
      'candidate': candidate.candidate,
      'sdpMid': candidate.sdpMid,
      'sdpMLineIndex': candidate.sdpMLineIndex,
    };
  }

  RTCIceCandidate? _candidateFromMap(Map<String, dynamic> json) {
    final candidate = json['candidate']?.toString();
    if (candidate == null || candidate.isEmpty) {
      return null;
    }
    return RTCIceCandidate(
      candidate,
      json['sdpMid']?.toString(),
      json['sdpMLineIndex'] is int
          ? json['sdpMLineIndex'] as int
          : int.tryParse('${json['sdpMLineIndex'] ?? ''}'),
    );
  }

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return const <String, dynamic>{};
  }

  String _buildCallId(String caller, String callee) {
    return '$caller:$callee:${DateTime.now().microsecondsSinceEpoch}';
  }

  bool _matchesActiveCall(dynamic value) {
    final current = _callId ?? _incomingCall?.callId;
    final incoming = value?.toString().trim();
    if (current == null || current.isEmpty) {
      return incoming == null || incoming.isEmpty;
    }
    return incoming == null || incoming.isEmpty || incoming == current;
  }

  String _errorKeyFor(Object error) {
    final message = error.toString().toLowerCase();
    if (message.contains('notallowed') ||
        message.contains('permission') ||
        message.contains('denied')) {
      return 'call_permission_denied';
    }
    return 'call_failed';
  }

  void _publishError(String key) {
    _clearErrorTimer?.cancel();
    _errorKey = key;
    _errorVersion += 1;
    _notify();
    _clearErrorTimer = Timer(const Duration(seconds: 4), () {
      _clearError();
      _notify();
    });
  }

  void _clearError() {
    _clearErrorTimer?.cancel();
    _clearErrorTimer = null;
    _errorKey = null;
  }

  void _clearRingingTimeout() {
    _ringingTimeout?.cancel();
    _ringingTimeout = null;
  }

  void _scheduleSocketRecovery() {
    if (_isAwaitingSocketRecovery) {
      return;
    }
    _isAwaitingSocketRecovery = true;
    _socketRecoveryTimer?.cancel();
    _socketRecoveryTimer = Timer(_socketRecoveryGrace, () {
      _isAwaitingSocketRecovery = false;
      unawaited(_handleRemoteEnded('call_connection_lost'));
    });
  }

  void _cancelSocketRecovery() {
    _isAwaitingSocketRecovery = false;
    _socketRecoveryTimer?.cancel();
    _socketRecoveryTimer = null;
  }

  void _schedulePeerDisconnectTimer() {
    _peerDisconnectTimer?.cancel();
    _peerDisconnectTimer = Timer(_peerDisconnectGrace, () {
      unawaited(_handleRemoteEnded('call_connection_lost'));
    });
  }

  void _cancelPeerDisconnectTimer() {
    _peerDisconnectTimer?.cancel();
    _peerDisconnectTimer = null;
  }

  DateTime? _parseTimestamp(dynamic value) {
    if (value == null) {
      return null;
    }

    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value);
    }

    return DateTime.tryParse(value.toString());
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  void _enableLocalTracks(MediaStream stream) {
    for (final track in stream.getAudioTracks()) {
      track.enabled = true;
    }
    for (final track in stream.getVideoTracks()) {
      track.enabled = true;
    }
  }

  void _enableRemoteTracks(MediaStream stream) {
    for (final track in stream.getAudioTracks()) {
      track.enabled = true;
    }
    for (final track in stream.getVideoTracks()) {
      track.enabled = true;
    }
  }

  Future<void> _startIncomingRingtone() async {
    if (kIsWeb) {
      return;
    }
    try {
      await _callAudioChannel.invokeMethod<void>('startIncomingRingtone');
    } catch (_) {
      // Incoming call UI should still work even if the platform ringtone fails.
    }
  }

  Future<void> _stopIncomingRingtone() async {
    if (kIsWeb) {
      return;
    }
    try {
      await _callAudioChannel.invokeMethod<void>('stopIncomingRingtone');
    } catch (_) {
      // Ignore cleanup failures to avoid breaking call teardown.
    }
  }

  Future<void> _configureAudioRoute(bool video) async {
    if (kIsWeb) {
      return;
    }

    try {
      await Helper.setSpeakerphoneOn(true);
    } catch (_) {
      // Keep the call alive even if the platform refuses audio route changes.
    }
  }

  Future<void> _restoreAudioRoute() async {
    if (kIsWeb) {
      return;
    }

    try {
      await Helper.setSpeakerphoneOn(false);
    } catch (_) {
      // Ignore cleanup failures during teardown.
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _clearRingingTimeout();
    _clearErrorTimer?.cancel();
    _socketRecoveryTimer?.cancel();
    _peerDisconnectTimer?.cancel();
    _subscription.cancel();
    unawaited(_stopIncomingRingtone());
    unawaited(_restoreAudioRoute());
    final pc = _peerConnection;
    _peerConnection = null;
    pc?.close();
    final localStream = _localStream;
    _localStream = null;
    if (localStream != null) {
      for (final track in localStream.getTracks()) {
        track.stop();
      }
      localStream.dispose();
    }
    final remoteStream = _remoteStream;
    _remoteStream = null;
    remoteStream?.dispose();
    super.dispose();
  }
}
