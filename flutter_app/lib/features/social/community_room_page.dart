import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/config/app_config.dart';
import '../../core/network/socket_service.dart';
import '../../l10n/app_strings.dart';
import '../../models/social_models.dart';
import '../auth/auth_controller.dart';
import '../settings/settings_controller.dart';
import 'social_repository.dart';

class CommunityRoomPage extends StatefulWidget {
  const CommunityRoomPage({
    super.key,
    required this.item,
  });

  final CommunityItem item;

  @override
  State<CommunityRoomPage> createState() => _CommunityRoomPageState();
}

class _CommunityRoomPageState extends State<CommunityRoomPage> {
  final _messageController = TextEditingController();
  StreamSubscription<SocketPacket>? _subscription;
  List<CommunityMessage> _messages = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _subscription = context.read<SocketService>().packets.listen(_handlePacket);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _loadMessages() async {
    final repository = context.read<SocialRepository>();
    setState(() => _loading = true);
    try {
      final messages = widget.item.type == CommunityType.group
          ? await repository.fetchGroupMessages(widget.item.id)
          : await repository.fetchChannelMessages(widget.item.id);
      if (!mounted) {
        return;
      }
      setState(() => _messages = messages);
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _handlePacket(SocketPacket packet) {
    final event = widget.item.type == CommunityType.group ? 'GROUP_MESSAGE' : 'CHANNEL_MESSAGE';
    if (packet.event != event) {
      return;
    }

    final payload = Map<String, dynamic>.from(packet.payload as Map);
    final idKey = widget.item.type == CommunityType.group ? 'groupId' : 'channelId';
    if (int.tryParse('${payload[idKey] ?? ''}') != widget.item.id) {
      return;
    }

    final message = CommunityMessage.fromJson(payload);
    if (!mounted) {
      return;
    }
    setState(() {
      if (_messages.any((item) => item.id == message.id)) {
        return;
      }
      _messages = [..._messages, message];
    });
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    final user = context.read<AuthController>().user;
    if (text.isEmpty || user == null) {
      return;
    }

    _messageController.clear();
    final socket = context.read<SocketService>();
    if (widget.item.type == CommunityType.group) {
      socket.emit('GROUP_MESSAGE', {
        'groupId': widget.item.id,
        'user': user.username,
        'message': text,
        'avatar': user.avatar,
      });
    } else {
      socket.emit('CHANNEL_MESSAGE', {
        'channelId': widget.item.id,
        'user': user.username,
        'message': text,
        'avatar': user.avatar,
      });
    }
  }

  Future<void> _showPeople() async {
    try {
      final repository = context.read<SocialRepository>();
      final settings = context.read<SettingsController>();
      final t = (String key) => AppStrings.text(settings.localeCode, key);
      final users = widget.item.type == CommunityType.group
          ? await repository.fetchGroupMembers(widget.item.id)
          : await repository.fetchChannelSubscribers(widget.item.id);

      if (!mounted) {
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: Text(t(widget.item.type == CommunityType.group ? 'members' : 'subscribers')),
            content: SizedBox(
              width: 360,
              child: users.isEmpty
                  ? Text(t('loading'))
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: users.length,
                      itemBuilder: (context, index) {
                        final user = users[index];
                        final imageUrl = AppConfig.resolveMediaUrl(user.avatar, settings.baseUrl);
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundImage: imageUrl.isNotEmpty ? NetworkImage(imageUrl) : null,
                            child: imageUrl.isEmpty
                                ? Text(user.username.substring(0, 1).toUpperCase())
                                : null,
                          ),
                          title: Text(user.fullName),
                          subtitle: Text('@${user.username}'),
                        );
                      },
                    ),
            ),
          );
        },
      );
    } catch (error) {
      _showError(error);
    }
  }

  void _showError(Object error) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error.toString())),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    final auth = context.watch<AuthController>();
    final t = (String key) => AppStrings.text(settings.localeCode, key);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.item.name),
            Text(
              '${widget.item.peopleCount} ${t(widget.item.type == CommunityType.group ? 'members' : 'subscribers')}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _showPeople,
            icon: const Icon(Icons.people_alt_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final message = _messages[index];
                      final mine = message.username == auth.user?.username;
                      return Align(
                        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          constraints: const BoxConstraints(maxWidth: 420),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: mine
                                ? Theme.of(context).colorScheme.primaryContainer
                                : Theme.of(context).colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Column(
                            crossAxisAlignment:
                                mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                            children: [
                              if (!mine)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: Text(
                                    message.username,
                                    style: Theme.of(context).textTheme.labelSmall,
                                  ),
                                ),
                              if (message.content.isNotEmpty) Text(message.content),
                              if (message.image != null && message.image!.isNotEmpty)
                                Text('[image] ${message.image}'),
                              if (message.audio != null && message.audio!.isNotEmpty)
                                Text('[audio] ${message.audio}'),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      minLines: 1,
                      maxLines: 5,
                      decoration: InputDecoration(hintText: t('type_message')),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _sendMessage,
                    child: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
