import '../app_settings.dart';
import 'crash_reporter.dart';

CrashReporter createPlatformCrashReporter(AppSettings settings) =>
    const NoopCrashReporter();
