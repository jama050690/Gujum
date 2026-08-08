import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/network/api_client.dart';
import '../../l10n/app_strings.dart';
import '../settings/settings_controller.dart';
import 'auth_controller.dart';
import 'phone_countries.dart';
import 'phone_hint_service.dart';

/// Google hisobi yo'q qurilmalar uchun kirish: raqam va ism, tamom.
///
/// Ilgari bu yerda username/parol formasi turardi — u ancha oldin
/// ishlatilmay qo'yilgan edi va yangi foydalanuvchida umuman paroli yo'q.
///
/// DIQQAT: raqam tasdiqlanmaydi. Kim qaysi raqamni yozsa, o'sha raqamli
/// akkauntga kiradi. Bu bilib qilingan vaqtinchalik qaror — barqaror
/// versiyadan keyin SMS kodi qo'shiladi.
class PhoneLoginPage extends StatefulWidget {
  const PhoneLoginPage({super.key, required this.onBack});

  final VoidCallback onBack;

  @override
  State<PhoneLoginPage> createState() => _PhoneLoginPageState();
}

class _PhoneLoginPageState extends State<PhoneLoginPage> {
  final _phoneController = TextEditingController();
  final _nameController = TextEditingController();
  PhoneCountry _country = defaultPhoneCountry;
  bool _submitting = false;
  bool _askingSim = true;
  String? _error;

  String _t(String key) =>
      AppStrings.text(context.read<SettingsController>().localeCode, key);

  @override
  void initState() {
    super.initState();
    // SIM dagi raqamni taklif qilamiz — foydalanuvchi hech narsa yozmasligi
    // ham mumkin. Onboarding dagi qadam ham shunday ishlaydi.
    WidgetsBinding.instance.addPostFrameCallback((_) => _prefillFromSim());
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _prefillFromSim() async {
    final number = await PhoneHintService.requestSimNumber();
    if (!mounted) return;
    setState(() {
      _askingSim = false;
      if (number == null) return;
      final matched = countryFromE164(number);
      final digits = number.replaceAll(RegExp(r'\D'), '');
      if (matched != null) {
        _country = matched;
        _phoneController.text = matched
            .format(digits.substring(matched.dialCode.replaceAll('+', '').length));
      } else {
        _phoneController.text = digits;
      }
    });
  }

  String get _e164 =>
      '${_country.dialCode}${_phoneController.text.replaceAll(RegExp(r'\D'), '')}';

  Future<void> _pickCountry() async {
    final picked = await showModalBottomSheet<PhoneCountry>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final country in phoneCountries)
              ListTile(
                leading:
                    Text(country.flag, style: const TextStyle(fontSize: 26)),
                title: Text(country.name),
                trailing: Text(country.dialCode,
                    style: const TextStyle(fontSize: 16)),
                onTap: () => Navigator.pop(sheetContext, country),
              ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _country = picked;
      _phoneController.text =
          picked.format(_phoneController.text.replaceAll(RegExp(r'\D'), ''));
    });
  }

  Future<void> _submit() async {
    final digits = _phoneController.text.replaceAll(RegExp(r'\D'), '');
    if (digits.length < _country.nationalLength) {
      setState(() => _error = _t('onboarding_phone_incomplete'));
      return;
    }
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = _t('onboarding_name_required'));
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await context
          .read<AuthController>()
          .loginWithPhone(phone: _e164, fullName: name);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = error.message;
      });
      return;
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = _t('onboarding_save_failed');
      });
      return;
    }
    if (!mounted) return;
    setState(() => _submitting = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Til o'zgarsa matnlar ham yangilanishi kerak.
    context.watch<SettingsController>();

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: _submitting ? null : widget.onBack),
        title: Text(_t('other_sign_in_methods')),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
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
              const SizedBox(height: 28),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  InkWell(
                    onTap: _submitting ? null : _pickCountry,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 18),
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
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      style: const TextStyle(fontSize: 20, letterSpacing: 1.1),
                      inputFormatters: [PhoneNumberFormatter(_country)],
                      onChanged: (_) {
                        if (_error != null) setState(() => _error = null);
                      },
                      decoration: InputDecoration(
                        hintText: _country.hint,
                        border: const OutlineInputBorder(),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 18),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
                decoration: InputDecoration(
                  labelText: _t('onboarding_name_title'),
                  hintText: _t('onboarding_name_hint'),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              if (_askingSim)
                const Center(
                  child: SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _submitting ? null : _submit,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _submitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(_t('onboarding_continue')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
