import 'package:flutter/foundation.dart';

/// Pastdagi paneldagi bo'limlar tartibi.
class HomeTab {
  static const chats = 0;
  static const contacts = 1;
  static const settings = 2;
  static const profile = 3;
}

/// Qaysi bo'lim ochiqligi — ilova darajasidagi holat.
///
/// Ilgari bu HomeShell ning ichida edi va unga yetib borish uchun uchta
/// alohida yo'l qurilgandi:
///   - InheritedWidget (HomeShellScope) — bo'lim ichidagi vidjetlar uchun;
///   - onChatOpened kabi callback lar — Navigator.push bilan ochilgan
///     sahifalar uchun, chunki ular qobiqning ostida emas, yonida turadi
///     va InheritedWidget ni ko'rmaydi;
///   - findAncestorStateOfType — qolganlari uchun.
///
/// Holat MaterialApp dan yuqorida provayder sifatida turganda bularning
/// hech biri kerak emas: istalgan context uni o'qiy oladi.
class NavigationController extends ChangeNotifier {
  int _index = HomeTab.chats;

  /// Qayerdan kelinganini eslaydigan bitta qadam.
  ///
  /// To'liq tarix emas: ro'yxat bo'lganda Suhbatlar ↔ Kontaktlar o'rtasida
  /// besh marta yurgan odam chiqish uchun besh marta "orqaga" bosishi
  /// kerak bo'lardi.
  int? _returnTab;

  /// Ochilgan bo'limlar. Bo'lim birinchi ochilgandagina quriladi — aks
  /// holda ilova ishga tushishi bilan Kontaktlar manzillar kitobini
  /// o'qishni, Profil esa serverdan yuklashni boshlab yuborardi.
  final Set<int> _visited = <int>{HomeTab.chats};

  int get index => _index;
  bool isVisited(int tab) => _visited.contains(tab);

  void selectTab(int value) {
    if (value == _index) return;
    _returnTab = _index;
    _visited.add(value);
    _index = value;
    notifyListeners();
  }

  /// Suhbatlarga qaytaradi va tarixni tozalaydi.
  ///
  /// selectTab dan foydalanib bo'lmaydi: u "qayerdan kelindi" ni yozib
  /// qo'yadi, ya'ni "orqaga" bilan uyga qaytish yangi yozuv yaratardi va
  /// keyingi bosish yana o'sha bo'limga olib borardi — ikki bo'lim
  /// o'rtasida cheksiz aylanish. Uy — oxirgi nuqta, undan keyin faqat
  /// chiqish.
  void goHome() {
    _returnTab = null;
    if (_index == HomeTab.chats) return;
    _index = HomeTab.chats;
    notifyListeners();
  }

  /// Avvalgi bo'limga qaytaradi. Qaytadigan joy bo'lmasa false — bunda
  /// "orqaga" odatdagicha davom etadi (chiqish so'raladi).
  bool popTab() {
    final target = _returnTab;
    if (target == null || target == _index) return false;
    _returnTab = null;
    _index = target;
    notifyListeners();
    return true;
  }
}
