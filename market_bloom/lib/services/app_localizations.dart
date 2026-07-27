import 'package:flutter/widgets.dart';

class AppLocalizations {
  AppLocalizations(this.locale);

  final Locale locale;

  static const supportedLocales = <Locale>[Locale('en'), Locale('ar')];

  bool get isRtl => locale.languageCode == 'ar';

  String get businessHubTitle => switch (locale.languageCode) {
    'ar' => 'المركز التجاري',
    _ => 'Business Hub',
  };

  String get businessHubSubtitle => switch (locale.languageCode) {
    'ar' => 'تقدمك وسجلاتك ومكافآتك',
    _ => 'Your progress, records, and rewards',
  };

  String get scoreLabel => switch (locale.languageCode) {
    'ar' => 'النتيجة',
    _ => 'SCORE',
  };

  String get achievementsTabLabel => switch (locale.languageCode) {
    'ar' => 'الإنجازات',
    _ => 'ACHIEVEMENTS',
  };

  String get statsTabLabel => switch (locale.languageCode) {
    'ar' => 'الإحصائيات',
    _ => 'STATS',
  };

  String get leaderboardTabLabel => switch (locale.languageCode) {
    'ar' => 'الترتيب',
    _ => 'LEADERBOARD',
  };

  String get settingsTabLabel => switch (locale.languageCode) {
    'ar' => 'الإعدادات',
    _ => 'SETTINGS',
  };

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations) ??
        AppLocalizations(const Locale('en'));
  }
}
