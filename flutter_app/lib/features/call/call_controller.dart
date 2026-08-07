import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/network/socket_service.dart';
import '../auth/auth_controller.dart';
import 'call_kit_service.dart';

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

class CallController extends ChangeNotifier with WidgetsBindingObserver {
  CallController({
    required SocketService socketService,
    required AuthController authController,
  })  : _socketService = socketService,
        _authController = authController {
    _subscription = _socketService.packets.listen(_handlePacket);
    _callKitSub = CallKitService.instance.events.listen(_handleCallKitEvent);
    // Qo'ng'iroq davomida quloqchin ulansa/uzilsa native tomon xabar beradi.
    _audioChannel.setMethodCallHandler((call) async {
      if (call.method != 'audioRouteChanged') return null;
      final info = (call.arguments as Map?)?.map(
        (key, value) => MapEntry(key.toString(), value),
      );
      if (info == null) return null;
      debugPrint('CALL_DEBUG audioRouteChanged $info');
      _syncAudioRouteInfo(info);
      notifyListeners();
      return null;
    });
    _audioPlayer = AudioPlayer();
    WidgetsBinding.instance.addObserver(this);
  }

  static const MethodChannel _audioChannel =
      MethodChannel('gujum/call_audio');

  final Map<String, dynamic> _rtcConfiguration = {
    'sdpSemantics': 'unified-plan',
    'iceTransportPolicy': 'all',
    'iceServers': [
      // STUN first. Without it the only candidates we can ever gather are host
      // (same-LAN only) and relay — so any TURN hiccup left ICE with no path at
      // all and the call sat in "connecting" until the 30s timeout. STUN lets
      // two peers connect directly whenever NAT allows, and keeps TURN as the
      // fallback relay it is meant to be rather than a single point of failure.
      {
        'urls': [
          'stun:stun.l.google.com:19302',
          'stun:stun1.l.google.com:19302',
        ],
      },
      {
        'urls': [
          'turn:gujum.jamshiddin.uz:3478?transport=udp',
          'turn:gujum.jamshiddin.uz:3478?transport=tcp',
          'turns:gujum.jamshiddin.uz:5349',
        ],
        'username': 'bootchat',
        'credential': 'Bootchat2024!',
      },
    ],
    'iceCandidatePoolSize': 10,
  };

  final SocketService _socketService;
  final AuthController _authController;
  late final StreamSubscription<SocketPacket> _subscription;
  late final StreamSubscription<({String action, String callId})> _callKitSub;
  late final AudioPlayer _audioPlayer;

  String? _pendingAutoAcceptCallId;
  String? _pendingDeclinedCallId;

  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  MediaStream? _upgradeVideoStream;
  final List<RTCIceCandidate> _pendingCandidates = <RTCIceCandidate>[];
  Timer? _iceConnectTimeout;
  Timer? _ringingTimeout;

  CallSessionState? _state;
  CallPeer? _remotePeer;
  IncomingCallData? _incomingCall;
  bool _remoteDescriptionReady = false;
  bool _connectedSignalSent = false;
  bool _isVideo = false;
  bool _isMuted = false;
  bool _isCameraOff = false;
  bool _toneActive = false;
  bool _isSpeakerOn = true;
  // _isSpeakerOn starts true as a *default*, not as a choice the user made.
  // Only a deliberate tap on the speaker control may outrank a plugged-in
  // headset — otherwise the session default silently hijacks call audio to the
  // loudspeaker even though an earphone is connected.
  bool _speakerExplicit = false;
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
  int _remoteStreamVersion = 0;
  int _localStreamVersion = 0;

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
  int get remoteStreamVersion => _remoteStreamVersion;
  int get localStreamVersion => _localStreamVersion;
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
      await _applyAudioRoute();
      final mediaState = await _openPreferredLocalMedia(video: video);
      _localStream = mediaState.stream;
      _isVideo = mediaState.videoEnabled;
      _isCameraOff = !_isVideo;
      final pc = await _createPeerConnection();
      for (final track in _localStream!.getTracks()) {
        await pc.addTrack(track, _localStream!);
      }

