import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/config/app_config.dart';
import '../../l10n/app_strings.dart';
import '../auth/auth_controller.dart';
import '../app/home_shell_scope.dart';
import '../chat/chat_controller.dart';
import '../chat/media_store.dart';
import '../chat/message_store.dart';
import '../settings/settings_controller.dart';
import 'blocked_users_page.dart';
import 'language_page.dart';
import 'social_repository.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    String t(String key) => AppStrings.text(settings.localeCode, key);

    return Scaffold(
      appBar: AppBar(
        title: Text(t('settings')),
        actions: [
          // Akkauntni o'chirish kundalik amal emas va qizil qator bo'lib
          // ro'yxatda turishi shart emas — u uch nuqta ostiga yashirildi.
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'delete_account') {
                _confirmDeleteAccount(context, t);
              }
            },
            itemBuilder: (menuContext) => [
              PopupMenuItem<String>(
                value: 'delete_account',
                child: Row(
                  children: [
                    Icon(
                      Icons.delete_forever_rounded,
                      color: Theme.of(menuContext).colorScheme.error,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      t('delete_account'),
                      style: TextStyle(
                        color: Theme.of(menuContext).colorScheme.error,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: ListView(
        // Kartochkalar o'rniga oddiy qatorlar: har biri alohida qutida
        // turganda ro'yxat parchalanib ko'rinardi. Bo'limlar sarlavha va
        // ingichka ajratgich bilan bo'linadi — Telegramdagi kabi.
        padding: EdgeInsets.zero,
        children: [
          _SectionLabel(text: t('settings_appearance')),
          SwitchListTile(
            value: settings.isDarkMode,
            onChanged: settings.setDarkMode,
            secondary: const Icon(Icons.dark_mode_outlined),
            title: Text(t('dark_mode')),
          ),
          ListTile(
            leading: const Icon(Icons.language_rounded),
            title: Text(t('language')),
            // Joriy til o'ng tomonda ko'rinadi — sahifani ochmasdan.
            subtitle: Text(
              AppStrings.languageNames[settings.localeCode] ??
                  settings.localeCode,
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const LanguagePage()),
            ),
          ),
          const Divider(height: 1),

          _SectionLabel(text: t('chats')),
          // "Saqlangan xabarlar" — Telegramda ham sozlamalar ichida bor.
          // Bosilganda Suhbatlar bo'limiga o'tib, o'sha ro'yxat ochiladi.
          ListTile(
            leading: const Icon(Icons.bookmark_border_rounded),
            title: Text(t('chat_saved_messages')),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () {
              context
                  .read<ChatController>()
                  .openSavedMessages(title: t('chat_saved_messages'));
              HomeShellScope.of(context)?.selectTab(HomeTab.chats);
            },
          ),
          // Bloklanganlar profil sahifasidan shu yerga ko'chirildi: profilni
          // tahrirlash bilan aloqasi yo'q edi.
          ListTile(
            leading: const Icon(Icons.block_rounded),
            title: Text(t('blocked_users')),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const BlockedUsersPage()),
            ),
          ),
          const Divider(height: 1),

          // Chiqish ilgari yon menyuda edi. Menyu olib tashlangach u shu
          // yerga ko'chdi — Telegramda ham u sozlamalar ichida.
          ListTile(
            leading: const Icon(Icons.logout_rounded),
            title: Text(t('logout')),
            onTap: () => _confirmLogout(context, t),
          ),
          const Divider(height: 1),

          const SizedBox(height: 20),
          // Versiya — qatorlar orasida emas, eng pastda, kulrang matn bilan.
          // Bosiladigan narsa emas, shuning uchun qator ko'rinishida ham
          // turishi shart emas.
          Center(
            child: Text(
              '${t('version_label')} ${AppConfig.appVersion}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Future<void> _confirmLogout(
    BuildContext context,
    String Function(String) t,
  ) async {
    final auth = context.read<AuthController>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(t('logout_confirm_title')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(t('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              t('logout'),
              style: TextStyle(color: Theme.of(dialogContext).colorScheme.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await auth.logout();
  }

  Future<void> _confirmDeleteAccount(
    BuildContext context,
    String Function(String) t,
  ) async {
    final reasonKeys = <String>[
      'reason_not_using',
      'reason_no_friends',
      'reason_bugs',
      'reason_privacy',
      'reason_other',
    ];
    String? selected;
    final commentController = TextEditingController();

    // Dialog yopilgach controller bo'shatiladi — aks holda har ochilishda
    // bittadan TextEditingController xotirada qolib ketardi.
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(t('delete_account')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t('delete_account_warning'),
                  style: TextStyle(color: Theme.of(dialogContext).colorScheme.error),
                ),
                const SizedBox(height: 16),
                Text(t('delete_account_reason_q')),
                // Flutter 3.32 dan keyin tanlov holati RadioGroup da
                // yuritiladi; RadioListTile.groupValue/onChanged eskirgan.
                RadioGroup<String>(
                  groupValue: selected,
                  onChanged: (value) => setDialogState(() => selected = value),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final key in reasonKeys)
                        RadioListTile<String>(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          value: key,
                          title: Text(t(key)),
                        ),
                    ],
                  ),
                ),
                TextField(
                  controller: commentController,
                  maxLines: 2,
                  maxLength: 200,
                  decoration: InputDecoration(
                    hintText: t('reason_comment_hint'),
                    counterText: '',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(t('cancel')),
            ),
            TextButton(
              // Sabab tanlanmaguncha o'chirib bo'lmaydi — tasodifiy bosishdan
              // himoya ham shu.
              onPressed: selected == null
                  ? null
                  : () => Navigator.pop(dialogContext, true),
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(dialogContext).colorScheme.error,
              ),
              child: Text(t('delete_account_confirm')),
            ),
          ],
        ),
      ),
    );

    final comment = commentController.text;
    commentController.dispose();

    if (confirmed != true || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final auth = context.read<AuthController>();
    final repository = context.read<SocialRepository>();
    try {
      await repository.deleteAccount(
        reason: selected,
        comment: comment,
      );
    } catch (_) {
      messenger.showSnackBar(
        SnackBar(content: Text(t('delete_account_failed'))),
      );
      return;
    }

    // Server tomonda akkaunt yo'q — endi chiqish har qanday holatda ham
    // bajarilishi kerak. Qurilmadagi nusxalarni tozalash yiqilsa ham
    // foydalanuvchini o'chirilgan akkauntda qoldirib bo'lmaydi.
    final username = auth.user?.username;
    try {
      // Ikkalasini ham tozalaymiz: yangi kalit (akkaunt id si) va eski
      // username kaliti — eski build qoldirgan papka qolib ketmasin.
      final id = auth.user?.id;
      if (id != null) {
        await (await MessageStore.create('u$id')).clearAll();
      }
      if (username != null) {
        await (await MessageStore.create(username)).clearAll();
      }
      await MediaStore.clearAll();
    } catch (_) {
      // tozalash muvaffaqiyatsiz — chiqishga to'sqinlik qilmaydi
    }
    await auth.logout();

    // Sozlamalar endi pastdagi paneldagi bo'lim, ya'ni ildiz marshrutning
    // o'zi — bu yerda yopiladigan narsa odatda yo'q. Lekin uning ustidan
    // "Bloklanganlar" yoki "Til" ochilgan bo'lishi mumkin, shuning uchun
    // stek baribir bo'shatiladi: akkaunt o'chirilgach ekranda ular
    // qolmasin.
    navigator.popUntil((route) => route.isFirst);
  }
}

/// Bo'lim sarlavhasi — qatorlar guruhini ajratadi.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Text(
        text.toUpperCase(),
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
      ),
    );
  }
}
