import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/network/session_store.dart';
import 'auth_controller.dart';
import '../chat/chat_page.dart';
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

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final store = context.read<SessionStore>();

    if (auth.needsPhoneNumber) {
      return const PhoneSetupPage();
    }

    // Ism bor bo'lsa ham bir marta tasdiqlatamiz — Google'dagi nom har doim
    // ham odam o'zini atagan nom emas.
    if (!_nameConfirmed && OnboardingFlow._nameMissing(auth)) {
      return NameSetupPage(
        onDone: () => setState(() => _nameConfirmed = true),
      );
    }

    if (!store.contactsAsked) {
      return ContactsSetupPage(
        onDone: () async {
          await store.markContactsAsked();
          if (mounted) setState(() {});
        },
      );
    }

    // Barcha qadamlar tugadi — to'g'ridan-to'g'ri ilovaga o'tamiz.
    //
    // Bu yerga tushish odatiy hol: oxirgi qadam SessionStore ga yozadi, u esa
    // ChangeNotifier emas, shuning uchun BootchatApp qayta qurilmaydi va
    // OnboardingFlow ekranda qolaveradi. Avval bu holat SizedBox.shrink()
    // qaytarardi — ya'ni kontaktlar so'ralgandan keyin ekran bo'sh qolardi.
    return const ChatPage();
  }
}
