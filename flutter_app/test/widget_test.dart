import 'package:flutter_test/flutter_test.dart';

import 'package:gujum_chat/l10n/app_strings.dart';

void main() {
  test('app strings fall back safely', () {
    expect(AppStrings.text('en', 'app_title'), 'Bootchat');
    expect(AppStrings.text('missing', 'app_title'), 'Bootchat');
  });
}
