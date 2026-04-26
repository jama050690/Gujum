import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../core/network/socket_service.dart';
import '../auth/auth_controller.dart';

enum CallSessionState { calling, ringing, connecting, connected }

class CallPeer {
  const CallPeer({required this.username, required this.displayName, this.avatar});
  final String username;
  final String displayName;
  final String? avatar;

  factory CallPeer.fromMap(Map<String, dynamic> json) {
    final username = (json['username'] ?? '').toString();
    final displayName = (json['fullName'] ?? json['full_name'] ?? json['displayName'] ?? username).toString();
    return CallPeer(
      username: username, 
      displayName: displayName.isEmpty ? username : displayName, 
      avatar: json['avatar']?.toString()
    );
  }
}

class IncomingCallData {
  const IncomingCallData({required this.callId, required this.caller, required this.offer, required this.isVideo});
  final String callId;
  final CallPeer caller;
  final Map<String, dynamic> offer;
  final bool isVideo;
}

class _PreparedCallMedia {
  const _PreparedCallMedia({required this.stream, required this.videoEnabled});
  final MediaStream stream;
  final bool videoEnabled;
}

class CallController extends ChangeNotifier {
  CallController({required SocketService socketService, required AuthController authController})
      : _socketService = socketService,
        _authController = authController {
    _subscription = _socketService.packets.listen(_handlePacket);
  }

  // --- TURN SERVER SOZLAMALARI (Koreya bilan ishlash uchun) ---
  static const String _turnHost = 'jamshiddin.uz';
  static const String _turnUsername = 'jama'; // Coturn useringiz
  static const String _turnCredential = '12345'; // Coturn parolingiz

  final Map<String, dynamic> _rtcConfiguration = {
    'sdpSemantics': 'unified-plan',
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
      {
        'urls': 'turn:$_turnHost:3478?transport=udp', 
        'username': _turnUsername, 
        'credential': _turnCredential
      },
      {
        'urls': 'turn:$_turnHost:3478?transport=tcp', // Koreya provayderlari uchun TCP muhim
        'username': _turnUsername, 
        'credential': _turnCredential
      },
    ],
    'iceCandidatePoolSize': 10,
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
  CallSessionState? _state;
  CallPeer? _remotePeer;
  IncomingCallData? _incomingCall;

  bool _remoteDescriptionReady = false;
  bool _isVideo = false;
  bool _isMuted = false;
  bool _isCameraOff = false;
  bool _disposed = false;

  String? _callId;
  String? _targetUsername;
  DateTime? _connectedAt;
  String? _errorKey;
  int _errorVersion = 0;

  // Getterlar
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
  DateTime? get connectedAt => _connectedAt;

  static const MethodChannel _callAudioChannel = MethodChannel('bootchat/call_audio');

  // --- ASOSIY FUNKSIYALAR ---

  Future<void> startCall(CallPeer peer, {required bool video}) async {
    if (hasSession || hasIncomingCall) return;
    _resetInternalState();
    _remotePeer = peer;
    _callId = 'call_${DateTime.now().millisecondsSinceEpoch}';
    _targetUsername = peer.username;
    _state = CallSessionState.calling;
    _isVideo = video;
    _notify();

    try {
      await _ensureMediaPermissions(video);
      final media = await _prepareCallMedia(video);
      _localStream = media.stream;
      _isVideo = media.videoEnabled;
      
      await _configureAudioRoute(media.videoEnabled);
      
      final pc = await _createPeerConnection(peer.username);
      _localStream!.getTracks().forEach((track) => pc.addTrack(track, _localStream!));
      
      final offer = await pc.createOffer({
        'mandatory': {'OfferToReceiveAudio': true, 'OfferToReceiveVideo': true}
      });
      await pc.setLocalDescription(offer);

      _socketService.emit('CALL_OFFER', {
        'callId': _callId,
        'target': peer.username,
        'caller': {
          'username': _authController.user?.username,
          'fullName': _authController.user?.displayName,
          'avatar': _authController.user?.avatar
        },
        'offer': {'sdp': offer.sdp, 'type': offer.type},
        'isVideo': _isVideo,
      });

      _state = CallSessionState.ringing;
      _startRingingTimeout();
      _notify();
    } catch (e) {
      debugPrint("StartCall Error: $e");
      await hangUp();
    }
  }

  Future<void> acceptIncomingCall() async {
    if (_incomingCall == null) return;
    final incoming = _incomingCall!;
    await _stopIncomingRingtone();

    _remotePeer = incoming.caller;
    _callId = incoming.callId;
    _targetUsername = incoming.caller.username;
    _state = CallSessionState.connecting;
    _isVideo = incoming.isVideo;
    _incomingCall = null;
    _notify();

    try {
      await _ensureMediaPermissions(incoming.isVideo);
      final media = await _prepareCallMedia(incoming.isVideo);
      _localStream = media.stream;
      
      await _configureAudioRoute(media.videoEnabled);
      
      final pc = await _createPeerConnection(incoming.caller.username);
      _localStream!.getTracks().forEach((track) => pc.addTrack(track, _localStream!));

      await pc.setRemoteDescription(RTCSessionDescription(incoming.offer['sdp'], incoming.offer['type']));
      _remoteDescriptionReady = true;
      
      for (var c in _pendingCandidates) { await pc.addCandidate(c); }
      _pendingCandidates.clear();

      final answer = await pc.createAnswer({
        'mandatory': {'OfferToReceiveAudio': true, 'OfferToReceiveVideo': true}
      });
      await pc.setLocalDescription(answer);

      _socketService.emit('CALL_ANSWER', {
        'callId': _callId,
        'target': _targetUsername,
        'answer': {'sdp': answer.sdp, 'type': answer.type},
      });
      _notify();
    } catch (e) {
      debugPrint("AcceptCall Error: $e");
      rejectIncomingCall();
    }
  }

