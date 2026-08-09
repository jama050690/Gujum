import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_strings.dart';
import '../call/call_controller.dart';
import '../chat/chat_controller.dart';
import '../settings/settings_controller.dart';
import 'navigation_controller.dart';

/// Butun ilova uchun bitta "orqaga" ishlovchisi.
///
/// Ilgari uchta PopScope bor edi — qo'ng'iroq oynasida, qobiqda va chat
/// sahifasida. Flutter bitta bosishda ro'yxatdagi HAMMASINI chaqiradi,
/// shuning uchun ular bir-birining ishiga aralashardi: qo'ng'iroq
/// kichrayishi bilan birga orqadagi suhbat yopilib ketardi, menyu
/// yopilishi chiqish so'roviga aylanardi. Har biriga "men ishlamayman"
/// degan tekshiruvlar qo'shib chiqilgandi.
///
/// Endi holat butunlay kontrollerlarda, ya'ni tartibni bitta joyda
/// yozish mumkin. Tartib yuqoridan pastga: eng ichki holat birinchi
/// yopiladi.
class AppBackHandler extends StatefulWidget {
  const AppBackHandler({super.key, required this.child});

  final Widget child;

  @override
  State<AppBackHandler> createState() => _AppBackHandlerState();
}

class _AppBackHandlerState extends State<AppBackHandler> {
  DateTime? _lastBackPress;

  /// true — bosish ichki holatni yopdi (suhbat, qidiruv, bo'lim...).
  /// false — yopadigan narsa qolmadi, chiqish so'raladi.
  bool _handleBack(BuildContext context) {
    final call = context.read<CallController>();
    final chat = context.read<ChatController>();
    final nav = context.read<NavigationController>();

    // 1. Qo'ng'iroq oynasi: kiruvchi qo'ng'iroqda hech narsa qilinmaydi
    //    (javob berish yoki rad etish kerak), ochiq qo'ng'iroqda esa
    //    kichrayadi.
    if (call.hasIncomingCall) return true;
    if (call.hasSession && !call.isCallUiMinimized) {
      call.isCallUiMinimized = true;
      return true;
    }

    // 2-4. Suhbat ichidagilar: tanlash → qidiruv → suhbatning o'zi.
    if (nav.index == HomeTab.chats) {
      if (chat.hasMessageSelection) {
        chat.clearMessageSelection();
        return true;
      }
      if (chat.chatSearchActive) {
        chat.closeChatSearch();
        return true;
      }
      if (chat.activeChat != null) {
        chat.showSavedMessages ? chat.closeSavedMessages() : chat.closeChat();
        return true;
      }
      // 5-6. Ro'yxat ustidagilar: qidiruv → arxiv.
      if (chat.inboxSearchOpen) {
        chat.closeInboxSearch();
        return true;
      }
      if (chat.showArchived) {
        chat.closeArchive();
        return true;
      }
    }

    // 7. Boshqa bo'limdan kelingan bo'lsa — o'sha yerga qaytamiz.
    if (nav.popTab()) return true;
    if (nav.index != HomeTab.chats) {
      nav.selectTab(HomeTab.chats);
      return true;
    }

    // 8. Chiqish — ikki marta bosilganda. Taymer yuqoridagi qadamlarda
    //    tozalanadi: aks holda bir marta ogohlantirilgach, oradagi
    //    bosishlardan keyin ilova ogohlantirishsiz yopilardi.
    final now = DateTime.now();
    final last = _lastBackPress;
    if (last != null && now.difference(last) < const Duration(seconds: 2)) {
      // Qo'ng'iroq ketayotgan bo'lsa ilovani o'ldirmaymiz: aktivlik
      // tugatilsa WebRTC ham o'ladi, bildirishnoma esa ekranda qoladi.
      if (call.isCallActive) {
        call.moveAppToBackground();
        return false;
      }
      SystemNavigator.pop();
      return false;
    }
    _lastBackPress = now;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppStrings.text(
          context.read<SettingsController>().localeCode,
          'exit_press_again',
        )),
        duration: const Duration(seconds: 2),
      ),
    );
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        // Bosish ichki holatni yopgan bo'lsa, chiqish hisobi qaytadan
        // boshlanadi: "yana bir marta bosing" ogohlantirishi oradagi
        // bosishlardan keyin kuchda qolmasin.
        if (_handleBack(context)) _lastBackPress = null;
      },
      child: widget.child,
    );
  }
}
