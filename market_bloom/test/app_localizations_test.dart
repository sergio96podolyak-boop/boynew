import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomarket/services/app_localizations.dart';

void main() {
  test(
    'returns english strings and left-to-right layout for english locale',
    () {
      final localizations = AppLocalizations(const Locale('en'));

      expect(localizations.businessHubTitle, 'Business Hub');
      expect(localizations.scoreLabel, 'SCORE');
      expect(localizations.isRtl, isFalse);
    },
  );

  test('returns arabic strings and right-to-left layout for arabic locale', () {
    final localizations = AppLocalizations(const Locale('ar'));

    expect(localizations.businessHubTitle, 'المركز التجاري');
    expect(localizations.scoreLabel, 'النتيجة');
    expect(localizations.isRtl, isTrue);
  });
}
