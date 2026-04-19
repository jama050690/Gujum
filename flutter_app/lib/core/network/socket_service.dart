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

  Stream<SocketPacket> get packets => _controller.stream;

  bool get isConnected => _socket?.connected ?? false;

  void connect({
    required String baseUrl,
    String path = AppConfig.defaultSocketPath,
    required String username,
    String? cookie,
  }) {
    disconnect();

    final options = io.OptionBuilder()
        .setPath(path)
        .setTransports(['websocket', 'polling'])
        .enableAutoConnect()
        .enableForceNew()
        .enableReconnection()
        .setExtraHeaders(
          cookie == null || cookie.isEmpty
              ? const <String, String>{}
              : {'Cookie': cookie},
        )
        .build();

    _socket = io.io(baseUrl, options);
    _registerDefaultListeners(username);
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

  void disconnect() {
    _socket?.dispose();
    _socket?.disconnect();
    _socket = null;
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
    socket
        .onDisconnect((_) => _controller.add(SocketPacket('disconnect', null)));
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
      'MESSAGES_READ',
      'TYPING',
      'FRIEND_REQUEST',
      'FRIEND_ACCEPTED',
      'CALL_OFFER',
      'CALL_ANSWER',
      'ICE_CANDIDATE',
      'CALL_REJECT',
      'CALL_END',
      'CALL_BLOCKED',
      'CALL_NOT_DELIVERED',
    ]) {
      socket.on(event, (data) => _controller.add(SocketPacket(event, data)));
    }
  }
}
