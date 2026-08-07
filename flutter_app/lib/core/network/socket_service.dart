import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../config/app_config.dart';

class SocketPacket {
  SocketPacket(this.event, this.payload);

  final String event;
  final dynamic payload;
}

class SocketService {
  io.Socket? _socket;
  final _controller = StreamController<SocketPacket>.broadcast();
  String? _connectionKey;
  String? _username;
  Timer? _keepaliveTimer;

  Stream<SocketPacket> get packets => _controller.stream;

  bool get isConnected => _socket?.connected ?? false;

  void connect({
    required String baseUrl,
    String path = AppConfig.defaultSocketPath,
    required String username,
    String? cookie,
  }) {
    final nextConnectionKey = '$baseUrl|$path|$username|${cookie ?? ''}';
    if (_socket != null &&
        _connectionKey == nextConnectionKey &&
        (_socket!.connected || _socket!.active)) {
      return;
    }

    disconnect();

    final optionBuilder = io.OptionBuilder()
        .setPath(path)
        .setTransports(['websocket', 'polling'])
        .enableAutoConnect()
        .enableReconnection()
        .setReconnectionAttempts(999999)
        .setReconnectionDelay(2000)
        .setReconnectionDelayMax(10000)
        .setTimeout(20000);

    // The server derives our identity from this token — without it the
    // handshake is rejected.
    if (cookie != null && cookie.isNotEmpty) {
      optionBuilder.setAuth(<String, dynamic>{'cookie': cookie});
    }

    final options = optionBuilder.build();

    _socket = io.io(baseUrl, options);
    _connectionKey = nextConnectionKey;
    _username = username;
    _registerDefaultListeners(username);
    _startKeepalive();
  }

  void emit(String event, dynamic payload) {
    if (_socket == null) {
      debugPrint('Socket emit failed: socket is null for event: $event');
      return;
    }
    if (!_socket!.connected) {
      debugPrint('Socket emit warning: socket not connected for event: $event');
    }
    _socket!.emit(event, payload);
  }

  void _startKeepalive() {
    _keepaliveTimer?.cancel();
    _keepaliveTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      final user = _username;
      if (user != null && (_socket?.connected ?? false)) {
        _socket!.emit('USER_ONLINE', user);
      }
    });
  }

  void disconnect() {
    _keepaliveTimer?.cancel();
    _keepaliveTimer = null;
    _username = null;
    _socket?.dispose();
    _socket?.disconnect();
    _socket = null;
    _connectionKey = null;
  }

  void dispose() {
    disconnect();
    _controller.close();
  }

  void _registerDefaultListeners(String username) {
    final socket = _socket;
    if (socket == null) {
      return;
    }

    socket.onConnect((_) {
      socket.emit('USER_ONLINE', username);
      _controller.add(SocketPacket('connect', null));
    });
    socket.onDisconnect((reason) {
      _controller.add(SocketPacket('disconnect', reason));
    });
    socket.onConnectError((error) {
      debugPrint('Socket connect error: $error');
      _controller.add(SocketPacket('connect_error', error));
    });
    socket.onError((error) {
      debugPrint('Socket error: $error');
      _controller.add(SocketPacket('error', error));
    });

    for (final event in const [
      'ONLINE_USERS_LIST',
      'USER_STATUS_CHANGED',
      'NEW_MESSAGE',
      'GROUP_MESSAGE',
      'CHANNEL_MESSAGE',
      'MESSAGE_DELETED',
      'MESSAGES_DELETED',
      'CHAT_CLEARED',
      'MESSAGES_READ',
      'TYPING',
      'FRIEND_REQUEST',
      'FRIEND_ACCEPTED',
      'CALL_OFFER',
      'CALL_ANSWER',
      'CALL_CONNECTED',
      'ICE_CANDIDATE',
      'CALL_REJECT',
      'CALL_END',
      'CALL_BLOCKED',
      'CALL_NOT_DELIVERED',
      'CALL_SESSION_SYNC',
      'CALL_PARTICIPANT_RECONNECTING',
      'CALL_PARTICIPANT_REJOINED',
      'CALL_RENEGOTIATE',
      'CALL_RENEGOTIATE_ANSWER',
    ]) {
      socket.on(event, (data) {
        _controller.add(SocketPacket(event, data));
      });
    }
  }
}
