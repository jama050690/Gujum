import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/network/session_store.dart';
import '../../l10n/app_strings.dart';
import '../settings/settings_controller.dart';
import 'auth_controller.dart';
import '../app/home_shell.dart';
import 'contacts_setup_page.dart';
import 'name_setup_page.dart';
import 'phone_setup_page.dart';

/// Kirgandan keyingi sozlash qadamlari: raqam → ism → kontaktlar.
///
/// Har bir qadam faqat kerak bo'lsa ko'rsatiladi. Google orqali kirgan
/// foydalanuvchida ism allaqachon bor, shuning uchun 2-qadam odatda bitta
/// tasdiqlash bosishiga aylanadi; eski akkauntlarda esa faqat yetishmayotgan
/// qadam chiqadi.
class OnboardingFlow extends StatefulWidget {
  const OnboardingFlow({super.key});

  /// Foydalanuvchiga hali sozlash kerakmi?
  static bool isNeeded(AuthController auth, SessionStore store) {
    if (!auth.isAuthenticated) return false;
    return auth.needsPhoneNumber ||
        _nameMissing(auth) ||
        !store.contactsAsked;
  }

  static bool _nameMissing(AuthController auth) {
    final name = auth.user?.fullName?.trim();
    return name == null || name.isEmpty;
  }

  @override
  State<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends State<OnboardingFlow> {
  bool _nameConfirmed = false;

  /// Qadamlar odatda holatdan kelib chiqadi (raqam bormi, ism bormi...), shu
  /// sababli "orqaga" ni shunchaki hisoblab bo'lmaydi: raqam saqlangandan
  /// keyin u qadam o'z-o'zidan yo'qoladi. Shuning uchun orqaga qaytilganda
  /// kerakli qadam ataylab majburlanadi. Saqlangan qiymat yo'qolmaydi —
  /// qadam qaytadan ko'rsatiladi va ustiga yozish mumkin.
  bool _forcePhoneStep = false;
  bool _forceNameStep = false;

  DateTime? _lastBackPress;

  _OnboardingStep _currentStep(AuthController auth, SessionStore store) {
    if (_forcePhoneStep || auth.needsPhoneNumber) return _OnboardingStep.phone;
    if (_forceNameStep ||
        (!_nameConfirmed && OnboardingFlow._nameMissing(auth))) {
      return _OnboardingStep.name;
    }
    if (!store.contactsAsked) return _OnboardingStep.contacts;
    return _OnboardingStep.done;
  }

  void _handleBack(BuildContext context, _OnboardingStep step) {
    switch (step) {
      case _OnboardingStep.contacts:
        setState(() => _forceNameStep = true);
        return;
      case _OnboardingStep.name:
        setState(() {
          _forceNameStep = false;
          _forcePhoneStep = true;
        });
        return;
      case _OnboardingStep.phone:
      case _OnboardingStep.done:
        // Birinchi qadam — ortga qaytadigan joy yo'q. Chat sahifasidagi
        // kabi ikki marta bosish kerak, aks holda bitta tasodifiy bosish
        // ro'yxatdan o'tishni yarim yo'lda tashlab chiqib ketardi.
        final now = DateTime.now();
        final last = _lastBackPress;
        if (last != null && now.difference(last) < const Duration(seconds: 2)) {
          SystemNavigator.pop();
          return;
        }
        _lastBackPress = now;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppStrings.text(
                context.read<SettingsController>().localeCode,
                'exit_press_again')),
            duration: const Duration(seconds: 2),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final store = context.read<SessionStore>();
    final step = _currentStep(auth, store);

    if (step == _OnboardingStep.done) {
      // Barcha qadamlar tugadi — to'g'ridan-to'g'ri ilovaga o'tamiz.
      //
      // Bu yerga tushish odatiy hol: oxirgi qadam SessionStore ga yozadi, u esa
      // ChangeNotifier emas, shuning uchun GujumApp qayta qurilmaydi va
      // OnboardingFlow ekranda qolaveradi. Avval bu holat SizedBox.shrink()
      // qaytarardi — ya'ni kontaktlar so'ralgandan keyin ekran bo'sh qolardi.
      return const HomeShell();
    }

    // Qadamlar Navigator marshrutlari emas — tizimning "orqaga" tugmasi ular
    // haqida bilmaydi va to'g'ridan-to'g'ri ilovadan chiqarib yuborardi.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleBack(context, step);
      },
      child: switch (step) {
        _OnboardingStep.phone => PhoneSetupPage(
            onDone: () => setState(() => _forcePhoneStep = false),
          ),
        // Ism bor bo'lsa ham bir marta tasdiqlatamiz — Google'dagi nom har
        // doim ham odam o'zini atagan nom emas.
        _OnboardingStep.name => NameSetupPage(
            onDone: () => setState(() {
              _forceNameStep = false;
              _nameConfirmed = true;
            }),
          ),
        _OnboardingStep.contacts => ContactsSetupPage(
            onDone: () async {
              await store.markContactsAsked();
              if (mounted) setState(() {});
            },
          ),
        _OnboardingStep.done => const HomeShell(),
      },
    );
  }
}

enum _OnboardingStep { phone, name, contacts, done }
