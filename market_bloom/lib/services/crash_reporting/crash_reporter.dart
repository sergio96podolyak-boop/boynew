class CrashReport {
  const CrashReport({
    required this.source,
    required this.exceptionType,
    required this.stackTrace,
    this.library,
    this.fatal = false,
    this.metadata = const <String, Object?>{},
  });

  final String source;
  final String exceptionType;
  final StackTrace stackTrace;
  final String? library;
  final bool fatal;
  final Map<String, Object?> metadata;
}

abstract interface class CrashReporter {
  bool get isAvailable;
  Future<bool> initialize();
  Future<void> record(CrashReport report);
}

abstract interface class ConsentAwareCrashReporter {
  Future<void> updateConsent(bool enabled);
}

class NoopCrashReporter implements CrashReporter, ConsentAwareCrashReporter {
  const NoopCrashReporter();

  @override
  bool get isAvailable => false;
  @override
  Future<bool> initialize() async => false;
  @override
  Future<void> record(CrashReport report) async {}
  @override
  Future<void> updateConsent(bool enabled) async {}
}
