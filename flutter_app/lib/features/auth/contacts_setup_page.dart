import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:provider/provider.dart';
import '../../l10n/app_strings.dart';
import '../settings/settings_controller.dart';

/// Ro'yxatdan o'tishning 3-qadami: kontaktlarni ulash.
///
/// Ruxsat so'rashdan oldin nima uchun kerakligini bir jumlada tushuntiramiz —
/// tizim oynasi to'satdan chiqsa, foydalanuvchilar odatda "Rad etish" bosadi.
class ContactsSetupPage extends StatefulWidget {
  const ContactsSetupPage({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  State<ContactsSetupPage> createState() => _ContactsSetupPageState();
}

class _ContactsSetupPageState extends State<ContactsSetupPage> {
  String _t(String key) => AppStrings.text(
      context.read<SettingsController>().localeCode, key);

  bool _busy = false;

  Future<void> _requestAccess() async {
    setState(() => _busy = true);
    try {
      await FlutterContacts.requestPermission(readonly: true);
    } catch (_) {
      // Rad etilsa ham davom etamiz — keyin Kontaktlar sahifasida qayta
      // so'raladi.
    }
    if (!mounted) return;
    setState(() => _busy = false);
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Icon(Icons.contacts_rounded,
                  size: 64, color: theme.colorScheme.primary),
              const SizedBox(height: 24),
              Text(
                _t('onboarding_contacts_title'),
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              Text(
                _t('onboarding_contacts_body'),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const Spacer(),
              FilledButton(
                onPressed: _busy ? null : _requestAccess,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _busy
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : Text(_t('onboarding_contacts_connect'),
                        style: TextStyle(fontSize: 17)),
              ),
              const SizedBox(height: 4),
              TextButton(
                onPressed: _busy ? null : widget.onDone,
                child: Text(_t('onboarding_later')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
