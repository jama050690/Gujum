import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../social/social_repository.dart';
import 'auth_controller.dart';
import 'phone_countries.dart';
import 'phone_hint_service.dart';
import '../../l10n/app_strings.dart';
import '../settings/settings_controller.dart';

/// Ro'yxatdan o'tishning 1-qadami: telefon raqami.
///
/// Ochilishi bilan SIM tanlagichini so'raydi — ikki SIM bo'lsa foydalanuvchi
/// bittasini bosadi va hech narsa yozmaydi. Tanlanmasa, davlat kodi bilan
/// raqam kiritish oynasi ochiladi: '+' oldindan turadi, standart kod +998,
/// raqam esa yozilayotganda o'sha davlat formatiga solinadi.
class PhoneSetupPage extends StatefulWidget {
  const PhoneSetupPage({super.key, this.onDone});

  final VoidCallback? onDone;

  @override
  State<PhoneSetupPage> createState() => _PhoneSetupPageState();
}

class _PhoneSetupPageState extends State<PhoneSetupPage> {
  String _t(String key) => AppStrings.text(
      context.read<SettingsController>().localeCode, key);

  final _controller = TextEditingController();
  PhoneCountry _country = defaultPhoneCountry;
  bool _saving = false;
  bool _askingSim = true;
  String? _error;
  // Raqam SIM tanlagichidan keldimi yoki qo'lda yozildimi — audit uchun.
  bool _fromSim = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _askSim());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _askSim() async {
    setState(() => _askingSim = true);
    final number = await PhoneHintService.requestSimNumber();
    if (!mounted) return;
    setState(() {
      _askingSim = false;
      if (number == null) return;
      // SIM dan kelgan raqam E.164 ko'rinishida: +998901234567.
      final matched = countryFromE164(number);
      final digits = number.replaceAll(RegExp(r'\D'), '');
      if (matched != null) {
        _country = matched;
        final national =
            digits.substring(matched.dialCode.replaceAll('+', '').length);
        _controller.text = matched.format(national);
      } else {
        _controller.text = digits;
      }
      _fromSim = true;
    });
  }

  String get _e164 {
    final digits = _controller.text.replaceAll(RegExp(r'\D'), '');
    return '${_country.dialCode}$digits';
  }

  Future<void> _save() async {
    final digits = _controller.text.replaceAll(RegExp(r'\D'), '');
    if (digits.length < _country.nationalLength) {
      setState(() => _error = _t('onboarding_phone_incomplete'));
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await context.read<SocialRepository>().savePhone(_e164, fromSim: _fromSim);
      if (!mounted) return;
      // Raqam saqlandi — keyingi qadamga o'tish uchun serverdan profilni
      // qayta so'rashning hojati yo'q. Avval refreshSession() kutilardi va
      // aynan shu yerda ekran qotib qolardi: ikkinchi so'rov sekin bo'lsa
      // yoki javob bermasa, "Davom etish" tugmasi aylanaverardi.
      await context.read<AuthController>().updateLocalProfile(phone: _e164);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.toString().contains('409')
            ? _t('onboarding_phone_taken')
            : _t('onboarding_save_failed');
      });
      return;
    }
    if (!mounted) return;
    setState(() => _saving = false);
    widget.onDone?.call();
  }

  Future<void> _pickCountry() async {
    final picked = await showModalBottomSheet<PhoneCountry>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final country in phoneCountries)
              ListTile(
                leading: Text(country.flag, style: const TextStyle(fontSize: 26)),
                title: Text(country.name),
                trailing: Text(
                  country.dialCode,
                  style: const TextStyle(fontSize: 16),
                ),
                onTap: () => Navigator.pop(context, country),
              ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _country = picked;
      // Format o'zgardi — bor raqamni yangi formatga solamiz.
      _controller.text =
          picked.format(_controller.text.replaceAll(RegExp(r'\D'), ''));
      _fromSim = false;
    });
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
              Icon(Icons.smartphone_rounded,
                  size: 56, color: theme.colorScheme.primary),
              const SizedBox(height: 20),
              Text(
                _t('onboarding_phone_title'),
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              Text(
                _t('onboarding_phone_body'),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 32),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Davlat kodi — bosilsa ro'yxat ochiladi.
                  InkWell(
                    onTap: _saving ? null : _pickCountry,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 12, vertical: 18),
                      decoration: BoxDecoration(
                        border: Border.all(color: theme.dividerColor),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_country.flag,
                              style: const TextStyle(fontSize: 22)),
                          const SizedBox(width: 6),
                          Text(
                            _country.dialCode,
                            style: const TextStyle(
                                fontSize: 20, fontWeight: FontWeight.w600),
                          ),
                          const Icon(Icons.arrow_drop_down_rounded),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      // Telefon klaviaturasi — harflar emas, katta raqamlar.
                      keyboardType: TextInputType.phone,
                      autofocus: false,
                      style: const TextStyle(fontSize: 20, letterSpacing: 1.1),
                      inputFormatters: [PhoneNumberFormatter(_country)],
                      onChanged: (_) {
                        if (_fromSim) _fromSim = false;
                        if (_error != null) setState(() => _error = null);
                      },
                      decoration: InputDecoration(
                        hintText: _country.hint,
                        border: const OutlineInputBorder(),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 18),
                        errorText: _error,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (_askingSim)
                const Center(
                  child: SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _saving ? null : _askSim,
                    icon: const Icon(Icons.sim_card_rounded, size: 18),
                    label: Text(_t('onboarding_phone_from_sim')),
                  ),
                ),
              const SizedBox(height: 20),
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
              const SizedBox(height: 4),
              TextButton(
                onPressed: _saving
                    ? null
                    : () => context.read<AuthController>().skipPhonePrompt(),
                child: Text(_t('onboarding_later')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
