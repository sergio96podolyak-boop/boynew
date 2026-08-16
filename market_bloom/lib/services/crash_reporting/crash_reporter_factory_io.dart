import '../app_settings.dart';
import 'crash_reporter.dart';
import 'firebase_crash_reporter.dart';

CrashReporter createPlatformCrashReporter(AppSettings settings) =>
    FirebaseCrashReporter(hasConsent: () => settings.crashReportingEnabled);