      final offer = await pc.createOffer();
      await pc.setLocalDescription(offer);
      _peerConnection = pc;
      _startRingingTimeout();
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
    // Ringing fazasida kelgan caller ICE kandidatlarini saqlash.
    // _prepareForNewSession() → _resetInternalState() ularni o'chiradi,
    // lekin yangi PC uchun bu kandidatlar kerak.
    final savedCandidates = List<RTCIceCandidate>.from(_pendingCandidates);
    await _stopAlertTone();
    // Ringtone to'xtaganda audio buffer shovqin bermasligi uchun qisqa kutish.
    await Future.delayed(const Duration(milliseconds: 150));
    await _prepareForNewSession(
        video: incoming.isVideo, preserveIncoming: true);
    _pendingCandidates.addAll(savedCandidates);
    _remotePeer = incoming.caller;
    _callId = incoming.callId;
    _targetUsername = incoming.caller.username;
    _state = CallSessionState.connecting;
    _incomingCall = null;
    notifyListeners();

    // Callkit incoming notification ni yashiramiz (in-app qabul bo'lsa)
    unawaited(CallKitService.hideIncoming(incoming.callId));

    try {
      await _requestMediaPermissions(video: incoming.isVideo);

      // PC ni darhol yaratamiz — ICE candidate hodisalari ro'yxatdan o'tadi.
      // setConnected/Telecom CALL_ANSWER dan KEYIN chaqiriladi: Telecom audio
      // tranzitsiyasi socket'ni qisqa uzishi mumkin, bu ICE kandidat yo'qolishiga
      // olib keladi. CALL_ANSWER avval yuborilsa bu muammo bo'lmaydi.
      final pc = await _createPeerConnection();

      // Remote description darhol o'rnatamiz — kamera ochilishini kutmaymiz
      await pc.setRemoteDescription(
        RTCSessionDescription(incoming.offer['sdp'], incoming.offer['type']),
      );

      // Endi kamerani ochamiz (remote desc va ICE bilan parallel)
      final mediaState =
          await _openPreferredLocalMedia(video: incoming.isVideo);
      _localStream = mediaState.stream;
      _isVideo = mediaState.videoEnabled;
      _isCameraOff = !_isVideo;

      for (final track in _localStream!.getTracks()) {
        await pc.addTrack(track, _localStream!);
      }

      // Faqat local track bo'lgan transceiver uchun SendRecv o'rnatamiz.
      // Audio call da video transceiverni Inactive qilamiz — aks holda callee
      // video yuborishga urinadi va caller tomonida streams=0 onTrack xatosi chiqadi.
      for (final t in await pc.getTransceivers()) {
        final hasLocalTrack = t.sender.track != null;
        await t.setDirection(
          (!incoming.isVideo && !hasLocalTrack)
              ? TransceiverDirection.Inactive
              : TransceiverDirection.SendRecv,
        );
      }

      _peerConnection = pc;
      _remoteDescriptionReady = true;

      for (final candidate in _pendingCandidates) {
        await pc.addCandidate(candidate);
      }
      _pendingCandidates.clear();

      final rawAnswer = await pc.createAnswer();
      // flutter_webrtc createAnswer() ba'zan audio uchun a=recvonly chiqaradi — bu bug.
      // Faqat recvonly ni tuzatamiz; inactive video uchun intentional.
      final fixedSdp = (rawAnswer.sdp ?? '')
          .replaceAll('a=recvonly', 'a=sendrecv');
      final answer = RTCSessionDescription(fixedSdp, rawAnswer.type);
      await pc.setLocalDescription(answer);
      _startIceTimeout();
      debugPrint('CALL_DEBUG ANSWER SDP (fixed):\n${answer.sdp}');

      // CALL_ANSWER ni Telecom handoff DAN OLDIN yuboramiz.
      // setConnected() → Telecom audio tranzitsiyasi → socket qisqa uzilishi mumkin.
      // Agar CALL_ANSWER o'sha paytda yuborilmagan bo'lsa, server call'ni hali
      // "ringing" deb biladi va socket qayta ulanganda CALL_OFFER yana jo'natadi
      // (cheksiz qo'ng'iroq davri). CALL_ANSWER avval yetkazilsa bu muammo yo'qoladi.
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

      // Telecom audio handoff
      await _applyAudioRoute();
      await CallKitService.setConnected(incoming.callId);
      await Future.delayed(const Duration(milliseconds: 500));
      await _applyAudioRoute();
    } on CallSetupException catch (error) {
      debugPrint(
        'CALL_DEBUG acceptIncomingCall() setup error=${error.errorKey}',
      );
      _reportError(error.errorKey);
      // _incomingCall allaqachon null — rejectIncomingCall callerni xabardor qilmaydi.
      // _resetSession(notifyRemote: true) CALL_END yuboradi, caller "Ulanmoqda"da qolmaydi.
      await _resetSession(notifyRemote: true, reason: 'setup_failed');
    } catch (error) {
      debugPrint('CALL_DEBUG acceptIncomingCall() failed error=$error');
      _reportError('call_failed');
      await _resetSession(notifyRemote: true, reason: 'setup_failed');
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

      // Eski upgrade stream ni tozalash (qayta urinish holatida)
      _upgradeVideoStream?.getVideoTracks().forEach((t) => t.stop());
      _upgradeVideoStream = await navigator.mediaDevices.getUserMedia(<String, dynamic>{
        'audio': false,
        'video': <String, dynamic>{'facingMode': 'user'},
      });
      final videoTrack = _upgradeVideoStream!.getVideoTracks().first;
      await stream.addTrack(videoTrack);
      await pc.addTrack(videoTrack, stream);
      _localStreamVersion++;
      // flutter_webrtc does not always promote recvonly/inactive → sendrecv
      // when addTrack is called; force SendRecv so the offer includes our video.
      for (final tr in await pc.getTransceivers()) {
        if (tr.sender.track?.kind == 'video') {
          await tr.setDirection(TransceiverDirection.SendRecv);
          break;
        }
      }

      final offer = await pc.createOffer();
      await pc.setLocalDescription(offer);
      debugPrint('CALL_DEBUG RENEGOTIATE OFFER SDP:\n${offer.sdp}');

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
    // Deliberate tap — from here on the user's choice outranks the headset.
    _speakerExplicit = true;
    debugPrint(
      'CALL_DEBUG toggleSpeaker() speakerOn=$_isSpeakerOn hasBluetooth=$hasBluetoothAudio hasHeadset=$hasHeadsetAudio route=$_audioRoute',
    );
    await _applyAudioRoute();
    notifyListeners();
  }

