import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_strings.dart';
import '../settings/settings_controller.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _baseUrlController = TextEditingController();

  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final settings = context.read<SettingsController>();

    setState(() => _loading = true);
    try {
      if (!mounted) {
        return;
      }
      _baseUrlController.text = settings.baseUrl;
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _save() async {
    final settings = context.read<SettingsController>();

    setState(() => _saving = true);
    try {
      await settings.setBaseUrl(_baseUrlController.text.trim());
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppStrings.text(settings.localeCode, 'api_base_url_saved'),
          ),
        ),
      );
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
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
    final t = (String key) => AppStrings.text(settings.localeCode, key);

    return Scaffold(
      appBar: AppBar(
        title: Text(t('settings')),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(t('save_settings')),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
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
                          items: const [
                            DropdownMenuItem(value: 'uz', child: Text('UZ')),
                            DropdownMenuItem(value: 'en', child: Text('EN')),
                            DropdownMenuItem(value: 'ru', child: Text('RU')),
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
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t('settings_connection'),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _baseUrlController,
                          decoration: InputDecoration(
                            labelText: t('api_base_url'),
                            helperText: t('api_base_url_hint'),
                          ),
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
