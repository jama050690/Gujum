import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
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

class CallController extends ChangeNotifier {
  CallController({required SocketService socketService, required AuthController authController})
      : _socketService = socketService,
        _authController = authController {
    _subscription = _socketService.packets.listen(_handlePacket);
    _audioPlayer = AudioPlayer();
  }

  final Map<String, dynamic> _rtcConfiguration = {
    'sdpSemantics': 'unified-plan',
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'turn:jamshiddin.uz:3478?transport=udp', 'username': 'jama', 'credential': '12345'},
      {'urls': 'turn:jamshiddin.uz:3478?transport=tcp', 'username': 'jama', 'credential': '12345'},
    ],
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
  String? _callId;
  String? _targetUsername;
  DateTime? _connectedAt;

  // Getterlar (Overlay va UI uchun kerakli)
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
  String? get errorKey => null;
  int get errorVersion => 0;

  Future<void> startCall(CallPeer peer, {required bool video}) async {
    if (hasSession) return;
    _resetInternalState();
    _remotePeer = peer;
    _callId = 'call_${DateTime.now().millisecondsSinceEpoch}';
    _targetUsername = peer.username;
    _state = CallSessionState.calling;
    _isVideo = video;
    notifyListeners();
    await _audioPlayer.play(AssetSource('sounds/dialing.mp3'));

    try {
      await [Permission.microphone, Permission.camera].request();
      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': true, 'video': video ? {'facingMode': 'user'} : false
      });
      final pc = await createPeerConnection(_rtcConfiguration);
      _localStream!.getTracks().forEach((t) => pc.addTrack(t, _localStream!));
      
      pc.onIceCandidate = (c) => _socketService.emit('ICE_CANDIDATE', {'callId': _callId, 'target': _targetUsername, 'candidate': {'candidate': c.candidate, 'sdpMid': c.sdpMid, 'sdpMLineIndex': c.sdpMLineIndex}});
      pc.onTrack = (e) { if (e.streams.isNotEmpty) { _remoteStream = e.streams.first; notifyListeners(); } };
      
      final offer = await pc.createOffer();
      await pc.setLocalDescription(offer);
      _socketService.emit('CALL_OFFER', {'callId': _callId, 'target': peer.username, 'offer': {'sdp': offer.sdp, 'type': offer.type}, 'isVideo': video, 'caller': {'username': _authController.user?.username, 'fullName': _authController.user?.displayName}});
      _peerConnection = pc;
    } catch (_) { hangUp(); }
  }

  void _handlePacket(SocketPacket packet) {
    final data = Map<String, dynamic>.from(packet.payload as Map? ?? {});
    switch (packet.event) {
      case 'CALL_OFFER':
        _incomingCall = IncomingCallData(callId: data['callId'], caller: CallPeer.fromMap(data['caller']), offer: Map<String, dynamic>.from(data['offer']), isVideo: data['isVideo'] == true);
        _audioPlayer.play(AssetSource('sounds/ringtone.mp3'));
        notifyListeners();
        break;
      case 'CALL_ANSWER':
        final answer = Map<String, dynamic>.from(data['answer']);
        _peerConnection?.setRemoteDescription(RTCSessionDescription(answer['sdp'], answer['type'])).then((_) {
          _remoteDescriptionReady = true;
          for (var c in _pendingCandidates) _peerConnection?.addCandidate(c);
        });
        _state = CallSessionState.connected;
        _audioPlayer.stop();
        notifyListeners();
        break;
      case 'ICE_CANDIDATE':
        final cand = Map<String, dynamic>.from(data['candidate']);
        final c = RTCIceCandidate(cand['candidate'], cand['sdpMid'], cand['sdpMLineIndex']);
        if (_remoteDescriptionReady) _peerConnection?.addCandidate(c); else _pendingCandidates.add(c);
        break;
      case 'CALL_END': case 'CALL_REJECT': _resetSession(); break;
    }
  }

  Future<void> acceptIncomingCall() async {
    if (_incomingCall == null) return;
    final incoming = _incomingCall!;
    await _audioPlayer.stop();
    _remotePeer = incoming.caller;
    _callId = incoming.callId;
    _targetUsername = incoming.caller.username;
    _state = CallSessionState.connecting;
    _isVideo = incoming.isVideo;
    _incomingCall = null;
    notifyListeners();

    try {
      await [Permission.microphone, Permission.camera].request();
      _localStream = await navigator.mediaDevices.getUserMedia({'audio': true, 'video': _isVideo ? {'facingMode': 'user'} : false});
      final pc = await createPeerConnection(_rtcConfiguration);
      _localStream!.getTracks().forEach((t) => pc.addTrack(t, _localStream!));
      await pc.setRemoteDescription(RTCSessionDescription(incoming.offer['sdp'], incoming.offer['type']));
      _remoteDescriptionReady = true;
      for (var c in _pendingCandidates) { await pc.addCandidate(c); }
      _pendingCandidates.clear();
      final answer = await pc.createAnswer();
      await pc.setLocalDescription(answer);
      _socketService.emit('CALL_ANSWER', {'callId': _callId, 'target': _targetUsername, 'answer': {'sdp': answer.sdp, 'type': answer.type}});
      _peerConnection = pc;
    } catch (e) { rejectIncomingCall(); }
  }

  void rejectIncomingCall() {
    if (_incomingCall != null) _socketService.emit('CALL_REJECT', {'callId': _incomingCall!.callId, 'target': _incomingCall!.caller.username});
    _resetSession();
  }

  Future<void> toggleMute() async { _isMuted = !_isMuted; _localStream?.getAudioTracks().forEach((t) => t.enabled = !_isMuted); notifyListeners(); }
  Future<void> toggleCamera() async { _isCameraOff = !_isCameraOff; _localStream?.getVideoTracks().forEach((t) => t.enabled = !_isCameraOff); notifyListeners(); }
  Future<void> switchCallMode(bool v) async => notifyListeners();

  Future<void> hangUp() async {
    if (_targetUsername != null) _socketService.emit('CALL_END', {'callId': _callId, 'target': _targetUsername});
    await _resetSession();
  }

  Future<void> _resetSession() async {
    await _audioPlayer.stop();
    await _peerConnection?.close();
    _localStream?.getTracks().forEach((t) => t.stop());
    _peerConnection = null; _localStream = null; _remoteStream = null; _state = null; _incomingCall = null; notifyListeners();
  }

  void _resetInternalState() { _incomingCall = null; _connectedAt = null; _pendingCandidates.clear(); _remoteDescriptionReady = false; }
  @override void dispose() { _subscription.cancel(); _resetSession(); _audioPlayer.dispose(); super.dispose(); }
}