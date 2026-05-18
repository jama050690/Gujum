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

class CallSetupException implements Exception {
  const CallSetupException(this.errorKey);

  final String errorKey;
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
    'bundlePolicy': 'max-bundle',
    'rtcpMuxPolicy': 'require',
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:jamshiddin.uz:3478'},
      {
        'urls': [
          'turn:jamshiddin.uz:3478?transport=udp',
          'turn:jamshiddin.uz:3478?transport=tcp',
          'turns:jamshiddin.uz:5349',
        ],
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
  Timer? _iceConnectTimeout;

  CallSessionState? _state;
  CallPeer? _remotePeer;
  IncomingCallData? _incomingCall;
  bool _remoteDescriptionReady = false;
  bool _connectedSignalSent = false;
  bool _isVideo = false;
  bool _isMuted = false;
  bool _isCameraOff = false;
  bool _isSpeakerOn = true;
  bool _isFrontCamera = true;
  bool _hasBluetoothAudio = false;
  bool _hasHeadsetAudio = false;
  bool _isUpgradingToVideo = false;
  CallAudioRoute _audioRoute = CallAudioRoute.speaker;
  String? _callId;
  String? _targetUsername;
  DateTime? _connectedAt;
  String? _errorKey;
  int _errorVersion = 0;

  CallSessionState? get state => _state;
  CallPeer? get remotePeer => _remotePeer;
  IncomingCallData? get incomingCall => _incomingCall;
  MediaStream? get localStream => _localStream;
  MediaStream? get remoteStream => _remoteStream;
  bool get hasRemoteVideo => _remoteStream?.getVideoTracks().isNotEmpty == true;
  bool get isVideo => _isVideo;
  bool get isMuted => _isMuted;
  bool get isCameraOff => _isCameraOff;
  bool get isSpeakerOn => _isSpeakerOn;
  bool get isFrontCamera => _isFrontCamera;
  bool get hasBluetoothAudio => _hasBluetoothAudio;
  bool get hasHeadsetAudio => _hasHeadsetAudio;
  CallAudioRoute get audioRoute => _audioRoute;
  bool get hasExternalAudioRoute => _hasBluetoothAudio || _hasHeadsetAudio;
  bool get hasSession => _state != null && _incomingCall == null;
  bool get hasIncomingCall => _incomingCall != null;
  DateTime? get connectedAt => _connectedAt;
  bool get canToggleCamera =>
      _state == CallSessionState.connected &&
      (_peerConnection != null) &&
      !_isUpgradingToVideo;
  String? get errorKey => _errorKey;
  int get errorVersion => _errorVersion;

  Future<void> startCall(CallPeer peer, {required bool video}) async {
    if (hasSession || hasIncomingCall) return;
    if (!_socketService.isConnected) {
      _reportError('call_not_connected');
      return;
    }
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
      final mediaState = await _openPreferredLocalMedia(video: video);
      _localStream = mediaState.stream;
      _isVideo = mediaState.videoEnabled;
      _isCameraOff = !_isVideo;
      await _applyAudioRoute();
      final pc = await _createPeerConnection();
      _localStream!
          .getTracks()
          .forEach((track) => pc.addTrack(track, _localStream!));

      final offer = await pc.createOffer();
      await pc.setLocalDescription(offer);
      _peerConnection = pc;
      _startIceTimeout();
      debugPrint('CALL_DEBUG OFFER SDP:\n${offer.sdp}');

      _socketService.emit('CALL_OFFER', {
        'callId': _callId,
        'target': peer.username,
        'offer': {'sdp': offer.sdp, 'type': offer.type},
        'isVideo': _isVideo,
        'caller': {
          'username': _authController.user?.username,
          'fullName': _authController.user?.displayName,
          'avatar': _authController.user?.avatar,
        }
      });
      debugPrint('CALL_DEBUG CALL_OFFER emitted callId=$_callId');
    } on CallSetupException catch (error) {
      debugPrint('CALL_DEBUG startCall() setup error=${error.errorKey}');
      _reportError(error.errorKey);
      await _resetSession(notifyRemote: true, reason: 'setup_failed');
    } catch (error) {
      debugPrint('CALL_DEBUG startCall() failed error=$error');
      _reportError('call_failed');
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
      final mediaState =
          await _openPreferredLocalMedia(video: incoming.isVideo);
      _localStream = mediaState.stream;
      _isVideo = mediaState.videoEnabled;
      _isCameraOff = !_isVideo;
      await _applyAudioRoute();
      final pc = await _createPeerConnection();

      // Add local tracks before applying the remote offer so transceivers line up
      // consistently with the web client during Web <-> Flutter negotiation.
      _localStream!
          .getTracks()
          .forEach((track) => pc.addTrack(track, _localStream!));

      await pc.setRemoteDescription(
        RTCSessionDescription(incoming.offer['sdp'], incoming.offer['type']),
      );
      // Assign _peerConnection BEFORE setting _remoteDescriptionReady so that
      // any ICE candidates arriving during the awaits below are not dropped.
      _peerConnection = pc;
      _remoteDescriptionReady = true;

      for (final candidate in _pendingCandidates) {
        await pc.addCandidate(candidate);
      }
      _pendingCandidates.clear();

      final answer = await pc.createAnswer();
      await pc.setLocalDescription(answer);
      _startIceTimeout();

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
      notifyListeners();
      debugPrint('CALL_DEBUG CALL_ANSWER emitted callId=$_callId');
    } on CallSetupException catch (error) {
      debugPrint(
        'CALL_DEBUG acceptIncomingCall() setup error=${error.errorKey}',
      );
      _reportError(error.errorKey);
      rejectIncomingCall();
    } catch (error) {
      debugPrint('CALL_DEBUG acceptIncomingCall() failed error=$error');
      _reportError('call_failed');
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
    if (_isVideo) {
      // Video call — kamerani yoq/o'chir
      _isCameraOff = !_isCameraOff;
      for (final track
          in _localStream?.getVideoTracks() ?? <MediaStreamTrack>[]) {
        track.enabled = !_isCameraOff;
      }
      notifyListeners();
    } else {
      // Audio call → videoga o'tkazish
      await _upgradeToVideo();
    }
  }

  Future<void> flipCamera() async {
    if (!_isVideo || _isCameraOff) return;
    final tracks = _localStream?.getVideoTracks() ?? [];
    if (tracks.isEmpty) return;
    try {
      await Helper.switchCamera(tracks.first);
      _isFrontCamera = !_isFrontCamera;
      notifyListeners();
    } catch (e) {
      debugPrint('CALL_DEBUG flipCamera() error=$e');
    }
  }

  Future<void> _upgradeToVideo() async {
    final pc = _peerConnection;
    final stream = _localStream;
    if (pc == null || stream == null || _targetUsername == null) return;

    _isUpgradingToVideo = true;
    notifyListeners();
    debugPrint('CALL_DEBUG _upgradeToVideo() start');

    try {
      final status = await Permission.camera.request();
      if (!status.isGranted) {
        _isUpgradingToVideo = false;
        notifyListeners();
        return;
      }

      final videoStream = await navigator.mediaDevices.getUserMedia(<String, dynamic>{
        'audio': false,
        'video': <String, dynamic>{'facingMode': 'user'},
      });
      final videoTrack = videoStream.getVideoTracks().first;
      await stream.addTrack(videoTrack);
      await pc.addTrack(videoTrack, stream);

      final offer = await pc.createOffer();
      await pc.setLocalDescription(offer);

      _socketService.emit('CALL_RENEGOTIATE', {
        'callId': _callId,
        'target': _targetUsername,
        'offer': {'sdp': offer.sdp, 'type': offer.type},
        'isVideo': true,
      });
      debugPrint('CALL_DEBUG CALL_RENEGOTIATE emitted');
    } catch (error) {
      debugPrint('CALL_DEBUG _upgradeToVideo() error=$error');
      _isUpgradingToVideo = false;
      notifyListeners();
    }
  }

  Future<void> toggleSpeaker() async {
    _isSpeakerOn = !_isSpeakerOn;
    debugPrint(
      'CALL_DEBUG toggleSpeaker() speakerOn=$_isSpeakerOn hasBluetooth=$hasBluetoothAudio hasHeadset=$hasHeadsetAudio route=$_audioRoute',
    );
    await _applyAudioRoute();
    notifyListeners();
  }

  Future<void> setAudioRoute(CallAudioRoute route) async {
    if (kIsWeb) return;
    try {
      if (route == CallAudioRoute.bluetooth) {
        await _audioChannel.invokeMethod<void>('activateBluetooth');
        _audioRoute = CallAudioRoute.bluetooth;
        _isSpeakerOn = false;
      } else if (route == CallAudioRoute.speaker) {
        _isSpeakerOn = true;
        await _applyAudioRoute();
      } else {
        _isSpeakerOn = false;
        await _applyAudioRoute();
      }
    } catch (e) {
      debugPrint('CALL_DEBUG setAudioRoute() error=$e');
    }
    notifyListeners();
  }

  Future<void> switchCallMode(bool video) async {
    if (!video || _isVideo) return;
    _reportError('call_video_fallback');
  }

  Future<void> hangUp() async {
    await _resetSession(notifyRemote: true, reason: 'hangup');
  }

  void _handlePacket(SocketPacket packet) {
    debugPrint('CALL_DEBUG packet event=${packet.event} payload=${packet.payload}');
    switch (packet.event) {
      case 'CALL_OFFER':
        final data = Map<String, dynamic>.from(packet.payload as Map? ?? {});
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
        final data = Map<String, dynamic>.from(packet.payload as Map? ?? {});
        final answer = Map<String, dynamic>.from(data['answer'] as Map? ?? {});
        final answeredAt = data['answeredAt'];
        final callId = data['callId']?.toString();
        if (callId != null && _callId != null && callId != _callId) {
          debugPrint(
              'CALL_DEBUG begona CALL_ANSWER e\'tiborsiz qoldirildi callId=$callId current=$_callId');
          break;
        }
        if (_remoteDescriptionReady) {
          debugPrint(
              'CALL_DEBUG dublikat CALL_ANSWER e\'tiborsiz qoldirildi callId=$callId');
          _state = CallSessionState.connecting;
          notifyListeners();
          break;
        }
        if (answeredAt is String) {
          _connectedAt ??= DateTime.tryParse(answeredAt)?.toLocal();
        } else if (answeredAt is num) {
          _connectedAt ??=
              DateTime.fromMillisecondsSinceEpoch(answeredAt.toInt());
        } else {
          _connectedAt ??= DateTime.now();
        }
        debugPrint('CALL_DEBUG ANSWER SDP:\n${answer['sdp']}');
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
        final data = Map<String, dynamic>.from(packet.payload as Map? ?? {});
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
        _reportError('call_rejected');
        unawaited(_resetSession());
        break;
      case 'CALL_END':
        final endData = Map<String, dynamic>.from(packet.payload as Map? ?? {});
        final reason = (endData['reason'] ?? '').toString();
        if (reason == 'connection_lost') {
          _reportError('call_connection_lost');
        } else if (_connectedAt == null &&
            (reason == 'hangup' || reason == 'disconnect_timeout')) {
          _reportError('call_missed');
        }
        unawaited(_resetSession());
        break;
      case 'CALL_BLOCKED':
        _reportError('call_blocked');
        unawaited(_resetSession());
        break;
      case 'CALL_NOT_DELIVERED':
        _reportError('call_not_delivered');
        unawaited(_resetSession());
        break;
      case 'CALL_SESSION_SYNC':
        final data = Map<String, dynamic>.from(packet.payload as Map? ?? {});
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
      case 'CALL_CONNECTED':
        final data = Map<String, dynamic>.from(packet.payload as Map? ?? {});
        final connectedAt = data['connectedAt'];
        if (connectedAt is String) {
          _connectedAt ??= DateTime.tryParse(connectedAt)?.toLocal();
        } else if (connectedAt is num) {
          _connectedAt ??=
              DateTime.fromMillisecondsSinceEpoch(connectedAt.toInt());
        } else {
          _connectedAt ??= DateTime.now();
        }
        _state = CallSessionState.connected;
        unawaited(_stopAlertTone());
        notifyListeners();
        break;

      case 'CALL_RENEGOTIATE':
        final reData = Map<String, dynamic>.from(packet.payload as Map? ?? {});
        final reCallId = reData['callId']?.toString();
        if (reCallId != null && reCallId != _callId) break;
        final reOfferMap =
            Map<String, dynamic>.from(reData['offer'] as Map? ?? {});
        final reIsVideo = reData['isVideo'] == true;
        unawaited(() async {
          final pc = _peerConnection;
          if (pc == null) return;
          try {
            await pc.setRemoteDescription(RTCSessionDescription(
              reOfferMap['sdp']?.toString() ?? '',
              reOfferMap['type']?.toString() ?? 'offer',
            ));
            if (reIsVideo && !_isVideo) {
              final videoStream = await navigator.mediaDevices
                  .getUserMedia(<String, dynamic>{
                'audio': false,
                'video': <String, dynamic>{'facingMode': 'user'},
              });
              final videoTrack = videoStream.getVideoTracks().first;
              if (_localStream != null) {
                await _localStream!.addTrack(videoTrack);
                await pc.addTrack(videoTrack, _localStream!);
              }
            }
            final reAnswer = await pc.createAnswer();
            await pc.setLocalDescription(reAnswer);
            _socketService.emit('CALL_RENEGOTIATE_ANSWER', {
              'callId': _callId,
              'target': _targetUsername,
              'answer': {'sdp': reAnswer.sdp, 'type': reAnswer.type},
            });
            if (reIsVideo && !_isVideo) {
              _isVideo = true;
              _isCameraOff = false;
              notifyListeners();
            }
          } catch (e) {
            debugPrint('CALL_DEBUG CALL_RENEGOTIATE error=$e');
          }
        }());
        break;

      case 'CALL_RENEGOTIATE_ANSWER':
        if (!_isUpgradingToVideo) break;
        final data = Map<String, dynamic>.from(packet.payload as Map? ?? {});
        final callId = data['callId']?.toString();
        if (callId != null && callId != _callId) break;
        final answerMap = Map<String, dynamic>.from(data['answer'] as Map? ?? {});
        final answer = RTCSessionDescription(
          answerMap['sdp']?.toString() ?? '',
          answerMap['type']?.toString() ?? 'answer',
        );
        unawaited(() async {
          try {
            await _peerConnection?.setRemoteDescription(answer);
            _isVideo = true;
            _isCameraOff = false;
            _isUpgradingToVideo = false;
            debugPrint('CALL_DEBUG video upgrade complete');
            notifyListeners();
          } catch (e) {
            debugPrint('CALL_DEBUG CALL_RENEGOTIATE_ANSWER error=$e');
            _isUpgradingToVideo = false;
            notifyListeners();
          }
        }());
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
    _isSpeakerOn = true;
    _hasBluetoothAudio = false;
    _hasHeadsetAudio = false;
    _isUpgradingToVideo = false;
    _audioRoute = CallAudioRoute.speaker;
    if (!preserveIncoming) {
      _incomingCall = null;
    }
  }

  Future<void> _requestMediaPermissions({required bool video}) async {
    final permissions = <Permission>[Permission.microphone];
    if (video) {
      permissions.add(Permission.camera);
    }
    final statuses = await permissions.request();
    final denied = statuses.values.any(
      (status) => !status.isGranted && !status.isLimited,
    );
    if (denied) {
      throw const CallSetupException('call_permission_denied');
    }
  }

  Future<MediaStream> _openLocalMedia({required bool video}) {
    return navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': video ? {'facingMode': 'user'} : false,
    });
  }

