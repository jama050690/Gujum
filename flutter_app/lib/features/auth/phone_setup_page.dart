import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../social/social_repository.dart';
import 'auth_controller.dart';
import 'phone_hint_service.dart';

/// Kirgandan keyin bir marta ko'rsatiladigan telefon raqami ekrani.
///
/// Ochilishi bilan SIM tanlagichini so'raydi — ikki SIM bo'lsa foydalanuvchi
/// bittasini bosadi va yozishga hojat qolmaydi. Tanlanmasa, raqamni qo'lda
/// kiritish uchun telefon klaviaturasi ochiladi.
class PhoneSetupPage extends StatefulWidget {
  const PhoneSetupPage({super.key});

  @override
  State<PhoneSetupPage> createState() => _PhoneSetupPageState();
}

class _PhoneSetupPageState extends State<PhoneSetupPage> {
  final _controller = TextEditingController();
  bool _saving = false;
  bool _askingSim = true;
  String? _error;
  // Raqam SIM tanlagichidan keldimi yoki qo'lda yozildimi — kelajakda
  // suiiste'molni aniqlash uchun foydali signal.
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
    final number = await PhoneHintService.requestSimNumber();
    if (!mounted) return;
    setState(() {
      _askingSim = false;
      if (number != null) {
        _controller.text = number;
        _fromSim = true;
      } else if (_controller.text.isEmpty) {
        _controller.text = '+998 ';
        _controller.selection =
            TextSelection.collapsed(offset: _controller.text.length);
      }
    });
  }

  Future<void> _save() async {
    final phone = _controller.text.trim();
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 9) {
      setState(() => _error = "Telefon raqamini to'liq kiriting");
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await context.read<SocialRepository>().savePhone(phone);
      await context.read<AuthController>().refreshSession();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        // 409 — raqam boshqa akkauntda.
        _error = e.toString().contains('409')
            ? "Bu raqam boshqa akkauntga biriktirilgan"
            : "Saqlab bo'lmadi, qaytadan urinib ko'ring";
      });
      return;
    }
    if (!mounted) return;
    setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),
              Icon(Icons.smartphone_rounded,
                  size: 64, color: theme.colorScheme.primary),
              const SizedBox(height: 24),
              Text(
                'Telefon raqamingiz',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              Text(
                "Raqamingizni kiriting — shunda tanishlaringiz sizni "
                "kontaktlaridan topa oladi. Hech kimga ko'rsatilmaydi.",
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 32),
              TextField(
                controller: _controller,
                // Telefon klaviaturasi — harflar emas, katta raqamlar.
                keyboardType: TextInputType.phone,
                autofocus: false,
                style: const TextStyle(fontSize: 22, letterSpacing: 1.2),
                textAlign: TextAlign.center,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9+\s\-()]')),
                  LengthLimitingTextInputFormatter(20),
                ],
                onChanged: (_) {
                  if (_fromSim) _fromSim = false;
                  if (_error != null) setState(() => _error = null);
                },
                decoration: InputDecoration(
                  hintText: '+998 90 123 45 67',
                  border: const OutlineInputBorder(),
                  errorText: _error,
                  suffixIcon: IconButton(
                    tooltip: 'SIM kartadan tanlash',
                    icon: const Icon(Icons.sim_card_rounded),
                    onPressed: _saving ? null : _askSim,
                  ),
                ),
              ),
              if (_askingSim) ...[
                const SizedBox(height: 16),
                const Center(
                  child: SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ],
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
                    : const Text('Davom etish', style: TextStyle(fontSize: 17)),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _saving
                    ? null
                    : () => context.read<AuthController>().skipPhonePrompt(),
                child: const Text('Keyinroq'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
