import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_strings.dart';
import '../settings/settings_controller.dart';

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
        ],
      ),
    );
  }
}