  Future<({MediaStream stream, bool videoEnabled})> _openPreferredLocalMedia({
    required bool video,
  }) async {
    if (!video) {
      return (stream: await _openLocalMedia(video: false), videoEnabled: false);
    }

    try {
      return (stream: await _openLocalMedia(video: true), videoEnabled: true);
    } catch (error) {
      debugPrint('CALL_DEBUG video media failed, falling back to audio: $error');
      _reportError('call_video_fallback');
      return (stream: await _openLocalMedia(video: false), videoEnabled: false);
    }
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
      debugPrint(
        'CALL_DEBUG onTrack kind=${track.kind} id=${track.id} '
        'streams=${event.streams.length} remoteStream=${_remoteStream?.id}',
      );
      if (event.streams.isNotEmpty) {
        final incoming = event.streams.first;
        if (_remoteStream == null) {
          _remoteStream = incoming;
        } else if (_remoteStream!.id != incoming.id) {
          _remoteStream = incoming;
        } else if (track.kind == 'video') {
          _remoteStream = null;
          _remoteStream = incoming;
        }
      } else {
        _remoteStream ??= await createLocalMediaStream('bootchat_remote');
        await _remoteStream!.addTrack(track);
      }
      debugPrint(
        'CALL_DEBUG onTrack done remoteStream=${_remoteStream?.id} '
        'videoTracks=${_remoteStream?.getVideoTracks().length} '
        'audioTracks=${_remoteStream?.getAudioTracks().length}',
      );
      unawaited(_markCallConnected());
      notifyListeners();
    };

