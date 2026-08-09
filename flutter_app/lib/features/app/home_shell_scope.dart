import 'package:flutter/widgets.dart';

/// Bo'limni ichkaridan almashtirish uchun. Suhbatlar ro'yxatining
/// sarlavhasidagi tugmalar ham shu orqali ishlaydi — ular yangi sahifa
/// ochsa, panel ustidan yopilib qolardi.
class HomeShellScope extends InheritedWidget {
  const HomeShellScope({
    super.key,
    required this.selectTab,
    required this.popTab,
    required super.child,
  });

  final void Function(int index) selectTab;

  /// Avvalgi bo'limga qaytaradi. Qaytadigan bo'lim bo'lmasa false.
  ///
  /// "Orqaga" Suhbatlar bo'limida ChatPage ga tushadi, shuning uchun
  /// bo'limlar tarixini u ham surishtira olishi kerak: Sozlamalardan
  /// ochilgan "Saqlangan xabarlar" yopilgach Sozlamalarga qaytish uchun.
  final bool Function() popTab;

  static HomeShellScope? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<HomeShellScope>();

  @override
  bool updateShouldNotify(HomeShellScope oldWidget) => false;
}

/// Panel bo'limlarining tartibi. Raqamlar bir necha joyda ishlatiladi.
class HomeTab {
  static const chats = 0;
  static const contacts = 1;
  static const settings = 2;
  static const profile = 3;
}
