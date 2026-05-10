import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/network/socket_service.dart';
import '../auth/auth_controller.dart';

enum CallSessionState { calling, ringing, connecting, connected }

enum CallAudioRoute { speaker, bluetooth, headset, earpiece }

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
    _audioPlayer = AudioPlayer();
  }

  static const MethodChannel _audioChannel =
      MethodChannel('bootchat/call_audio');

  final Map<String, dynamic> _rtcConfiguration = {
    'sdpSemantics': 'unified-plan',
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {
        'urls': 'turns:jamshiddin.uz:5349',
        'username': 'bootchat',
        'credential': 'Bootchat2024!',
      },
    ],
    'iceTransportPolicy': 'relay',
    'iceCandidatePoolSize': 10,
  };

  final SocketService _socketService;
  final AuthController _authController;
  late final StreamSubscription<SocketPacket> _subscription;
  late final AudioPlayer _audioPlayer;

  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  final List<RTCIceCandidate> _pendingCandidates = <RTCIceCandidate>[];

  CallSessionState? _state;
  CallPeer? _remotePeer;
  IncomingCallData? _incomingCall;
  bool _remoteDescriptionReady = false;
  bool _isVideo = false;
  bool _isMuted = false;
  bool _isCameraOff = false;
  bool _isSpeakerOn = true;
  bool _hasBluetoothAudio = false;
  bool _hasHeadsetAudio = false;
  CallAudioRoute _audioRoute = CallAudioRoute.speaker;
  String? _callId;
  String? _targetUsername;
  DateTime? _connectedAt;

  CallSessionState? get state => _state;
  CallPeer? get remotePeer => _remotePeer;
  IncomingCallData? get incomingCall => _incomingCall;
  MediaStream? get localStream => _localStream;
  MediaStream? get remoteStream => _remoteStream;
  bool get isVideo => _isVideo;
  bool get isMuted => _isMuted;
  bool get isCameraOff => _isCameraOff;
  bool get isSpeakerOn => _isSpeakerOn;
  bool get hasBluetoothAudio => _hasBluetoothAudio;
  bool get hasHeadsetAudio => _hasHeadsetAudio;
  CallAudioRoute get audioRoute => _audioRoute;
  bool get hasExternalAudioRoute => _hasBluetoothAudio || _hasHeadsetAudio;
  bool get hasSession => _state != null && _incomingCall == null;
  bool get hasIncomingCall => _incomingCall != null;
  DateTime? get connectedAt => _connectedAt;
  String? get errorKey => null;
  int get errorVersion => 0;

  Future<void> startCall(CallPeer peer, {required bool video}) async {
    if (hasSession || hasIncomingCall) return;
    debugPrint(
      'CALL_DEBUG startCall() target=${peer.username} video=$video socketConnected=${_socketService.isConnected}',
    );

    await _prepareForNewSession(video: video);
    _remotePeer = peer;
    _callId = 'call_${DateTime.now().millisecondsSinceEpoch}';
    _targetUsername = peer.username;
    _state = CallSessionState.calling;
    notifyListeners();
    await _startOutgoingTone();

    try {
      await _requestMediaPermissions(video: video);
      _localStream = await _openLocalMedia(video: video);
      await _applyAudioRoute();
      final pc = await _createPeerConnection();
      _localStream!
          .getTracks()
          .forEach((track) => pc.addTrack(track, _localStream!));

      final offer = await pc.createOffer();
      await pc.setLocalDescription(offer);
      _peerConnection = pc;

      _socketService.emit('CALL_OFFER', {
        'callId': _callId,
        'target': peer.username,
        'offer': {'sdp': offer.sdp, 'type': offer.type},
        'isVideo': video,
        'caller': {
          'username': _authController.user?.username,
          'fullName': _authController.user?.displayName,
          'avatar': _authController.user?.avatar,
        }
      });
      debugPrint('CALL_DEBUG CALL_OFFER emitted callId=$_callId');
    } catch (error) {
      debugPrint('CALL_DEBUG startCall() failed error=$error');
      await _resetSession(notifyRemote: true, reason: 'setup_failed');
    }
  }

  Future<void> acceptIncomingCall() async {
    if (_incomingCall == null) return;
    debugPrint(
      'CALL_DEBUG acceptIncomingCall() callId=${_incomingCall!.callId} caller=${_incomingCall!.caller.username} video=${_incomingCall!.isVideo}',
    );

    final incoming = _incomingCall!;
    await _stopAlertTone();
    await _prepareForNewSession(
        video: incoming.isVideo, preserveIncoming: true);
    _remotePeer = incoming.caller;
    _callId = incoming.callId;
    _targetUsername = incoming.caller.username;
    _state = CallSessionState.connecting;
    _incomingCall = null;
    notifyListeners();

    try {
      await _requestMediaPermissions(video: incoming.isVideo);
      _localStream = await _openLocalMedia(video: incoming.isVideo);
      await _applyAudioRoute();
      final pc = await _createPeerConnection();
      await pc.setRemoteDescription(
        RTCSessionDescription(incoming.offer['sdp'], incoming.offer['type']),
      );
      _remoteDescriptionReady = true;

      _localStream!
          .getTracks()
          .forEach((track) => pc.addTrack(track, _localStream!));

      for (final candidate in _pendingCandidates) {
        await pc.addCandidate(candidate);
      }
      _pendingCandidates.clear();

      final answer = await pc.createAnswer();
      await pc.setLocalDescription(answer);
      _peerConnection = pc;

      _socketService.emit('CALL_ANSWER', {
        'callId': _callId,
        'target': _targetUsername,
        'answer': {'sdp': answer.sdp, 'type': answer.type},
        'user': {
          'username': _authController.user?.username,
          'full_name': _authController.user?.displayName,
          'avatar': _authController.user?.avatar,
        },
      });
      debugPrint('CALL_DEBUG CALL_ANSWER emitted callId=$_callId');
    } catch (error) {
      debugPrint('CALL_DEBUG acceptIncomingCall() failed error=$error');
      rejectIncomingCall();
    }
  }

  void rejectIncomingCall() {
    final incoming = _incomingCall;
    if (incoming != null) {
      _socketService.emit('CALL_REJECT', {
        'callId': incoming.callId,
        'target': incoming.caller.username,
        'isVideo': incoming.isVideo,
      });
    }
    unawaited(_resetSession());
  }

  Future<void> toggleMute() async {
    _isMuted = !_isMuted;
    for (final track
        in _localStream?.getAudioTracks() ?? <MediaStreamTrack>[]) {
      track.enabled = !_isMuted;
    }
    notifyListeners();
  }

  Future<void> toggleCamera() async {
    _isCameraOff = !_isCameraOff;
    for (final track
        in _localStream?.getVideoTracks() ?? <MediaStreamTrack>[]) {
      track.enabled = !_isCameraOff;
    }
    notifyListeners();
  }

  Future<void> toggleSpeaker() async {
    if (hasExternalAudioRoute) {
      _isSpeakerOn = !_isSpeakerOn;
    } else {
      _isSpeakerOn = true;
    }
    await _applyAudioRoute();
    notifyListeners();
  }

  Future<void> switchCallMode(bool video) async {
    _isVideo = video;
    notifyListeners();
  }

  Future<void> hangUp() async {
    await _resetSession(notifyRemote: true, reason: 'hangup');
  }

  void _handlePacket(SocketPacket packet) {
    debugPrint('CALL_DEBUG packet event=${packet.event} payload=${packet.payload}');
    final data = Map<String, dynamic>.from(packet.payload as Map? ?? {});
    switch (packet.event) {
      case 'CALL_OFFER':
        if (hasSession || hasIncomingCall) {
          _socketService.emit('CALL_REJECT', {
            'callId': data['callId'],
            'target': Map<String, dynamic>.from(
                data['caller'] as Map? ?? {})['username'],
            'isVideo': data['isVideo'] == true,
          });
          break;
        }
        _incomingCall = IncomingCallData(
          callId: (data['callId'] ?? '').toString(),
          caller: CallPeer.fromMap(
              Map<String, dynamic>.from(data['caller'] as Map? ?? {})),
          offer: Map<String, dynamic>.from(data['offer'] as Map? ?? {}),
          isVideo: data['isVideo'] == true,
        );
        _remotePeer = _incomingCall!.caller;
        _state = CallSessionState.ringing;
        unawaited(_startIncomingTone());
        notifyListeners();
        break;
      case 'CALL_ANSWER':
        final answer = Map<String, dynamic>.from(data['answer'] as Map? ?? {});
        _peerConnection
            ?.setRemoteDescription(
                RTCSessionDescription(answer['sdp'], answer['type']))
            .then((_) async {
          _remoteDescriptionReady = true;
          for (final candidate in _pendingCandidates) {
            await _peerConnection?.addCandidate(candidate);
          }
          _pendingCandidates.clear();
          _state = CallSessionState.connecting;
          notifyListeners();
        });
        break;
      case 'ICE_CANDIDATE':
        final cand = Map<String, dynamic>.from(data['candidate'] as Map? ?? {});
        final candidate = RTCIceCandidate(
          cand['candidate'],
          cand['sdpMid'],
          cand['sdpMLineIndex'],
        );
        if (_remoteDescriptionReady) {
          _peerConnection?.addCandidate(candidate);
        } else {
          _pendingCandidates.add(candidate);
        }
        break;
      case 'CALL_REJECT':
      case 'CALL_END':
      case 'CALL_BLOCKED':
      case 'CALL_NOT_DELIVERED':
        unawaited(_resetSession());
        break;
      case 'CALL_SESSION_SYNC':
        final peer = CallPeer.fromMap(
            Map<String, dynamic>.from(data['peer'] as Map? ?? {}));
        _remotePeer = peer;
        _callId = data['callId']?.toString();
        _targetUsername = peer.username;
        _isVideo = data['isVideo'] == true;
        _state = data['status'] == 'connected'
            ? CallSessionState.connected
            : CallSessionState.connecting;
        final startedAt = data['startedAt'];
        if (startedAt is String) {
          _connectedAt = DateTime.tryParse(startedAt);
        } else if (startedAt is num) {
          _connectedAt = DateTime.fromMillisecondsSinceEpoch(startedAt.toInt());
        }
        notifyListeners();
        break;
    }
  }

  Future<void> _prepareForNewSession({
    required bool video,
    bool preserveIncoming = false,
  }) async {
    await _stopAlertTone();
    await _closePeerResources();
    _resetInternalState();
    _isVideo = video;
    _isMuted = false;
    _isCameraOff = false;
    _isSpeakerOn = video;
    _hasBluetoothAudio = false;
    _hasHeadsetAudio = false;
    _audioRoute = video ? CallAudioRoute.speaker : CallAudioRoute.earpiece;
    if (!preserveIncoming) {
      _incomingCall = null;
    }
  }

  Future<void> _requestMediaPermissions({required bool video}) async {
    final permissions = <Permission>[Permission.microphone];
    if (video) {
      permissions.add(Permission.camera);
    }
    await permissions.request();
  }

  Future<MediaStream> _openLocalMedia({required bool video}) {
    return navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': video ? {'facingMode': 'user'} : false,
    });
  }

  Future<RTCPeerConnection> _createPeerConnection() async {
    final pc = await createPeerConnection(_rtcConfiguration);

    pc.onIceCandidate = (candidate) {
      if (candidate.candidate == null || _targetUsername == null) return;
      _socketService.emit('ICE_CANDIDATE', {
        'callId': _callId,
        'target': _targetUsername,
        'candidate': {
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        }
      });
    };

    pc.onTrack = (event) async {
      final track = event.track;
      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams.first;
      } else {
        _remoteStream ??= await createLocalMediaStream('bootchat_remote');
        _remoteStream!.addTrack(track);
      }
      if (track.kind == 'audio') {
        unawaited(_applyAudioRoute());
      }
      unawaited(_markCallConnected());
      notifyListeners();
    };

    pc.onIceConnectionState = (state) {
      if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
          state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        unawaited(_markCallConnected());
      } else if (state == RTCIceConnectionState.RTCIceConnectionStateFailed ||
          state == RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
        unawaited(_resetSession());
      }
    };

    pc.onConnectionState = (state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        unawaited(_markCallConnected());
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        unawaited(_resetSession());
      }
    };

    return pc;
  }

  Future<void> _markCallConnected() async {
    _state = CallSessionState.connected;
    _connectedAt ??= DateTime.now();
    await _stopAlertTone();
    await _applyAudioRoute();
    notifyListeners();
  }

  Future<void> _startOutgoingTone() async {
    await _audioPlayer.stop();
    await _audioPlayer.setReleaseMode(ReleaseMode.loop);
    await _audioPlayer.play(AssetSource('sounds/dialing.mp3'));
  }

  Future<void> _startIncomingTone() async {
    await _audioPlayer.stop();
    await _audioPlayer.setReleaseMode(ReleaseMode.loop);

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        await _audioChannel.invokeMethod<void>('startIncomingRingtone');
        return;
      } catch (_) {}
    }

    await _audioPlayer.play(AssetSource('sounds/ringtone.mp3'));
  }

  Future<void> _stopAlertTone() async {
    await _audioPlayer.stop();

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        await _audioChannel.invokeMethod<void>('stopIncomingRingtone');
      } catch (_) {}
    }
  }

  Future<void> _applyAudioRoute() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;

    try {
      final result = await _audioChannel.invokeMapMethod<String, dynamic>(
        'activateCallAudio',
        {
        'speakerOn': _isVideo || _isSpeakerOn,
        },
      );
      _syncAudioRouteInfo(result);
    } catch (_) {}
  }

  Future<void> _restoreAudioRoute() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;

    try {
      await _audioChannel.invokeMethod<void>('restoreAudioRoute');
    } catch (_) {}
  }

  Future<void> _closePeerResources() async {
    await _peerConnection?.close();
    for (final track in _localStream?.getTracks() ?? <MediaStreamTrack>[]) {
      track.stop();
    }
    _peerConnection = null;
    _localStream = null;
    _remoteStream = null;
  }

  Future<void> _resetSession({
    bool notifyRemote = false,
    String reason = 'hangup',
  }) async {
    final target = _targetUsername;
    final callId = _callId;
    final wasVideo = _isVideo;
    final duration = _connectedAt == null
        ? 0
        : DateTime.now().difference(_connectedAt!).inSeconds;

    await _stopAlertTone();
    await _closePeerResources();
    await _restoreAudioRoute();

    _state = null;
    _incomingCall = null;
    _remotePeer = null;
    _callId = null;
    _targetUsername = null;
    _resetInternalState();
    notifyListeners();

    if (notifyRemote && target != null) {
      _socketService.emit('CALL_END', {
        'callId': callId,
        'target': target,
        'reason': reason,
        'isVideo': wasVideo,
        'duration': duration,
      });
    }
  }

  void _resetInternalState() {
    _connectedAt = null;
    _pendingCandidates.clear();
    _remoteDescriptionReady = false;
  }

  void _syncAudioRouteInfo(Map<String, dynamic>? data) {
    if (data == null) return;

    _hasBluetoothAudio = data['hasBluetooth'] == true;
    _hasHeadsetAudio = data['hasHeadset'] == true;

    switch ((data['currentRoute'] ?? '').toString()) {
      case 'bluetooth':
        _audioRoute = CallAudioRoute.bluetooth;
        _isSpeakerOn = false;
        break;
      case 'headset':
        _audioRoute = CallAudioRoute.headset;
        _isSpeakerOn = false;
        break;
      case 'earpiece':
        _audioRoute = CallAudioRoute.earpiece;
        _isSpeakerOn = false;
        break;
      case 'speaker':
      default:
        _audioRoute = CallAudioRoute.speaker;
        _isSpeakerOn = true;
        break;
    }
  }

  @override
  void dispose() {
    _subscription.cancel();
    unawaited(_resetSession());
    _audioPlayer.dispose();
    super.dispose();
  }
}
