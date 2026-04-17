import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_strings.dart';
import '../../models/chat_models.dart';
import '../call/call_controller.dart';
import '../chat/chat_controller.dart';
import '../settings/settings_controller.dart';

class CallsPage extends StatelessWidget {
  const CallsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    final chat = context.watch<ChatController>();
    final call = context.watch<CallController>();
    final t = (String key) => AppStrings.text(settings.localeCode, key);
    final history = chat.inbox
        .where((item) => _CallPreview.tryParse(item.lastMessage) != null)
        .toList(growable: false);

    return Scaffold(
      appBar: AppBar(
        title: Text(t('calls')),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (call.hasSession && call.remotePeer != null)
            _ActiveCallCard(
              title: call.remotePeer!.displayName,
              subtitle: t(
                call.isVideo ? 'call_video' : 'call_audio',
              ),
            ),
          if (history.isEmpty && !call.hasSession)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 48),
              child: Center(
                child: Text(
                  t('calls_empty'),
                  textAlign: TextAlign.center,
                ),
              ),
            )
          else
            ...history.map(
              (item) => _CallHistoryTile(
                item: item,
                settings: settings,
                onTap: () async {
                  await chat.openChat(item);
                  if (context.mounted) {
                    Navigator.of(context).pop();
                  }
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _ActiveCallCard extends StatelessWidget {
  const _ActiveCallCard({
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: ListTile(
        leading: const CircleAvatar(
          child: Icon(Icons.call_rounded),
        ),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.graphic_eq_rounded),
      ),
    );
  }
}

class _CallHistoryTile extends StatelessWidget {
  const _CallHistoryTile({
    required this.item,
    required this.settings,
    required this.onTap,
  });

  final InboxItem item;
  final SettingsController settings;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final info = _CallPreview.tryParse(item.lastMessage);
    if (info == null) {
      return const SizedBox.shrink();
    }

    final t = (String key) => AppStrings.text(settings.localeCode, key);
    final subtitle = info.isMissed
        ? t('call_missed')
        : '${t(info.isVideo ? 'call_video' : 'call_audio')} • ${info.formattedDuration}';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          child: Icon(
            info.isVideo ? Icons.videocam_outlined : Icons.call_outlined,
          ),
        ),
        title: Text(item.fullName),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right_rounded),
      ),
    );
  }
}

class _CallPreview {
  const _CallPreview({
    required this.isVideo,
    required this.isMissed,
    required this.durationSeconds,
  });

  final bool isVideo;
  final bool isMissed;
  final int durationSeconds;

  String get formattedDuration {
    final minutes = durationSeconds ~/ 60;
    final seconds = durationSeconds % 60;
    final hours = minutes ~/ 60;
    final remainingMinutes = minutes % 60;

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${remainingMinutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${remainingMinutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  static final RegExp _pattern =
      RegExp(r'^__CALL:(audio|video):(missed|\d+)__$');

  static _CallPreview? tryParse(String value) {
    final match = _pattern.firstMatch(value.trim());
    if (match == null) {
      return null;
    }

    final token = match.group(2) ?? 'missed';
    return _CallPreview(
      isVideo: match.group(1) == 'video',
      isMissed: token == 'missed',
      durationSeconds: token == 'missed' ? 0 : int.tryParse(token) ?? 0,
    );
  }
}
