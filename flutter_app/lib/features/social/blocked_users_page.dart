import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/config/app_config.dart';
import '../../l10n/app_strings.dart';
import '../../models/social_models.dart';
import '../settings/settings_controller.dart';
import '../auth/auth_controller.dart';
import 'social_repository.dart';
import '../../core/widgets/avatar_image.dart';

/// Bloklangan foydalanuvchilar ro'yxati.
///
/// Ilgari bu ro'yxat profil sahifasining oxirida turardi — profil tahriri
/// bilan hech qanday aloqasi yo'q edi va profil ochilishini ham
/// sekinlashtirardi (ro'yxat har safar birga yuklanardi). Endi u
/// Sozlamalar ichida, alohida sahifa.
class BlockedUsersPage extends StatefulWidget {
  const BlockedUsersPage({super.key});

  @override
  State<BlockedUsersPage> createState() => _BlockedUsersPageState();
}

class _BlockedUsersPageState extends State<BlockedUsersPage> {
  /// Oxirgi ro'yxat — sahifa yopilgandan keyin ham qoladi.
  ///
  /// Sahifa har ochilganda serverdan so'ralardi va shu vaqt davomida
  /// faqat aylanma ko'rinardi; serverga bitta so'rov 1-2 soniya ketadi.
  /// Ro'yxat kimga tegishli ekani ham saqlanadi: boshqa akkaunt kirganda
  /// eskisi ko'rinib qolmasin.
  static String? _cacheOwner;
  static List<SimpleUser>? _cached;

  List<SimpleUser> _blocked = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    final owner = context.read<AuthController>().user?.username;
    if (owner != null && owner == _cacheOwner && _cached != null) {
      _blocked = _cached!;
      _loading = false;
    } else {
      _cacheOwner = null;
      _cached = null;
    }
    _load();
  }

  Future<void> _load() async {
    // Ko'rsatadigan narsa bo'lsa aylanma chiqmaydi.
    if (mounted) setState(() => _loading = _blocked.isEmpty);
    try {
      final blocked = await context.read<SocialRepository>().fetchBlockedUsers();
      if (!mounted) return;
      _cacheOwner = context.read<AuthController>().user?.username;
      _cached = blocked;
      setState(() {
        _blocked = blocked;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _unblock(SimpleUser user) async {
    try {
      await context.read<SocialRepository>().unblockUser(user.username);
      if (!mounted) return;
      final updated =
          _blocked.where((item) => item.username != user.username).toList();
      // Keshni ham yangilaymiz — aks holda sahifa qayta ochilganda
      // blokdan chiqarilgan odam yana ro'yxatda ko'rinardi.
      _cached = updated;
      setState(() => _blocked = updated);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    String t(String key) => AppStrings.text(settings.localeCode, key);

    return Scaffold(
      appBar: AppBar(title: Text(t('blocked_users'))),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _blocked.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(32),
                        child: Center(child: Text(t('no_blocked_users'))),
                      ),
                    ],
                  )
                : ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: _blocked.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final user = _blocked[index];
                      final imageUrl = AppConfig.resolveMediaUrl(
                          user.avatar, settings.baseUrl);
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundImage:
                              imageUrl.isNotEmpty ? avatarImage(imageUrl) : null,
                          child: imageUrl.isEmpty
                              ? Text(user.username.isNotEmpty
                                  ? user.username.substring(0, 1).toUpperCase()
                                  : '?')
                              : null,
                        ),
                        title: Text(user.fullName),
                        subtitle: Text('@${user.username}'),
                        trailing: OutlinedButton(
                          onPressed: () => _unblock(user),
                          child: Text(t('unblock')),
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}
