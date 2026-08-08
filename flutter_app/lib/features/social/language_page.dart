import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_strings.dart';
import '../settings/settings_controller.dart';

/// Til tanlash — alohida sahifa.
///
/// Ilgari bu sozlamalardagi ochiluvchi ro'yxat edi. Beshta til uchun ham u
/// tor va noqulay: yozuvlar turlicha (arabcha, koreyscha) va tanlanganini
/// ko'rish qiyin. Telegramda ham til alohida sahifada.
class LanguagePage extends StatelessWidget {
  const LanguagePage({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    String t(String key) => AppStrings.text(settings.localeCode, key);

    return Scaffold(
      appBar: AppBar(title: Text(t('language'))),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          for (final code in AppStrings.supportedLocales)
            ListTile(
              title: Text(AppStrings.languageNames[code] ?? code),
              subtitle: Text(code.toUpperCase()),
              // Tanlangani belgi bilan ko'rsatiladi — ochiluvchi ro'yxatda
              // buni ko'rish uchun ro'yxatni ochish kerak edi.
              trailing: settings.localeCode == code
                  ? Icon(
                      Icons.check_rounded,
                      color: Theme.of(context).colorScheme.primary,
                    )
                  : null,
              onTap: () => settings.setLocaleCode(code),
            ),
        ],
      ),
    );
  }
}
