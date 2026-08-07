import 'dart:async';

import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';

class CallKitService {
  CallKitService._();
  static final CallKitService instance = CallKitService._();

  final _controller =
      StreamController<({String action, String callId})>.broadcast();
  Stream<({String action, String callId})> get events => _controller.stream;
  StreamSubscription? _sub;

  void init() {
    _sub?.cancel();
    _sub = FlutterCallkitIncoming.onEvent.listen(_handle);
  }

  void _handle(CallEvent? event) {
    if (event == null) return;
    switch (event) {
      case CallEventActionCallAccept(:final id):
        _controller.add((action: 'accept', callId: id));
      case CallEventActionCallDecline(:final id):
        _controller.add((action: 'decline', callId: id));
      case CallEventActionCallTimeout(:final id):
        _controller.add((action: 'timeout', callId: id));
      case CallEventActionCallEnded(:final id):
        _controller.add((action: 'ended', callId: id));
      default:
        break;
    }
  }

  /// Matnlar chaqiruvchi tomondan beriladi — bu servis til bilan ishlamaydi,
  /// shuning uchun qatorlar shu yerda qotib qolmasligi kerak.
  static Future<void> showIncoming({
    required String callId,
    required String callerName,
    required String callerUsername,
    required bool isVideo,
    required String acceptLabel,
    required String declineLabel,
    required String incomingChannelName,
    required String missedChannelName,
  }) async {
    try {
      await FlutterCallkitIncoming.showCallkitIncoming(CallKitParams(
        id: callId,
        nameCaller: callerName,
        appName: 'Gujum',
        handle: callerUsername.isNotEmpty ? callerUsername : callerName,
        type: isVideo ? 1 : 0,
        duration: 30000,
        android: AndroidParams(
          isCustomNotification: true,
          isFullScreen: true,
          isShowFullLockedScreen: true,
          ringtonePath: 'system_ringtone_default',
          backgroundColor: '#0C111A',
          actionColor: '#4D82E3',
          textAccept: acceptLabel,
          textDecline: declineLabel,
          incomingCallNotificationChannelName: incomingChannelName,
          missedCallNotificationChannelName: missedChannelName,
        ),
      ));
    } catch (e) {
    }
  }

  // Incoming call notification ni yashirish (in-app qabul qilinganda)
  static Future<void> hideIncoming(String callId) async {
    try {
      await FlutterCallkitIncoming.hideCallkitIncoming(
        CallKitParams(id: callId),
      );
    } catch (e) {
    }
  }

  // Qo'ng'iroq ulandi — callkit holatini yangilash
  static Future<void> setConnected(String callId) async {
    try {
      await FlutterCallkitIncoming.setCallConnected(callId);
    } catch (e) {
    }
  }

  static Future<void> endCall(String callId) async {
    try {
      await FlutterCallkitIncoming.endCall(callId);
    } catch (e) {
    }
  }

  static Future<void> endAllCalls() async {
    try {
      await FlutterCallkitIncoming.endAllCalls();
    } catch (e) {
    }
  }

  void dispose() {
    _sub?.cancel();
  }
}