  void _handlePacket(SocketPacket packet) {
    final data = packet.payload is Map ? Map<String, dynamic>.from(packet.payload) : {};
    
    switch (packet.event) {
      case 'CALL_OFFER':
        if (hasSession) return;
        _incomingCall = IncomingCallData(
          callId: data['callId'] ?? '',
          caller: CallPeer.fromMap(data['caller']),
          offer: Map<String, dynamic>.from(data['offer']),
          isVideo: data['isVideo'] == true,
        );
        _startIncomingRingtone();
        _notify();
        break;

      case 'CALL_ANSWER':
        if (_peerConnection == null) return;
        final answer = Map<String, dynamic>.from(data['answer']);
        _peerConnection!.setRemoteDescription(RTCSessionDescription(answer['sdp'], answer['type'])).then((_) {
          _remoteDescriptionReady = true;
          for (var c in _pendingCandidates) { _peerConnection!.addCandidate(c); }
          _pendingCandidates.clear();
        });
        break;

      case 'ICE_CANDIDATE':
        final candData = Map<String, dynamic>.from(data['candidate']);
        final candidate = RTCIceCandidate(candData['candidate'], candData['sdpMid'], candData['sdpMLineIndex']);
        if (_remoteDescriptionReady) {
          _peerConnection?.addCandidate(candidate);
        } else {
          _pendingCandidates.add(candidate);
        }
        break;

      case 'CALL_END':
      case 'CALL_REJECT':
        _resetSession();
        break;
    }
  }

  Future<RTCPeerConnection> _createPeerConnection(String target) async {
    final pc = await createPeerConnection(_rtcConfiguration);
    
    pc.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams.first;
        _notify();
      }
    };

    pc.onIceCandidate = (candidate) {
      _socketService.emit('ICE_CANDIDATE', {
        'callId': _callId,
        'target': target,
        'candidate': {
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex
        }
      });
    };

    pc.onConnectionState = (state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _markConnected();
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        hangUp();
      }
    };

    _peerConnection = pc;
    return pc;
  }

  // --- YORDAMCHI METODLAR ---
  
  void rejectIncomingCall() {
    if (_incomingCall != null) {
      _socketService.emit('CALL_REJECT', {'callId': _incomingCall!.callId, 'target': _incomingCall!.caller.username});
    }
    _resetSession();
  }

  Future<void> hangUp() async {
    if (_targetUsername != null) {
      _socketService.emit('CALL_END', {'callId': _callId, 'target': _targetUsername});
    }
    await _resetSession();
  }

  Future<void> _resetSession() async {
    _ringingTimeout?.cancel();
    await _stopIncomingRingtone();
    await _peerConnection?.close();
    _peerConnection = null;
    _localStream?.getTracks().forEach((t) => t.stop());
    _localStream = null;
    _remoteStream = null;
    _state = null;
    _incomingCall = null;
    _notify();
  }

  void _markConnected() {
    _connectedAt = DateTime.now();
    _state = CallSessionState.connected;
    _notify();
  }

  void _notify() { if (!_disposed) notifyListeners(); }

  Future<void> _configureAudioRoute(bool v) async {
    try { await Helper.setSpeakerphoneOn(v); } catch (_) {}
  }

  Future<void> _ensureMediaPermissions(bool v) async {
    await Permission.microphone.request();
    if (v) await Permission.camera.request();
  }

  Future<_PreparedCallMedia> _prepareCallMedia(bool v) async {
    final s = await navigator.mediaDevices.getUserMedia({
      'audio': {'echoCancellation': true, 'noiseSuppression': true},
      'video': v ? {'facingMode': 'user', 'width': 640, 'height': 480} : false
    });
    return _PreparedCallMedia(stream: s, videoEnabled: v);
  }

  void _startRingingTimeout() {
    _ringingTimeout?.cancel();
    _ringingTimeout = Timer(const Duration(seconds: 45), () => hangUp());
  }

  Future<void> _startIncomingRingtone() async {
    try { await _callAudioChannel.invokeMethod('startIncomingRingtone'); } catch (_) {}
  }

  Future<void> _stopIncomingRingtone() async {
    try { await _callAudioChannel.invokeMethod('stopIncomingRingtone'); } catch (_) {}
  }

  void _resetInternalState() {
    _incomingCall = null;
    _connectedAt = null;
    _pendingCandidates.clear();
    _remoteDescriptionReady = false;
  }

  @override
  void dispose() {
    _disposed = true;
    _subscription.cancel();
    _resetSession();
    super.dispose();
  }
}