import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../social/social_repository.dart';
import 'auth_controller.dart';
import '../../l10n/app_strings.dart';
import '../settings/settings_controller.dart';

/// Ro'yxatdan o'tishning 2-qadami: ism.
///
/// Google orqali kirilgan bo'lsa ism allaqachon ma'lum — maydon to'ldirilgan
/// holda ochiladi va foydalanuvchi shunchaki tasdiqlaydi.
class NameSetupPage extends StatefulWidget {
  const NameSetupPage({super.key, this.onDone});

  final VoidCallback? onDone;

  @override
  State<NameSetupPage> createState() => _NameSetupPageState();
}

class _NameSetupPageState extends State<NameSetupPage> {
  String _t(String key) => AppStrings.text(
      context.read<SettingsController>().localeCode, key);

  late final TextEditingController _controller;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final user = context.read<AuthController>().user;
    _controller = TextEditingController(text: user?.fullName ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _controller.text.trim();
    if (name.isEmpty) {
      setState(() => _error = _t('onboarding_name_required'));
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final repository = context.read<SocialRepository>();
      final auth = context.read<AuthController>();
      await repository.saveFullName(name);
      await auth.refreshSession();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = _t('onboarding_save_failed');
      });
      return;
    }
    if (!mounted) return;
    setState(() => _saving = false);
    widget.onDone?.call();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(Icons.person_rounded,
                  size: 56, color: theme.colorScheme.primary),
              const SizedBox(height: 20),
              Text(
                _t('onboarding_name_title'),
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              Text(
                _t('onboarding_name_body'),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 32),
              TextField(
                controller: _controller,
                textCapitalization: TextCapitalization.words,
                style: const TextStyle(fontSize: 20),
                textAlign: TextAlign.center,
                maxLength: 50,
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
                decoration: InputDecoration(
                  hintText: _t('onboarding_name_hint'),
                  border: const OutlineInputBorder(),
                  errorText: _error,
                  counterText: '',
                ),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _saving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : Text(_t('onboarding_continue'),
                        style: const TextStyle(fontSize: 17)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
