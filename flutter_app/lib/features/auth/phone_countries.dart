import 'package:flutter/services.dart';

/// Bitta davlatning raqam formati.
///
/// [groups] — milliy raqamning bo'laklari. Masalan O'zbekistonda 9 ta raqam
/// 2-3-2-2 ko'rinishida ajratiladi: 90-123-45-67.
class PhoneCountry {
  const PhoneCountry({
    required this.iso,
    required this.dialCode,
    required this.flag,
    required this.name,
    required this.groups,
  });

  final String iso;
  final String dialCode; // '+998'
  final String flag;
  final String name;
  final List<int> groups;

  int get nationalLength => groups.fold(0, (sum, g) => sum + g);

  /// Namuna matn: '90-123-45-67'
  String get hint {
    var digit = 0;
    return groups
        .map((g) => List.generate(g, (_) => '${(digit++ % 9) + 1}').join())
        .join('-');
  }

  /// Raqamlarni guruhlarga bo'lib, orasiga '-' qo'yadi.
  String format(String digits) {
    final buffer = StringBuffer();
    var index = 0;
    for (final size in groups) {
      if (index >= digits.length) break;
      if (index > 0) buffer.write('-');
      final end = (index + size).clamp(0, digits.length);
      buffer.write(digits.substring(index, end));
      index = end;
    }
    // Formatdan oshib ketgan raqamlar (noto'g'ri davlat tanlangan bo'lishi
    // mumkin) yo'qolmasin — oxiriga qo'shib qo'yamiz.
    if (index < digits.length) {
      if (index > 0) buffer.write('-');
      buffer.write(digits.substring(index));
    }
    return buffer.toString();
  }
}

/// Hozircha kerak bo'lgan davlatlar. Ro'yxat kengaytiriladigan qilib
/// tuzilgan — yangi davlat qo'shish uchun bitta qator yetarli.
const phoneCountries = <PhoneCountry>[
  PhoneCountry(
    iso: 'UZ', dialCode: '+998', flag: '🇺🇿', name: "O'zbekiston",
    groups: [2, 3, 2, 2], // 90-123-45-67
  ),
  PhoneCountry(
    iso: 'RU', dialCode: '+7', flag: '🇷🇺', name: 'Rossiya',
    groups: [3, 3, 2, 2], // 900-123-45-67
  ),
  PhoneCountry(
    iso: 'KZ', dialCode: '+7', flag: '🇰🇿', name: "Qozog'iston",
    groups: [3, 3, 2, 2], // 700-123-45-67
  ),
  PhoneCountry(
    iso: 'KR', dialCode: '+82', flag: '🇰🇷', name: 'Koreya',
    groups: [2, 4, 4], // 10-1234-5678
  ),
  PhoneCountry(
    iso: 'TR', dialCode: '+90', flag: '🇹🇷', name: 'Turkiya',
    groups: [3, 3, 2, 2], // 532-123-45-67
  ),
  PhoneCountry(
    iso: 'TM', dialCode: '+993', flag: '🇹🇲', name: 'Turkmaniston',
    groups: [2, 6], // 65-123456
  ),
  PhoneCountry(
    iso: 'TJ', dialCode: '+992', flag: '🇹🇯', name: 'Tojikiston',
    groups: [2, 3, 4], // 90-123-4567
  ),
];

const defaultPhoneCountry = phoneCountries[0]; // O'zbekiston

/// E.164 raqamdan (masalan SIM tanlagichidan kelgan '+998901234567')
/// davlatni topadi. Eng uzun dialCode ustun — '+7' va '+998' chalkashmasin.
PhoneCountry? countryFromE164(String e164) {
  final digits = e164.replaceAll(RegExp(r'\D'), '');
  final sorted = [...phoneCountries]
    ..sort((a, b) => b.dialCode.length.compareTo(a.dialCode.length));
  for (final country in sorted) {
    final code = country.dialCode.replaceAll('+', '');
    if (digits.startsWith(code)) return country;
  }
  return null;
}

/// Kiritilayotgan raqamni tanlangan davlat formatiga solib boradi.
class PhoneNumberFormatter extends TextInputFormatter {
  PhoneNumberFormatter(this.country);

  final PhoneCountry country;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    // Formatdagi barcha bo'shliqlarni to'ldirgandan keyin yozishni to'xtatamiz.
    final limited = digits.length > country.nationalLength
        ? digits.substring(0, country.nationalLength)
        : digits;
    final formatted = country.format(limited);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
