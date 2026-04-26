import 'dart:async';
import 'package:audioplayers/audioplayers.dart'; // MethodChannel o'rniga universal paket
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
    return CallPeer(username: username, displayName: displayName, avatar: json['avatar']?.toString());
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
    _audioPlayer = AudioPlayer(); // Ovoz pleyerini yoqamiz
  }

  // --- TURN SERVER (Koreya/Xalqaro ulanish uchun 100% to'g'ri config) ---
  final Map<String, dynamic> _rtcConfiguration = {
    'sdpSemantics': 'unified-plan',
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
      {
        'urls': 'turn:jamshiddin.uz:3478?transport=udp',
        'username': 'jama',
        'credential': '12345'
      },
      {
        'urls': 'turn:jamshiddin.uz:3478?transport=tcp', // Koreya provayderlari uchun TCP shart
        'username': 'jama',
        'credential': '12345'
      },
    ],
    'iceCandidatePoolSize': 10,
  };

  final SocketService _socketService;
  final AuthController _authController;
  late final StreamSubscription<SocketPacket> _subscription;
  late final AudioPlayer _audioPlayer; // Universal ovoz pleyeri

  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  final List<RTCIceCandidate> _pendingCandidates = <RTCIceCandidate>[];

  Timer? _ringingTimeout;
  CallSessionState? _state;
  CallPeer? _remotePeer;
  IncomingCallData? _incomingCall;

  bool _remoteDescriptionReady = false;
  bool _isVideo = false;
  bool _disposed = false;
  String? _callId;
  String? _targetUsername;
  DateTime? _connectedAt;

  // Getterlar
  CallSessionState? get state => _state;
  CallPeer? get remotePeer => _remotePeer;
  IncomingCallData? get incomingCall => _incomingCall;
  MediaStream? get localStream => _localStream;
  MediaStream? get remoteStream => _remoteStream;
  bool get isVideo => _isVideo;
  bool get hasSession => _state != null;
  bool get hasIncomingCall => _incomingCall != null;

  // --- OVOZ FUNKSIYALARI (Web va Mobil uchun universal) ---

  Future<void> _playTone(String fileName) async {
    try {
      await _audioPlayer.setReleaseMode(ReleaseMode.loop);
      await _audioPlayer.play(AssetSource('sounds/$fileName'));
    } catch (e) {
      debugPrint("Ovoz xatosi: $e");
    }
  }

  Future<void> _stopTone() async {
    await _audioPlayer.stop();
  }

  // --- ASOSIY MANTIQ ---

  Future<void> startCall(CallPeer peer, {required bool video}) async {
    if (hasSession || hasIncomingCall) return;
    _resetInternalState();
    _remotePeer = peer;
    _callId = 'call_${DateTime.now().millisecondsSinceEpoch}';
    _targetUsername = peer.username;
    _state = CallSessionState.calling;
    _isVideo = video;
    _notify();

    await _playTone('dialing.mp3'); // Gudoq boshlanadi

    try {
      await _ensureMediaPermissions(video);
      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': {'echoCancellation': true, 'noiseSuppression': true},
        'video': video ? {'facingMode': 'user'} : false
      });
      
      final pc = await _createPeerConnection(peer.username);
      _localStream!.getTracks().forEach((track) => pc.addTrack(track, _localStream!));
      
      final offer = await pc.createOffer({'mandatory': {'OfferToReceiveAudio': true, 'OfferToReceiveVideo': true}});
      await pc.setLocalDescription(offer);

      _socketService.emit('CALL_OFFER', {
        'callId': _callId,
        'target': peer.username,
        'caller': {
          'username': _authController.user?.username,
          'fullName': _authController.user?.displayName,
        },
        'offer': {'sdp': offer.sdp, 'type': offer.type},
        'isVideo': video,
      });

      _state = CallSessionState.ringing;
      _startRingingTimeout();
      _notify();
    } catch (e) {
      await hangUp();
    }
  }

  Future<void> acceptIncomingCall() async {
    if (_incomingCall == null) return;
    final incoming = _incomingCall!;
    await _stopTone(); // Ringtone to'xtaydi

    _remotePeer = incoming.caller;
    _callId = incoming.callId;
    _targetUsername = incoming.caller.username;
    _state = CallSessionState.connecting;
    _notify();

    try {
      await _ensureMediaPermissions(incoming.isVideo);
      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': incoming.isVideo ? {'facingMode': 'user'} : false
      });
      
      final pc = await _createPeerConnection(incoming.caller.username);
      _localStream!.getTracks().forEach((track) => pc.addTrack(track, _localStream!));

      await pc.setRemoteDescription(RTCSessionDescription(incoming.offer['sdp'], incoming.offer['type']));
      _remoteDescriptionReady = true;
      for (var c in _pendingCandidates) { await pc.addCandidate(c); }
      _pendingCandidates.clear();

      final answer = await pc.createAnswer({'mandatory': {'OfferToReceiveAudio': true, 'OfferToReceiveVideo': true}});
      await pc.setLocalDescription(answer);

      _socketService.emit('CALL_ANSWER', {
        'callId': _callId,
        'target': _targetUsername,
        'answer': {'sdp': answer.sdp, 'type': answer.type},
      });
      _notify();
    } catch (e) {
      rejectIncomingCall();
    }
  }

  void _handlePacket(SocketPacket packet) {
    final data = packet.payload is Map ? Map<String, dynamic>.from(packet.payload) : {};
    switch (packet.event) {
      case 'CALL_OFFER':
        if (hasSession) return;
        _incomingCall = IncomingCallData(
          callId: data['callId'],
          caller: CallPeer.fromMap(data['caller']),
          offer: Map<String, dynamic>.from(data['offer']),
          isVideo: data['isVideo'] == true,
        );
        _playTone('ringtone.mp3'); // Ringtone boshlanadi
        _notify();
        break;
      case 'CALL_ANSWER':
        final answer = Map<String, dynamic>.from(data['answer']);
        _peerConnection?.setRemoteDescription(RTCSessionDescription(answer['sdp'], answer['type'])).then((_) {
          _remoteDescriptionReady = true;
          for (var c in _pendingCandidates) { _peerConnection?.addCandidate(c); }
          _pendingCandidates.clear();
        });
        break;
      case 'ICE_CANDIDATE':
        final cand = Map<String, dynamic>.from(data['candidate']);
        final c = RTCIceCandidate(cand['candidate'], cand['sdpMid'], cand['sdpMLineIndex']);
        if (_remoteDescriptionReady) { _peerConnection?.addCandidate(c); } 
        else { _pendingCandidates.add(c); }
        break;
      case 'CALL_END':
      case 'CALL_REJECT':
        _resetSession();
        break;
    }
  }

  Future<RTCPeerConnection> _createPeerConnection(String target) async {
    final pc = await createPeerConnection(_rtcConfiguration);
    pc.onTrack = (event) { if (event.streams.isNotEmpty) { _remoteStream = event.streams.first; _notify(); } };
    pc.onIceCandidate = (candidate) {
      _socketService.emit('ICE_CANDIDATE', {
        'callId': _callId, 'target': target,
        'candidate': {'candidate': candidate.candidate, 'sdpMid': candidate.sdpMid, 'sdpMLineIndex': candidate.sdpMLineIndex}
      });
    };
    pc.onConnectionState = (s) {
      if (s == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _stopTone();
        _connectedAt = DateTime.now();
        _state = CallSessionState.connected;
        _notify();
      } else if (s == RTCPeerConnectionState.RTCPeerConnectionStateFailed) { hangUp(); }
    };
    _peerConnection = pc;
    return pc;
  }

  Future<void> hangUp() async {
    if (_targetUsername != null) { _socketService.emit('CALL_END', {'callId': _callId, 'target': _targetUsername}); }
    await _resetSession();
  }

  void rejectIncomingCall() {
    if (_incomingCall != null) { _socketService.emit('CALL_REJECT', {'callId': _incomingCall!.callId, 'target': _incomingCall!.caller.username}); }
    _resetSession();
  }

  Future<void> _resetSession() async {
    _ringingTimeout?.cancel();
    await _stopTone();
    await _peerConnection?.close();
    _peerConnection = null;
    _localStream?.getTracks().forEach((t) => t.stop());
    _localStream = null;
    _remoteStream = null;
    _state = null;
    _incomingCall = null;
    _notify();
  }

  void _notify() { if (!_disposed) notifyListeners(); }
  void _startRingingTimeout() { _ringingTimeout = Timer(const Duration(seconds: 45), () => hangUp()); }
  Future<void> _ensureMediaPermissions(bool v) async { await Permission.microphone.request(); if (v) await Permission.camera.request(); }
  void _resetInternalState() { _incomingCall = null; _connectedAt = null; _pendingCandidates.clear(); _remoteDescriptionReady = false; }

  @override
  void dispose() { _disposed = true; _subscription.cancel(); _resetSession(); _audioPlayer.dispose(); super.dispose(); }
}