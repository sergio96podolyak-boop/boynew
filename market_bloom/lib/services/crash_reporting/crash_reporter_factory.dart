import '../app_settings.dart';
import 'crash_reporter.dart';
import 'crash_reporter_factory_stub.dart'
    if (dart.library.io) 'crash_reporter_factory_io.dart' as platform;

CrashReporter createCrashReporter(AppSettings settings) =>
    platform.createPlatformCrashReporter(settings);
