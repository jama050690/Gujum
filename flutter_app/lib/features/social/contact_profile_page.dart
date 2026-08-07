import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/config/app_config.dart';
import '../../models/social_models.dart';
import '../call/call_controller.dart';
import '../settings/settings_controller.dart';
import '../chat/media_viewer_page.dart';
import 'social_repository.dart';
import '../../l10n/app_strings.dart';

class ContactProfilePage extends StatefulWidget {
  const ContactProfilePage({
    super.key,
    required this.username,
    this.displayName,
    this.lastSeenStatus,
  });

  final String username;
  final String? displayName;
  final String? lastSeenStatus;

  @override
  State<ContactProfilePage> createState() => _ContactProfilePageState();
}

class _ContactProfilePageState extends State<ContactProfilePage> {
  String _t(String key) => AppStrings.text(
      context.read<SettingsController>().localeCode, key);

  ProfileDetails? _profile;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final repo = context.read<SocialRepository>();
      final profile = await repo.fetchProfile(widget.username);
      if (mounted) setState(() { _profile = profile; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _startCall({required bool video}) {
    final call = context.read<CallController>();
    final name = _profile?.fullName ?? widget.displayName ?? widget.username;
    Navigator.pop(context);
    call.startCall(
      CallPeer(username: widget.username, displayName: name),
      video: video,
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    final isDark = settings.isDarkMode;
    final avatarUrl = AppConfig.resolveMediaUrl(_profile?.avatar, settings.baseUrl);
    final name = _profile?.fullName ?? widget.displayName ?? widget.username;
    final initials = name.trim().split(RegExp(r'\s+')).take(2)
        .map((s) => s.isNotEmpty ? s[0].toUpperCase() : '').join();
    const accent = Color(0xFF4A89BE);
    final cardBg = isDark ? const Color(0xFF17212B) : Colors.white;
    final bgColor = isDark ? const Color(0xFF0E1621) : const Color(0xFFF0F2F5);

    return Scaffold(
      backgroundColor: bgColor,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 260,
            pinned: true,
            backgroundColor: isDark ? const Color(0xFF17212B) : accent,
            foregroundColor: Colors.white,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                color: isDark ? const Color(0xFF17212B) : accent,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 56),
                    GestureDetector(
                      onTap: avatarUrl.isNotEmpty
                          ? () => Navigator.push(context, MaterialPageRoute(
                              builder: (_) => ImageViewerPage(
                                imageUrl: avatarUrl,
                                heroTag: 'cp_${widget.username}',
                              )))
                          : null,
                      child: Hero(
                        tag: 'cp_${widget.username}',
                        child: CircleAvatar(
                          radius: 52,
                          backgroundColor: accent.withAlpha(180),
                          backgroundImage: avatarUrl.isNotEmpty
                              ? NetworkImage(avatarUrl) : null,
                          child: avatarUrl.isEmpty
                              ? Text(initials, style: const TextStyle(
                                  fontSize: 34, color: Colors.white,
                                  fontWeight: FontWeight.bold))
                              : null,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(name, style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w700,
                        color: Colors.white)),
                    const SizedBox(height: 4),
                    Text(
                      widget.lastSeenStatus ?? '@${widget.username}',
                      style: const TextStyle(fontSize: 13, color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: _loading
                ? const Padding(
                    padding: EdgeInsets.only(top: 48),
                    child: Center(child: CircularProgressIndicator()))
                : _buildBody(isDark, cardBg),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(bool isDark, Color cardBg) {
    final p = _profile;
    final tc = isDark ? Colors.white : Colors.black87;
    final sc = isDark ? Colors.white54 : Colors.black45;

    return Column(children: [
      const SizedBox(height: 12),
      Container(
        color: cardBg,
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          _Btn(icon: Icons.message_rounded, label: _t('profile_message'),
              onTap: () => Navigator.pop(context)),
          _Btn(icon: Icons.call_rounded, label: _t('call_audio'),
              onTap: () => _startCall(video: false)),
          _Btn(icon: Icons.videocam_rounded, label: _t('profile_video_call'),
              onTap: () => _startCall(video: true)),
        ]),
      ),
      if (p != null) ...[
        const SizedBox(height: 12),
        Container(color: cardBg, child: Column(children: [
          if (p.phone.isNotEmpty)
            _InfoRow(Icons.phone_rounded, p.phone, _t('profile_mobile'), tc, sc),
          _InfoRow(Icons.alternate_email_rounded, '@${p.username}',
              _t('profile_username_label'),
              tc, sc, onTap: () => Clipboard.setData(
                  ClipboardData(text: p.username))),
          if (p.birthday.isNotEmpty && p.birthday != 'null')
            _InfoRow(Icons.cake_rounded, _fmtBday(p.birthday),
                _t('profile_birthday'), tc, sc),
          if (p.bio.isNotEmpty)
            _InfoRow(Icons.info_outline_rounded, p.bio, _t('profile_bio_label'),
                tc, sc),
        ])),
      ],
      const SizedBox(height: 32),
    ]);
  }

  String _fmtBday(String raw) {
    final parts = raw.split('-');
    if (parts.length < 2) return raw;
    const ms = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug',
                 'Sep','Oct','Nov','Dec'];
    final m = int.tryParse(parts.length >= 3 ? parts[1] : parts[0]) ?? 0;
    return (m >= 1 && m <= 12)
        ? '${ms[m - 1]}${parts.length >= 3 ? " ${parts[2]}" : ""}'
        : raw;
  }
}

class _Btn extends StatelessWidget {
  const _Btn({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 54, height: 54,
        decoration: const BoxDecoration(
            color: Color(0x204A89BE), shape: BoxShape.circle),
        child: Icon(icon, color: const Color(0xFF4A89BE), size: 24),
      ),
      const SizedBox(height: 6),
      Text(label, style: const TextStyle(
          fontSize: 12, color: Color(0xFF4A89BE))),
    ]),
  );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.icon, this.label, this.sub, this.tc, this.sc, {this.onTap});
  final IconData icon;
  final String label;
  final String sub;
  final Color tc;
  final Color sc;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(children: [
        Icon(icon, size: 22, color: const Color(0xFF4A89BE)),
        const SizedBox(width: 20),
        Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontSize: 16, color: tc)),
          const SizedBox(height: 2),
          Text(sub, style: TextStyle(fontSize: 13, color: sc)),
        ])),
      ]),
    ),
  );
}