    // Fallback for implementations that fire onAddStream instead of onTrack
    pc.onAddStream = (stream) {
      debugPrint('CALL_DEBUG onAddStream id=${stream.id}');
      if (_remoteStream?.id != stream.id) {
        _remoteStream = stream;
        unawaited(_markCallConnected());
        notifyListeners();
      }
    };

    pc.onIceConnectionState = (state) {
      debugPrint('CALL_DEBUG ICE state: $state');
      if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
          state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        _iceConnectTimeout?.cancel();
        _iceConnectTimeout = null;
        unawaited(_markCallConnected());
      } else if (state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
        _iceConnectTimeout?.cancel();
        _iceConnectTimeout = null;
        unawaited(_resetSession(notifyRemote: true, reason: 'connection_lost'));
      } else if (state == RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
        // Temporary disconnection — end call after 15 s if not recovered
        _iceConnectTimeout ??= Timer(const Duration(seconds: 15), () {
          if (_state != null) {
            unawaited(_resetSession(notifyRemote: true, reason: 'connection_lost'));
          }
        });
      }
    };

    pc.onConnectionState = (state) {
      debugPrint('CALL_DEBUG peer connection state: $state');
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        unawaited(_markCallConnected());
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        unawaited(_resetSession(notifyRemote: true, reason: 'connection_lost'));
      }
    };

    return pc;
  }

  Future<void> _markCallConnected() async {
    final alreadyConnected = _state == CallSessionState.connected;
    if (!_connectedSignalSent && _targetUsername != null && _callId != null) {
      _connectedSignalSent = true;
      _socketService.emit('CALL_CONNECTED', {
        'callId': _callId,
        'target': _targetUsername,
      });
    }
    _state = CallSessionState.connected;
    _connectedAt ??= DateTime.now();
    await _stopAlertTone();
    if (!alreadyConnected) await _applyAudioRoute();
    notifyListeners();
  }

  Future<void> _startOutgoingTone() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        debugPrint('CALL_DEBUG startOutgoingTone() using native tone');
        await _audioChannel.invokeMethod<void>('startOutgoingTone');
        return;
      } catch (error) {
        debugPrint('CALL_DEBUG startOutgoingTone() native failed error=$error');
      }
    }
    try {
      await _audioPlayer.stop();
      await _audioPlayer.setReleaseMode(ReleaseMode.loop);
      await _audioPlayer.play(AssetSource('sounds/dialing.wav'));
    } catch (error) {
      debugPrint('CALL_DEBUG _startOutgoingTone() asset failed error=$error');
    }
  }

  Future<void> _startIncomingTone() async {
    await _audioPlayer.stop();
    await _audioPlayer.setReleaseMode(ReleaseMode.loop);

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        debugPrint('CALL_DEBUG startIncomingTone() using native ringtone');
        await _audioChannel.invokeMethod<void>('startIncomingRingtone');
        return;
      } catch (error) {
        debugPrint('CALL_DEBUG startIncomingTone() native ringtone failed error=$error');
      }
    }

    debugPrint('CALL_DEBUG startIncomingTone() using asset ringtone fallback');
    try {
      await _audioPlayer.play(AssetSource('sounds/ringtone.wav'));
    } catch (error) {
      debugPrint('CALL_DEBUG startIncomingTone() asset ringtone failed error=$error');
    }
  }

  Future<void> _stopAlertTone() async {
    await _audioPlayer.stop();

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        await _audioChannel.invokeMethod<void>('stopIncomingRingtone');
        await _audioChannel.invokeMethod<void>('stopOutgoingTone');
      } catch (_) {}
    }
  }

  Future<void> _applyAudioRoute() async {
    if (kIsWeb) return;

    if (defaultTargetPlatform != TargetPlatform.android) {
      try {
        await Helper.setSpeakerphoneOn(_isSpeakerOn);
        _audioRoute = _isSpeakerOn
            ? CallAudioRoute.speaker
            : CallAudioRoute.earpiece;
      } catch (error) {
        debugPrint('CALL_DEBUG _applyAudioRoute() helper failed error=$error');
      }
      return;
    }

    try {
      final result = await _audioChannel.invokeMapMethod<String, dynamic>(
        'activateCallAudio',
        {
          'speakerOn': _isSpeakerOn,
        },
      );
      debugPrint('CALL_DEBUG _applyAudioRoute() result=$result');
      _syncAudioRouteInfo(result);
    } catch (error) {
      debugPrint('CALL_DEBUG _applyAudioRoute() failed error=$error');
    }
    // Sync flutter_webrtc's own audio manager with our speaker preference
    try {
      await Helper.setSpeakerphoneOn(_isSpeakerOn);
    } catch (_) {}
  }

  Future<void> _restoreAudioRoute() async {
    if (kIsWeb) return;

    if (defaultTargetPlatform != TargetPlatform.android) {
      try {
        await Helper.setSpeakerphoneOn(false);
      } catch (_) {}
      return;
    }

    try {
      await _audioChannel.invokeMethod<void>('restoreAudioRoute');
    } catch (_) {}
  }

  void _startIceTimeout() {
    _iceConnectTimeout?.cancel();
    _iceConnectTimeout = Timer(const Duration(seconds: 30), () {
      if (_state != null && _state != CallSessionState.connected) {
        debugPrint('CALL_DEBUG ICE timeout — no connection after 30s');
        unawaited(_resetSession(notifyRemote: true, reason: 'connection_lost'));
      }
    });
  }

  Future<void> _closePeerResources() async {
    _iceConnectTimeout?.cancel();
    _iceConnectTimeout = null;
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
    if (_callId == null && _targetUsername == null) return;
    final target = _targetUsername;
    final callId = _callId;
    final wasVideo = _isVideo;
    _callId = null;
    _targetUsername = null;
    final duration = _connectedAt == null
        ? 0
        : DateTime.now().difference(_connectedAt!).inSeconds;

    await _stopAlertTone();
    await _closePeerResources();
    await _restoreAudioRoute();

    _state = null;
    _incomingCall = null;
    _remotePeer = null;
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
    _connectedSignalSent = false;
  }

  void _reportError(String key) {
    _errorKey = key;
    _errorVersion += 1;
    notifyListeners();
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