  Future<void> setAudioRoute(CallAudioRoute route) async {
    if (kIsWeb) return;
    // Picking a route from the sheet is always deliberate.
    _speakerExplicit = true;
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
        // Background holatda decline bosilgan — bu callni rad etamiz
        final offCallId = (data['callId'] ?? '').toString();
        if (_pendingDeclinedCallId != null && _pendingDeclinedCallId == offCallId) {
          _pendingDeclinedCallId = null;
          _socketService.emit('CALL_REJECT', {
            'callId': offCallId,
            'target': Map<String, dynamic>.from(
                data['caller'] as Map? ?? {})['username'],
            'isVideo': data['isVideo'] == true,
          });
          unawaited(CallKitService.endAllCalls());
          break;
        }
        if (hasSession || hasIncomingCall) {
          final dupCallId = (data['callId'] ?? '').toString();
          // Xuddi shu callId bo'lsa — duplikat (CALL_SESSION_SYNC + CALL_OFFER birga keldi),
          // CALL_REJECT yubormaslik kerak — aks holda caller qo'ng'iroqdan chiqib ketadi.
          if (dupCallId == _callId || dupCallId == _incomingCall?.callId) {
            break;
          }
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

        // Callkit orqali qabul qilingan bo'lsa — avtomatik javob berish
        if (_pendingAutoAcceptCallId == _incomingCall!.callId) {
          _pendingAutoAcceptCallId = null;
          _state = CallSessionState.connecting;
          notifyListeners();
          unawaited(acceptIncomingCall());
          break;
        }

        _state = CallSessionState.ringing;
        _toneActive = true;
        notifyListeners();

        // Background holatda callkit ko'rsatish (u o'zi ringtone o'ynaydi)
        // Foreground da esa o'zimizning UI + ringtone ishlatamiz
        final lifecycle = WidgetsBinding.instance.lifecycleState;
        if (lifecycle != AppLifecycleState.resumed) {
          unawaited(CallKitService.showIncoming(
            callId: _incomingCall!.callId,
            callerName: _incomingCall!.caller.displayName,
            callerUsername: _incomingCall!.caller.username,
            isVideo: _incomingCall!.isVideo,
          ));
        } else {
          _startIncomingTone();
        }
        break;
      case 'CALL_ANSWER':
        final data = Map<String, dynamic>.from(packet.payload as Map? ?? {});
        final answer = Map<String, dynamic>.from(data['answer'] as Map? ?? {});
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
        _ringingTimeout?.cancel();
        _ringingTimeout = null;
        _startIceTimeout();
        _connectedAt ??= DateTime.now();
        debugPrint('CALL_DEBUG ANSWER SDP:\n${answer['sdp']}');
        final sessionCallId = _callId;
        // Avval toneni to'liq to'xtatamiz — keyin setRemoteDescription.
        // ToneGenerator audio bufferi to'liq tozalanmasa WebRTC audiosi bilan aralashib shovqin beradi.
        unawaited(() async {
          await _stopAlertTone();
          await Future.delayed(const Duration(milliseconds: 150));
          if (_callId != sessionCallId) return;
          await _peerConnection?.setRemoteDescription(
              RTCSessionDescription(answer['sdp'], answer['type']));
          if (_callId != sessionCallId) return;
          _remoteDescriptionReady = true;
          for (final candidate in _pendingCandidates) {
            await _peerConnection?.addCandidate(candidate);
          }
          _pendingCandidates.clear();
          _state = CallSessionState.connecting;
          notifyListeners();
        }());
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
        final rejectData =
            Map<String, dynamic>.from(packet.payload as Map? ?? {});
        final rejectCallId = rejectData['callId']?.toString();
        if (rejectCallId != null && _callId != null && rejectCallId != _callId) {
          debugPrint(
              'CALL_DEBUG eski CALL_REJECT etiborga olinmadi rejectCallId=$rejectCallId current=$_callId');
          break;
        }
        _reportError('call_rejected');
        unawaited(_resetSession());
        break;
      case 'CALL_END':
        final endData = Map<String, dynamic>.from(packet.payload as Map? ?? {});
        final endCallId = endData['callId']?.toString();
        if (endCallId != null && _callId != null && endCallId != _callId) {
          debugPrint(
              'CALL_DEBUG eski CALL_END etiborga olinmadi endCallId=$endCallId current=$_callId');
          break;
        }
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
        final direction = (data['direction'] ?? '').toString();
        final status = (data['status'] ?? '').toString();
        // incoming + ringing: agar allaqachon incomingCall bor bo'lsa — skip.
        // Aks holda (reconnect holati) offer bilan birga kelsa — incomingCall tiklanadi.
        if (direction == 'incoming' && status == 'ringing') {
          if (hasIncomingCall || hasSession) break;
          final offerRaw = data['offer'];
          if (offerRaw == null) break;
          final offer = Map<String, dynamic>.from(offerRaw as Map? ?? {});
          if ((offer['sdp'] as String?)?.isEmpty ?? true) break;
          final peer = CallPeer.fromMap(
              Map<String, dynamic>.from(data['peer'] as Map? ?? {}));
          _incomingCall = IncomingCallData(
            callId: (data['callId'] ?? '').toString(),
            caller: peer,
            offer: offer,
            isVideo: data['isVideo'] == true,
          );
          _remotePeer = peer;
          // Notification orqali "Answer" bosilgan bo'lsa — avtomatik qabul qilish
          if (_pendingAutoAcceptCallId == _incomingCall!.callId) {
            _pendingAutoAcceptCallId = null;
            _state = CallSessionState.connecting;
            notifyListeners();
            unawaited(acceptIncomingCall());
            break;
          }
          _state = CallSessionState.ringing;
          _toneActive = true;
          notifyListeners();
          final lifecycle = WidgetsBinding.instance.lifecycleState;
          if (lifecycle != AppLifecycleState.resumed) {
            unawaited(CallKitService.showIncoming(
              callId: _incomingCall!.callId,
              callerName: _incomingCall!.caller.displayName,
              callerUsername: _incomingCall!.caller.username,
              isVideo: _incomingCall!.isVideo,
            ));
          } else {
            _startIncomingTone();
          }
          break;
        }
        final peer = CallPeer.fromMap(
            Map<String, dynamic>.from(data['peer'] as Map? ?? {}));
        _remotePeer = peer;
        _callId = data['callId']?.toString();
        _targetUsername = peer.username;
        // Server video upgrade ni bilmaydi — _isVideo ni false ga qaytarmaymiz.
        // Agar server true desa qabul qilamiz; false desa mavjud holatni saqlaymiz.
        if (data['isVideo'] == true) _isVideo = true;
        _state = status == 'connected'
            ? CallSessionState.connected
            : CallSessionState.connecting;
        final startedAt = data['startedAt'];
        if (startedAt is String) {
          _connectedAt = DateTime.tryParse(startedAt);
        } else if (startedAt is num) {
          _connectedAt = DateTime.fromMillisecondsSinceEpoch(startedAt.toInt());
        }
        notifyListeners();
        // PC yo'q va status ringing — qayta offer yuboramiz
        if (status != 'connected' && _peerConnection == null) {
          unawaited(_restartOutgoingOffer());
        }
        // Status connected va server answer saqlab qo'ygan — remote desc o'rnatamiz
        if (status == 'connected' && data['answer'] != null) {
          final answerMap =
              Map<String, dynamic>.from(data['answer'] as Map? ?? {});
          unawaited(() async {
            final pc = _peerConnection;
            if (pc == null) return;
            try {
              await pc.setRemoteDescription(RTCSessionDescription(
                answerMap['sdp']?.toString() ?? '',
                answerMap['type']?.toString() ?? 'answer',
              ));
              _startIceTimeout();
              debugPrint('CALL_DEBUG CALL_SESSION_SYNC: remote desc set from buffered answer');
            } catch (e) {
              debugPrint('CALL_DEBUG CALL_SESSION_SYNC answer error=$e');
            }
          }());
        }
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
              _upgradeVideoStream?.getVideoTracks().forEach((t) => t.stop());
              _upgradeVideoStream = await navigator.mediaDevices
                  .getUserMedia(<String, dynamic>{
                'audio': false,
                'video': <String, dynamic>{'facingMode': 'user'},
              });
              final videoTrack = _upgradeVideoStream!.getVideoTracks().first;
              if (_localStream != null) {
                await _localStream!.addTrack(videoTrack);
                await pc.addTrack(videoTrack, _localStream!);
                _localStreamVersion++;
                // Force video transceiver to SendRecv so callee also sends video.
                for (final tr in await pc.getTransceivers()) {
                  if (tr.sender.track?.kind == 'video') {
                    await tr.setDirection(TransceiverDirection.SendRecv);
                    break;
                  }
                }
              }
            }
            final rawAnswer = await pc.createAnswer();
            // flutter_webrtc may produce a=recvonly for video — fix it.
            final fixedSdp = (rawAnswer.sdp ?? '')
                .replaceAll('a=recvonly', 'a=sendrecv');
            final reAnswer = RTCSessionDescription(fixedSdp, rawAnswer.type);
            await pc.setLocalDescription(reAnswer);
            _socketService.emit('CALL_RENEGOTIATE_ANSWER', {
              'callId': _callId,
              'target': _targetUsername,
              'answer': {'sdp': reAnswer.sdp, 'type': reAnswer.type},
            });
            if (reIsVideo && !_isVideo) {
              await _rebuildRemoteStream();
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
            await _rebuildRemoteStream();
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
    _speakerExplicit = false;
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
      'audio': {
        'echoCancellation': true,
        'noiseSuppression': true,
        'autoGainControl': true,
        'googEchoCancellation': true,
        'googNoiseSuppression': true,
        'googAutoGainControl': true,
        'googHighpassFilter': true,
      },
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
        // streams=0 holati: track stream bilan bog'liq emas.
        // Native remote stream'ga addTrack qilib bo'lmaydi — alohida local stream yaratamiz.
        final localStream = await createLocalMediaStream('gujum_remote_${track.kind}');
        try {
          await localStream.addTrack(track);
          // Agar bu audio track bo'lsa va bizda stream yo'q bo'lsa, uni ishlatamiz.
          // Agar stream bor bo'lsa (native), native audio o'ynashda davom etadi.
          if (_remoteStream == null) {
            _remoteStream = localStream;
          } else if (track.kind == 'video') {
            _remoteStream = localStream;
          }
        } catch (e) {
          debugPrint('CALL_DEBUG onTrack local stream addTrack failed: $e');
        }
      }
      // Video track kelganda renderer'ni majburan yangilaymiz (renegotiation case)
      if (track.kind == 'video') {
        _remoteStreamVersion++;
      }
      debugPrint(
        'CALL_DEBUG onTrack done remoteStream=${_remoteStream?.id} '
        'videoTracks=${_remoteStream?.getVideoTracks().length} '
        'audioTracks=${_remoteStream?.getAudioTracks().length}',
      );
      notifyListeners();
    };

