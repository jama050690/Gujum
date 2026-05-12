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
      debugPrint(
        'SOCKET_DEBUG connect() skipped existing connection key=$nextConnectionKey connected=${_socket!.connected} active=${_socket!.active}',
      );
      return;
    }

    debugPrint(
      'SOCKET_DEBUG connect() username=$username baseUrl=$baseUrl path=$path hasCookie=${cookie?.isNotEmpty == true}',
    );
    disconnect();

final options = io.OptionBuilder()
    .setPath(path) // Bu yerda AppConfig.defaultSocketPath /api/bootchat/socket.io/ ekanligini tekshiring
    .setTransports(['websocket']) // 'polling' ni 'websocket' ga almashtiring!
    .enableAutoConnect()
    .enableReconnection()
    .setReconnectionAttempts(999999)
    .setReconnectionDelay(1000)
    .setReconnectionDelayMax(5000)
    .setExtraHeaders(
      cookie == null || cookie.isEmpty
          ? const <String, String>{}
          : {'Cookie': cookie},
    )
    .build();

    _socket = io.io(baseUrl, options);
    _connectionKey = nextConnectionKey;
    debugPrint('SOCKET_DEBUG socket instance created');
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
    debugPrint('SOCKET_DEBUG emit event=$event payload=$payload');
    _socket!.emit(event, payload);
  }

  void disconnect() {
    debugPrint('SOCKET_DEBUG disconnect() called');
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
      debugPrint('SOCKET_DEBUG onConnect id=${socket.id}');
      socket.emit('USER_ONLINE', username);
      debugPrint('SOCKET_DEBUG USER_ONLINE emitted username=$username');
      _controller.add(SocketPacket('connect', null));
    });
    socket.onDisconnect((reason) {
      debugPrint('SOCKET_DEBUG onDisconnect reason=$reason');
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
      'CALL_SESSION_SYNC',
      'CALL_PARTICIPANT_RECONNECTING',
      'CALL_PARTICIPANT_REJOINED',
    ]) {
      socket.on(event, (data) {
        debugPrint('SOCKET_DEBUG onEvent event=$event data=$data');
        _controller.add(SocketPacket(event, data));
      });
    }
  }
}
