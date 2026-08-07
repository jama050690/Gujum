import 'package:flutter_test/flutter_test.dart';

import 'package:gujum_chat/l10n/app_strings.dart';

void main() {
  test('app strings fall back safely', () {
    expect(AppStrings.text('en', 'app_title'), 'Gujum');
    // Noma'lum til kodi — inglizchaga tushadi, xato bermaydi.
    expect(AppStrings.text('missing', 'app_title'), 'Gujum');
  });

  test('every locale carries the same keys', () {
    // Kalit faqat bitta tilda qolib ketishi oson: shu test uni ushlaydi.
    // (Ilgari 8 ta qo'ng'iroq kaliti faqat ruschada bor edi.)
    const probes = [
      'app_title',
      'call_accept',
      'call_decline',
      'call_return',
      'call_busy',
      'call_connection_failed',
      'recent_calls',
      'new_contact',
    ];
    for (final locale in AppStrings.supportedLocales) {
      for (final key in probes) {
        expect(
          AppStrings.text(locale, key),
          isNot(key),
          reason: '"\$key" tarjimasi "\$locale" tilida yo\'q',
        );
      }
    }
  });
}
