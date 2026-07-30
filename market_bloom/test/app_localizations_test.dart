import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomarket/game/meta_models.dart';
import 'package:pomarket/services/app_localizations.dart';

void main() {
  test(
    'returns english strings and left-to-right layout for english locale',
    () {
      final localizations = AppLocalizations(const Locale('en'));

      expect(localizations.businessHubTitle, 'Business Hub');
      expect(localizations.scoreLabel, 'SCORE');
      expect(localizations.freeBonus, 'Free Bonus');
      expect(localizations.rewardCenterTitle, 'Reward Center');
      expect(localizations.isRtl, isFalse);
    },
  );

  test('returns arabic strings and right-to-left layout for arabic locale', () {
    final localizations = AppLocalizations(const Locale('ar'));

    expect(localizations.businessHubTitle, 'المركز التجاري');
    expect(localizations.scoreLabel, 'النتيجة');
    expect(localizations.freeBonus, 'مكافأة مجانية');
    expect(localizations.rewardCenterTitle, 'مركز المكافآت');
    expect(localizations.isRtl, isTrue);
  });

  test('achievement presentation stays localized outside English', () {
    final hebrew = AppLocalizations(const Locale('he'));
    final arabic = AppLocalizations(const Locale('ar'));

    for (final definition in AchievementCatalog.all) {
      expect(hebrew.achievementTitle(definition.id), isNot(definition.title));
      expect(
        hebrew.achievementDescription(definition.id),
        isNot(definition.description),
      );
      expect(arabic.achievementTitle(definition.id), isNot(definition.title));
      expect(
        arabic.achievementDescription(definition.id),
        isNot(definition.description),
      );
    }
  });
}
