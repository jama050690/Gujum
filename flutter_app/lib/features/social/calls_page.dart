import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/config/app_config.dart';
import '../../l10n/app_strings.dart';
import '../../models/chat_models.dart';
import '../app/navigation_controller.dart';
import '../auth/auth_controller.dart';
import '../call/call_controller.dart';
import '../chat/chat_controller.dart';
import '../settings/settings_controller.dart';

/// Qo'ng'iroqlar tarixi.
///
/// Ilgari bu sahifa inbox ro'yxatini filtrlardi, ya'ni faqat suhbatdagi eng
/// oxirgi xabar qo'ng'iroq bo'lsagina ko'rinardi: qo'ng'iroqdan keyin bitta
/// xabar yozilsa u ro'yxatdan yo'qolardi, eski qo'ng'iroqlar esa umuman
/// chiqmasdi. Endi /api/calls/history dan oxirgi 200 tasi olinadi.
class CallsPage extends StatefulWidget {
  const CallsPage({super.key});

  @override
  State<CallsPage> createState() => _CallsPageState();
}

class _CallsPageState extends State<CallsPage> {
  List<CallHistoryEntry> _history = const [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final history = await context.read<ChatController>().fetchCallHistory();
      if (!mounted) return;
      setState(() {
        _history = history;
        // Server bir marta 200 tagacha beradi. To'liq kelgan bo'lsa,
        // demak davomi ham bo'lishi mumkin.
        _hasMore = history.length >= AppConfig.callHistoryPageSize;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  /// Ro'yxat oxiriga yetganda keyingi bo'lakni oladi. Ilgari chegara
  /// qattiq 200 ta edi va undan oldingi qo'ng'iroqlarni ko'rishning
  /// imkoni yo'q edi.
  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _history.isEmpty) return;
    setState(() => _loadingMore = true);
    try {
      final older = await context
          .read<ChatController>()
          .fetchCallHistory(before: _history.last.createdAt);
      if (!mounted) return;
      setState(() {
        _history = [..._history, ...older];
        _hasMore = older.length >= AppConfig.callHistoryPageSize;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _hasMore = false;
        _loadingMore = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    final chat = context.watch<ChatController>();
    final call = context.watch<CallController>();
    final me = context.watch<AuthController>().user?.username;
    String t(String key) => AppStrings.text(settings.localeCode, key);

    return Scaffold(
      appBar: AppBar(title: Text(t('calls'))),
      body: RefreshIndicator(
        onRefresh: _load,
        child: Builder(builder: (context) {
          // Faqat sarlavha qismi oldindan quriladi. Ilgari bu yerda
          // ListView(children: [...]) turardi va u BUTUN tarixni birdan
          // qurardi — har bir qator ustiga tarmoqdan rasm oladigan
          // CircleAvatar bilan. Ro'yxat uzun bo'lsa sahifa shu sababli
          // ochilmay turardi; server so'rovi bunga qo'shimcha edi.
          final header = <Widget>[
            if (call.hasSession && call.remotePeer != null)
              _ActiveCallCard(
                title: call.remotePeer!.displayName,
                subtitle: t(call.isVideo ? 'call_video' : 'call_audio'),
              ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 48),
                child: Center(child: Text(t('request_failed'))),
              )
            else if (_history.isEmpty && !call.hasSession)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 48),
                child: Center(
                  child: Text(t('calls_empty'), textAlign: TextAlign.center),
                ),
              ),
          ];
          final entries = (_loading || _error != null) ? const [] : _history;

          return ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            itemCount: header.length + entries.length + (_hasMore ? 1 : 0),
            itemBuilder: (context, index) {
              if (index < header.length) return header[index];
              if (index == header.length + entries.length) {
                // Oxiriga yetildi — keyingi bo'lakni so'raymiz. Bu
                // itemBuilder ning ichida, ya'ni qurilish paytida:
                // setState ni to'g'ridan-to'g'ri chaqirib bo'lmaydi.
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  unawaited(_loadMore());
                });
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                );
              }
              final entry = entries[index - header.length];
              return _CallHistoryTile(
                entry: entry,
                settings: settings,
                isOutgoing: entry.caller == me,
                onTap: () {
                  // Suhbat ochilishini kutmaymiz — u darhol ochiladi,
                  // xabarlar esa keyin to'ldiriladi.
                  // Bo'lim holati MaterialApp dan yuqorida turadi, ya'ni
                  // bu sahifa (u Navigator.push bilan ochilgan bo'lsa ham)
                  // uni to'g'ridan-to'g'ri o'zgartira oladi.
                  context.read<NavigationController>().selectTab(
                        HomeTab.chats,
                      );
                  Navigator.of(context).pop();
                  unawaited(chat.openChat(InboxItem(
                    username: entry.peerUsername,
                    fullName: entry.peerFullName,
                    avatar: entry.peerAvatar,
                    lastActive: null,
                    lastMessage: '',
                    lastMessageAt: entry.createdAt,
                    unreadCount: 0,
                  )));
                },
              );
            },
          );
        }),
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
    required this.entry,
    required this.settings,
    required this.isOutgoing,
    required this.onTap,
  });

  final CallHistoryEntry entry;
  final SettingsController settings;
  final bool isOutgoing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final info = _CallPreview.tryParse(entry.content);
    if (info == null) {
      return const SizedBox.shrink();
    }

    String t(String key) => AppStrings.text(settings.localeCode, key);

    // Javobsiz qolgan qo'ng'iroq ikki tomon uchun bir xil emas: chaqirgan
    // odam uni o'zi bekor qilgan, chaqirilgan esa o'tkazib yuborgan. Ilgari
    // ikkalasiga ham "o'tkazib yuborilgan" deb yozilardi.
    final String subtitle;
    if (info.isMissed) {
      subtitle = isOutgoing ? t('call_cancelled') : t('call_missed');
    } else {
      final direction = isOutgoing ? t('call_outgoing') : t('call_incoming');
      final kind = t(info.isVideo ? 'call_video' : 'call_audio');
      subtitle = '$direction • $kind • ${info.formattedDuration}';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          child: Icon(
            info.isVideo ? Icons.videocam_outlined : Icons.call_outlined,
          ),
        ),
        title: Text(entry.peerFullName),
        subtitle: Row(
          children: [
            Icon(
              isOutgoing ? Icons.call_made_rounded : Icons.call_received_rounded,
              size: 14,
              color: info.isMissed
                  ? Theme.of(context).colorScheme.error
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Expanded(child: Text(subtitle, overflow: TextOverflow.ellipsis)),
          ],
        ),
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