    // Fallback for implementations that fire onAddStream instead of onTrack
    pc.onAddStream = (stream) {
      debugPrint('CALL_DEBUG onAddStream id=${stream.id}');
      if (_remoteStream?.id != stream.id) {
        _remoteStream = stream;
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
    final isFirstConnect = !_connectedSignalSent;
    if (isFirstConnect && _targetUsername != null && _callId != null) {
      _connectedSignalSent = true;
      _socketService.emit('CALL_CONNECTED', {
        'callId': _callId,
        'target': _targetUsername,
      });
      unawaited(CallKitService.setConnected(_callId!));
    }
    _state = CallSessionState.connected;
    _connectedAt ??= DateTime.now();
    _remoteStreamVersion++;

    if (isFirstConnect) {
      // Tone buffer WebRTC mic'iga qo'shilmasligi uchun qisqa mute.
      for (final track in _localStream?.getAudioTracks() ?? <MediaStreamTrack>[]) {
        track.enabled = false;
      }
      await _stopAlertTone();
      await Future.delayed(const Duration(milliseconds: 400));
      // Ulanish paytida audio route to'g'ri bo'lishini ta'minlaymiz
      // (ayniqsa background'dan qabul qilingan qo'ng'iroqlarda).
      await _applyAudioRoute();
      if (!_isMuted) {
        for (final track in _localStream?.getAudioTracks() ?? <MediaStreamTrack>[]) {
          track.enabled = true;
        }
      }
    }

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

    // Race condition tekshiruvi: agar stop allaqachon chaqirilgan bo'lsa, boshlamaymiz
    if (!_toneActive) return;

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        debugPrint('CALL_DEBUG startIncomingTone() using native ringtone');
        await _audioChannel.invokeMethod<void>('startIncomingRingtone');
        return;
      } catch (error) {
        debugPrint('CALL_DEBUG startIncomingTone() native ringtone failed error=$error');
      }
    }

