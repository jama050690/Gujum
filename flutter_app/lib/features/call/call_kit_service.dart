import 'dart:async';

import 'package:flutter/foundation.dart';
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
    debugPrint('[CallKit] event=${event.runtimeType}');
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

  static Future<void> showIncoming({
    required String callId,
    required String callerName,
    required bool isVideo,
  }) async {
    try {
      await FlutterCallkitIncoming.showCallkitIncoming(CallKitParams(
        id: callId,
        nameCaller: callerName,
        appName: 'Bootchat',
        handle: callerName,
        type: isVideo ? 1 : 0,
        duration: 30000,
        android: AndroidParams(
          isCustomNotification: false,
          isShowFullLockedScreen: true,
          ringtonePath: 'system_ringtone_default',
          backgroundColor: '#0C111A',
          actionColor: '#4D82E3',
          textAccept: "Qabul qilish",
          textDecline: "Rad etish",
          incomingCallNotificationChannelName: "Qo'ng'iroq",
          missedCallNotificationChannelName: "O'tkazib yuborilgan",
        ),
      ));
    } catch (e) {
      debugPrint('[CallKit] showIncoming error: $e');
    }
  }

  // Incoming call notification ni yashirish (in-app qabul qilinganda)
  static Future<void> hideIncoming(String callId) async {
    try {
      await FlutterCallkitIncoming.hideCallkitIncoming(
        CallKitParams(id: callId),
      );
    } catch (e) {
      debugPrint('[CallKit] hideIncoming error: $e');
    }
  }

  // Qo'ng'iroq ulandi — callkit holatini yangilash
  static Future<void> setConnected(String callId) async {
    try {
      await FlutterCallkitIncoming.setCallConnected(callId);
    } catch (e) {
      debugPrint('[CallKit] setConnected error: $e');
    }
  }

  static Future<void> endCall(String callId) async {
    try {
      await FlutterCallkitIncoming.endCall(callId);
    } catch (e) {
      debugPrint('[CallKit] endCall error: $e');
    }
  }

  static Future<void> endAllCalls() async {
    try {
      await FlutterCallkitIncoming.endAllCalls();
    } catch (e) {
      debugPrint('[CallKit] endAllCalls error: $e');
    }
  }

  void dispose() {
    _sub?.cancel();
  }
}
