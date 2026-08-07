import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_strings.dart';
import '../auth/auth_controller.dart';
import '../chat/media_store.dart';
import '../chat/message_store.dart';
import '../settings/settings_controller.dart';
import 'blocked_users_page.dart';
import 'social_repository.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    final t = (String key) => AppStrings.text(settings.localeCode, key);

    return Scaffold(
      appBar: AppBar(title: Text(t('settings'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Text(
                    t('settings_appearance'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                SwitchListTile(
                  value: settings.isDarkMode,
                  onChanged: settings.setDarkMode,
                  title: Text(t('dark_mode')),
                ),
                ListTile(
                  title: Text(t('language')),
                  trailing: DropdownButton<String>(
                    value: settings.localeCode,
                    underline: const SizedBox.shrink(),
                    items: [
                      for (final code in AppStrings.supportedLocales)
                        DropdownMenuItem(
                          value: code,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                code.toUpperCase(),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(width: 8),
                              // Tilning o'z nomi — o'sha tilda yozilgan holda.
                              Text(AppStrings.languageNames[code] ?? code),
                            ],
                          ),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        settings.setLocaleCode(value);
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Bloklanganlar profil sahifasidan shu yerga ko'chirildi: profilni
          // tahrirlash bilan aloqasi yo'q edi.
          Card(
            child: ListTile(
              leading: const Icon(Icons.block_rounded),
              title: Text(t('blocked_users')),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const BlockedUsersPage()),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Xavfli hudud — Google Play akkaunt yaratadigan ilovalardan ilova
          // ichida o'chirish imkonini talab qiladi.
          Card(
            child: ListTile(
              leading: Icon(
                Icons.delete_forever_rounded,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(
                t('delete_account'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              onTap: () => _confirmDeleteAccount(context, t),
            ),
          ),
        ],
      ),
    );
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
    var deleting = false;

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
                for (final key in reasonKeys)
                  RadioListTile<String>(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: key,
                    groupValue: selected,
                    title: Text(t(key)),
                    onChanged: deleting
                        ? null
                        : (value) => setDialogState(() => selected = value),
                  ),
                TextField(
                  controller: commentController,
                  enabled: !deleting,
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
              onPressed: deleting ? null : () => Navigator.pop(dialogContext, false),
              child: Text(t('cancel')),
            ),
            TextButton(
              // Sabab tanlanmaguncha o'chirib bo'lmaydi — tasodifiy bosishdan
              // himoya ham shu.
              onPressed: (deleting || selected == null)
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

    if (confirmed != true || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final auth = context.read<AuthController>();
    final repository = context.read<SocialRepository>();
    try {
      await repository.deleteAccount(
        reason: selected,
        comment: commentController.text,
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

    // Sozlamalar sahifasi Navigator.push bilan ochilgan, ya'ni u ildiz
    // ekranning ustida turadi. Ildizni AuthFlow ga almashtirish uni
    // yopmaydi — shuning uchun kirish ekraniga qaytish uchun stekni
    // bo'shatish kerak. Aks holda o'chirilgandan keyin ham sozlamalarda
    // qolib ketilardi.
    navigator.popUntil((route) => route.isFirst);
  }
}