    if (!_toneActive) return;

    debugPrint('CALL_DEBUG startIncomingTone() using asset ringtone fallback');
    try {
      await _audioPlayer.play(AssetSource('sounds/ringtone.wav'));
    } catch (error) {
      debugPrint('CALL_DEBUG startIncomingTone() asset ringtone failed error=$error');
    }
  }

  Future<void> _stopAlertTone() async {
    _toneActive = false;
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

    // Save the user's intent before the native call may return stale state.
    final requestedSpeaker = _isSpeakerOn;
    try {
      final result = await _audioChannel.invokeMapMethod<String, dynamic>(
        'activateCallAudio',
        {
          'speakerOn': requestedSpeaker,
          // A wired headset beats the speaker default, but never beats an
          // explicit tap on the speaker button.
          'preferWiredHeadset': !_speakerExplicit,
        },
      );
      debugPrint('CALL_DEBUG _applyAudioRoute() result=$result');
      _syncAudioRouteInfo(result);
      // _syncAudioRouteInfo may override _isSpeakerOn with a stale native value.
      // Restore the user's requested state unless bluetooth/headset took over.
      if (_audioRoute != CallAudioRoute.bluetooth &&
          _audioRoute != CallAudioRoute.headset) {
        _isSpeakerOn = requestedSpeaker;
        _audioRoute =
            requestedSpeaker ? CallAudioRoute.speaker : CallAudioRoute.earpiece;
      }
    } catch (error) {
      debugPrint('CALL_DEBUG _applyAudioRoute() failed error=$error');
    }
    // WebRTC's audio engine keeps its own speakerphone flag, so it has to be
    // told too — but with the RESOLVED route, not the original request. Passing
    // requestedSpeaker here was the bug: it runs last by design, so it undid the
    // native setCommunicationDevice(wiredHeadset) and pushed call audio out of
    // the loudspeaker with an earphone plugged in.
    final effectiveSpeaker = _audioRoute == CallAudioRoute.speaker;
    try {
      await Helper.setSpeakerphoneOn(effectiveSpeaker);
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

  void _startRingingTimeout() {
    _ringingTimeout?.cancel();
    _ringingTimeout = Timer(const Duration(seconds: 60), () {
      if (_state == CallSessionState.calling) {
        debugPrint('CALL_DEBUG ringing timeout — no answer after 60s');
        unawaited(_resetSession(notifyRemote: true, reason: 'no_answer'));
      }
    });
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

  // onTrack Android'da renegotiation paytida ishlamasligi mumkin.
  // Transceiver receiver'dan video trackni topib _remoteStream'ni yangilaymiz.
  Future<void> _rebuildRemoteStream() async {
    final pc = _peerConnection;
    if (pc == null) return;
    try {
      final transceivers = await pc.getTransceivers();
      for (final t in transceivers) {
        final track = t.receiver.track;
        if (track?.kind != 'video') continue;
        // onTrack allaqachon video qo'shgan bo'lsa — faqat renderer'ni yangilaymiz
        if (_remoteStream?.getVideoTracks().isNotEmpty == true) {
          _remoteStreamVersion++;
          return;
        }
        // Yangi stream yaratib video trackni qo'shamiz
        final stream = await createLocalMediaStream('remote_video');
        await stream.addTrack(track!);
        _remoteStream = stream;
        _remoteStreamVersion++;
        return;
      }
    } catch (e) {
      debugPrint('CALL_DEBUG _rebuildRemoteStream error=$e');
    }
  }

  Future<void> _closePeerResources() async {
    _iceConnectTimeout?.cancel();
    _iceConnectTimeout = null;

    // Havolalarni darhol bo'shatamiz: pastdagi close() yoki stop() osilib
    // qolsa ham controller o'lik obyektlarni ushlab turmasin va keyingi
    // qo'ng'iroq toza holatdan boshlansin.
    final pc = _peerConnection;
    final local = _localStream;
    final upgrade = _upgradeVideoStream;
    _peerConnection = null;
    _localStream = null;
    _remoteStream = null;
    _upgradeVideoStream = null;

    for (final track in local?.getTracks() ?? <MediaStreamTrack>[]) {
      try {
        track.stop();
      } catch (_) {}
    }
    for (final track in upgrade?.getTracks() ?? <MediaStreamTrack>[]) {
      try {
        track.stop();
      } catch (_) {}
    }
    // Kamera/mikrofon treklari to'xtaganidan keyin yopamiz — yarim qurilgan
    // ulanishda close() javob bermay qolishi mumkin.
    try {
      await pc?.close();
    } catch (_) {}
  }

  Future<void> _resetSession({
    bool notifyRemote = false,
    String reason = 'hangup',
  }) async {
    // _state ham tekshiriladi: sozlash yarim yo'lda uzilganda id lar allaqachon
    // tozalangan bo'lishi mumkin, lekin ekranda hali qo'ng'iroq turadi —
    // bunday holatda ham chiqa olishimiz kerak.
    if (_callId == null &&
        _targetUsername == null &&
        _incomingCall == null &&
        _state == null) {
      return;
    }
    final target = _targetUsername;
    final callId = _callId;
    final effectiveCallId = callId ?? _incomingCall?.callId;
    final wasVideo = _isVideo;
    _callId = null;
    _targetUsername = null;
    _pendingAutoAcceptCallId = null;
    _pendingDeclinedCallId = null;
    if (effectiveCallId != null) unawaited(CallKitService.endCall(effectiveCallId));
    final duration = _connectedAt == null
        ? 0
        : DateTime.now().difference(_connectedAt!).inSeconds;

    // Suhbatdoshga birinchi navbatda xabar beramiz: tozalash osilib qolsa ham
    // u tomonda qo'ng'iroq "ulanmoqda" holatida qolib ketmasin.
    if (notifyRemote && target != null) {
      _socketService.emit('CALL_END', {
        'callId': callId,
        'target': target,
        'reason': reason,
        'isVideo': wasVideo,
        'duration': duration,
      });
    }

    // Ekranni darhol yopamiz. Avval tozalash bajarilardi va uning ichidagi
    // birorta await (yarim qurilgan PeerConnection.close(), native audio
    // kanali) osilib qolsa, _state hech qachon tozalanmasdi: qo'ng'iroq
    // ekranda qolib, "Tugatish" tugmasi esa id lar allaqachon null bo'lgani
    // uchun hech narsa qilmasdi.
    _state = null;
    _incomingCall = null;
    _remotePeer = null;
    _resetInternalState();
    notifyListeners();

    // Tozalash — endi UI ga bog'liq emas. Har biri alohida himoyalangan:
    // bittasi yiqilsa qolganlari baribir bajariladi.
    await _safeCleanup('stopAlertTone', _stopAlertTone);
    await _safeCleanup('closePeerResources', _closePeerResources);
    await _safeCleanup('restoreAudioRoute', _restoreAudioRoute);
  }

  /// Tozalash qadamini xato va osilib qolishdan himoyalaydi.
  Future<void> _safeCleanup(String label, Future<void> Function() action) async {
    try {
      await action().timeout(const Duration(seconds: 3));
    } on TimeoutException {
      debugPrint('CALL_DEBUG cleanup timeout: $label');
    } catch (e) {
      debugPrint('CALL_DEBUG cleanup error ($label): $e');
    }
  }

  // Socket reconnect dan keyin PC yo'q bo'lsa — yangi offer yuborib qo'ng'iroqni tiklaydi.
  Future<void> _restartOutgoingOffer() async {
    if (_callId == null || _targetUsername == null || _remotePeer == null) return;
    debugPrint('CALL_DEBUG _restartOutgoingOffer() callId=$_callId target=$_targetUsername');
    try {
      await _closePeerResources();
      await _requestMediaPermissions(video: _isVideo);
      await _applyAudioRoute();
      final mediaState = await _openPreferredLocalMedia(video: _isVideo);
      _localStream = mediaState.stream;
      _isVideo = mediaState.videoEnabled;
      _isCameraOff = !_isVideo;
      final pc = await _createPeerConnection();
      for (final track in _localStream!.getTracks()) {
        await pc.addTrack(track, _localStream!);
      }
      final offer = await pc.createOffer();
      await pc.setLocalDescription(offer);
      _peerConnection = pc;
      _startRingingTimeout();
      _socketService.emit('CALL_OFFER', {
        'callId': _callId,
        'target': _targetUsername,
        'offer': {'sdp': offer.sdp, 'type': offer.type},
        'isVideo': _isVideo,
        'caller': {
          'username': _authController.user?.username,
          'fullName': _authController.user?.displayName,
          'avatar': _authController.user?.avatar,
        }
      });
      debugPrint('CALL_DEBUG _restartOutgoingOffer() re-emitted CALL_OFFER');
      notifyListeners();
    } catch (error) {
      debugPrint('CALL_DEBUG _restartOutgoingOffer() error=$error');
      await _resetSession(notifyRemote: true, reason: 'setup_failed');
    }
  }

  void _resetInternalState() {
    _connectedAt = null;
    _pendingCandidates.clear();
    _remoteDescriptionReady = false;
    _connectedSignalSent = false;
    _ringingTimeout?.cancel();
    _ringingTimeout = null;
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
        // Qurilmada quloqchin yo'q bo'lsa ham audio speaker'dan chiqadi — holatni sinxronlaymiz
        _isSpeakerOn = true;
        break;
    }
  }

  // Killed holatda qabul qilingan qo'ng'iroq — tashqaridan (main.dart) o'rnatiladi
  void setPendingAutoAccept(String callId) {
    if (callId.isEmpty) return;
    _pendingAutoAcceptCallId = callId;
    debugPrint('[CallKit] setPendingAutoAccept callId=$callId');
  }

  void _handleCallKitEvent(({String action, String callId}) event) {
    debugPrint('[CallKit] action=${event.action} callId=${event.callId}');
    switch (event.action) {
      case 'accept':
        if (_incomingCall?.callId == event.callId) {
          // App foreground bo'lsa darhol qabul qilamiz,
          // background bo'lsa resumed ga o'tganda (_onAppResumed) qabul qilamiz.
          final lifecycle = WidgetsBinding.instance.lifecycleState;
          if (lifecycle == AppLifecycleState.resumed) {
            unawaited(acceptIncomingCall());
          } else {
            _pendingAutoAcceptCallId = event.callId;
          }
        } else {
          // App o'ldirilgan holatda qabul qilingan — CALL_OFFER kelishini kutamiz
          _pendingAutoAcceptCallId = event.callId;
        }
      case 'decline':
        if (_incomingCall?.callId == event.callId) {
          rejectIncomingCall();
        } else {
          _pendingAutoAcceptCallId = null;
          // CALL_OFFER kelganda to'g'ri target bilan rad etamiz
          _pendingDeclinedCallId = event.callId;
          unawaited(CallKitService.endCall(event.callId));
        }
      case 'timeout':
        if (_incomingCall?.callId == event.callId) {
          unawaited(_resetSession());
        } else {
          _pendingAutoAcceptCallId = null;
        }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _onAppResumed();
    }
  }

  void _onAppResumed() {
    if (_pendingAutoAcceptCallId != null &&
        _incomingCall?.callId == _pendingAutoAcceptCallId) {
      _pendingAutoAcceptCallId = null;
      unawaited(acceptIncomingCall());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _subscription.cancel();
    _callKitSub.cancel();
    unawaited(_resetSession());
    _audioPlayer.dispose();
    super.dispose();
  }
}
