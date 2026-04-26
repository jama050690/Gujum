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
    return CallPeer(username: username, displayName: displayName.isEmpty ? username : displayName, avatar: json['avatar']?.toString());
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

  static const String _turnHost = 'jamshiddin.uz';
  static const String _turnUsername = 'jama';
  static const String _turnCredential = '12345';

  final Map<String, dynamic> _rtcConfiguration = {
    'sdpSemantics': 'unified-plan',
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'turn:$_turnHost:3478?transport=udp', 'username': _turnUsername, 'credential': _turnCredential},
      {'urls': 'turn:$_turnHost:3478?transport=tcp', 'username': _turnUsername, 'credential': _turnCredential},
    ],
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
  String? get errorKey => _errorKey;
  int get errorVersion => _errorVersion;

  static const MethodChannel _callAudioChannel = MethodChannel('bootchat/call_audio');

  Future<void> startCall(CallPeer peer, {required bool video}) async {
    if (hasSession || hasIncomingCall) return;
    _resetInternalState();
    _remotePeer = peer;
    _callId = '${_authController.user?.username}-${peer.username}-${DateTime.now().millisecondsSinceEpoch}';
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
      for (final track in _localStream!.getTracks()) { await pc.addTrack(track, _localStream!); }
      final offer = await pc.createOffer({'mandatory': {'OfferToReceiveAudio': true, 'OfferToReceiveVideo': true}});
      await pc.setLocalDescription(offer);
      _socketService.emit('CALL_OFFER', {
        'callId': _callId, 'target': peer.username,
        'caller': {'username': _authController.user?.username, 'fullName': _authController.user?.displayName, 'avatar': _authController.user?.avatar},
        'offer': {'sdp': offer.sdp, 'type': offer.type}, 'isVideo': _isVideo,
      });
      _state = CallSessionState.ringing;
      _startRingingTimeout();
      _notify();
    } catch (e) { await hangUp(); _publishError('call_failed'); }
  }

  Future<void> switchCallMode(bool toVideo) async {
    if (_peerConnection == null || !hasSession) return;
    try {
      await _ensureMediaPermissions(toVideo);
      final media = await _prepareCallMedia(toVideo);
      _localStream?.getTracks().forEach((t) => t.stop());
      _localStream = media.stream;
      _isVideo = media.videoEnabled;
      _isCameraOff = false;
      await _configureAudioRoute(_isVideo);
      final senders = await _peerConnection!.getSenders();
      final vTrack = _isVideo ? _localStream!.getVideoTracks().first : null;
      for (var s in senders) { if (s.track?.kind == 'video') await s.replaceTrack(vTrack); }
      _socketService.emit('SWITCH_CALL_MODE', {'callId': _callId, 'target': _targetUsername, 'isVideo': _isVideo});
      _notify();
    } catch (e) { _publishError('mode_switch_failed'); }
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
      _isVideo = media.videoEnabled;
      await _configureAudioRoute(media.videoEnabled);
      final pc = await _createPeerConnection(incoming.caller.username);
      for (final track in _localStream!.getTracks()) { await pc.addTrack(track, _localStream!); }
      await pc.setRemoteDescription(RTCSessionDescription(incoming.offer['sdp'], incoming.offer['type']));
      _remoteDescriptionReady = true;
      for (var c in _pendingCandidates) { await pc.addCandidate(c); }
      _pendingCandidates.clear();
      final answer = await pc.createAnswer({'mandatory': {'OfferToReceiveAudio': true, 'OfferToReceiveVideo': true}});
      await pc.setLocalDescription(answer);
      _socketService.emit('CALL_ANSWER', {
        'callId': _callId, 'target': _targetUsername, 'answer': {'sdp': answer.sdp, 'type': answer.type},
        'isVideo': _isVideo, 'user': {'username': _authController.user?.username, 'full_name': _authController.user?.displayName, 'avatar': _authController.user?.avatar}
      });
      _notify();
    } catch (e) { rejectIncomingCall(); }
  }

  void rejectIncomingCall() {
    if (_incomingCall != null) { _socketService.emit('CALL_REJECT', {'callId': _incomingCall!.callId, 'target': _incomingCall!.caller.username}); }
    _stopIncomingRingtone();
    _incomingCall = null;
    _notify();
  }

  Future<void> hangUp() async {
    if (_targetUsername != null) { _socketService.emit('CALL_END', {'callId': _callId, 'target': _targetUsername}); }
    await _resetSession();
  }

  Future<void> toggleMute() async {
    if (_localStream == null) return;
    _isMuted = !_isMuted;
    for (var t in _localStream!.getAudioTracks()) { t.enabled = !_isMuted; }
    _notify();
  }

  Future<void> toggleCamera() async {
    if (_localStream == null || !_isVideo) return;
    _isCameraOff = !_isCameraOff;
    for (var t in _localStream!.getVideoTracks()) { t.enabled = !_isCameraOff; }
    _notify();
  }

  // --- INTERNAL HANDLERS (Missing in your last copy) ---

  void _handlePacket(SocketPacket packet) {
    final Map<String, dynamic> data = packet.payload is Map ? Map<String, dynamic>.from(packet.payload) : {};
    switch (packet.event) {
      case 'CALL_OFFER': _handleCallOffer(data); break;
      case 'CALL_ANSWER': _handleCallAnswer(data); break;
      case 'ICE_CANDIDATE': _handleIceCandidate(data); break;
      case 'SWITCH_CALL_MODE': if (data['callId'] == _callId) { _isVideo = data['isVideo'] == true; _notify(); } break;
      case 'CALL_END': case 'CALL_REJECT': _handleRemoteEnded(); break;
    }
  }

  void _handleCallOffer(Map<String, dynamic> data) {
    if (hasSession) return;
    _incomingCall = IncomingCallData(
      callId: data['callId'] ?? '', 
      caller: CallPeer.fromMap(data['caller'] is Map ? Map<String, dynamic>.from(data['caller']) : {}), 
      offer: Map<String, dynamic>.from(data['offer'] ?? {}), 
      isVideo: data['isVideo'] == true
    );
    _startIncomingRingtone();
    _notify();
  }

  Future<void> _handleCallAnswer(Map<String, dynamic> data) async {
    if (_peerConnection == null) return;
    final answer = Map<String, dynamic>.from(data['answer'] ?? {});
    await _peerConnection!.setRemoteDescription(RTCSessionDescription(answer['sdp'], answer['type']));
    _remoteDescriptionReady = true;
    for (var c in _pendingCandidates) { await _peerConnection!.addCandidate(c); }
    _pendingCandidates.clear();
  }

  Future<void> _handleIceCandidate(Map<String, dynamic> data) async {
    final cand = Map<String, dynamic>.from(data['candidate'] ?? {});
    final c = RTCIceCandidate(cand['candidate'], cand['sdpMid'], cand['sdpMLineIndex']);
    if (_remoteDescriptionReady) { 
      await _peerConnection?.addCandidate(c); 
    } else { 
      _pendingCandidates.add(c); 
    }
  }

  Future<RTCPeerConnection> _createPeerConnection(String target) async {
    final pc = await createPeerConnection(_rtcConfiguration);
    pc.onTrack = (event) { if (event.streams.isNotEmpty) { _remoteStream = event.streams.first; _notify(); } };
    pc.onIceCandidate = (c) {
      _socketService.emit('ICE_CANDIDATE', {'callId': _callId, 'target': target, 'candidate': {'candidate': c.candidate, 'sdpMid': c.sdpMid, 'sdpMLineIndex': c.sdpMLineIndex}});
    };
    pc.onConnectionState = (s) {
      if (s == RTCPeerConnectionState.RTCPeerConnectionStateConnected) { _markConnected(); }
      else if (s == RTCPeerConnectionState.RTCPeerConnectionStateFailed) { hangUp(); }
    };
    _peerConnection = pc;
    return pc;
  }

  Future<void> _resetSession() async {
    _ringingTimeout?.cancel(); await _stopIncomingRingtone(); await _peerConnection?.close();
    _peerConnection = null; _localStream?.getTracks().forEach((t) => t.stop());
    _localStream = null; _remoteStream = null; _state = null; _notify();
  }

  void _markConnected() { _stopIncomingRingtone(); _connectedAt = DateTime.now(); _state = CallSessionState.connected; _notify(); }
  void _notify() { if (!_disposed) notifyListeners(); }
  void _publishError(String k) { _errorKey = k; _errorVersion++; _notify(); _clearErrorTimer?.cancel(); _clearErrorTimer = Timer(const Duration(seconds: 3), () { _errorKey = null; _notify(); }); }
  void _handleRemoteEnded() => _resetSession();
  void _startRingingTimeout() { _ringingTimeout?.cancel(); _ringingTimeout = Timer(const Duration(seconds: 30), () => hangUp()); }
  Future<void> _startIncomingRingtone() async { try { await _callAudioChannel.invokeMethod('startIncomingRingtone'); } catch (_) {} }
  Future<void> _stopIncomingRingtone() async { try { await _callAudioChannel.invokeMethod('stopIncomingRingtone'); } catch (_) {} }
  Future<void> _configureAudioRoute(bool v) async { try { await Helper.setSpeakerphoneOn(v); } catch (_) {} }
  Future<void> _ensureMediaPermissions(bool v) async { await Permission.microphone.request(); if (v) await Permission.camera.request(); }
  void _resetInternalState() { _incomingCall = null; _connectedAt = null; _pendingCandidates.clear(); _remoteDescriptionReady = false; }
  Future<_PreparedCallMedia> _prepareCallMedia(bool v) async {
    final s = await navigator.mediaDevices.getUserMedia({'audio': {'echoCancellation': true}, 'video': v ? {'facingMode': 'user'} : false});
    return _PreparedCallMedia(stream: s, videoEnabled: v);
  }
  @override void dispose() { _disposed = true; _subscription.cancel(); _resetSession(); super.dispose(); }
}