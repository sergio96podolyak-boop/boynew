import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

import 'crash_reporter.dart';
import 'crash_sanitizer.dart';

class FirebaseCrashReporter
    implements CrashReporter, ConsentAwareCrashReporter {
  FirebaseCrashReporter({
    required this.hasConsent,
    FirebaseCrashlytics? crashlytics,
    Future<FirebaseApp> Function()? initializeFirebase,
    this.sanitizer = const CrashSanitizer(),
  }) : _crashlytics = crashlytics ?? FirebaseCrashlytics.instance,
       _initializeFirebase = initializeFirebase ?? Firebase.initializeApp;

  final bool Function() hasConsent;
  final FirebaseCrashlytics _crashlytics;
  final Future<FirebaseApp> Function() _initializeFirebase;
  final CrashSanitizer sanitizer;

  bool _initialized = false;
  Future<bool>? _initialization;

  @override
  bool get isAvailable =>
      (Platform.isAndroid || Platform.isIOS) && _initialized && hasConsent();

  @override
  Future<bool> initialize() {
    final active = _initialization;
    if (active != null) return active;
    final future = _initializeSafely();
    _initialization = future;
    return future;
  }

  Future<bool> _initializeSafely() async {
    if ((!Platform.isAndroid && !Platform.isIOS) || !hasConsent()) {
      return false;
    }
    try {
      await _initializeFirebase().timeout(const Duration(seconds: 5));
      await _crashlytics.setCrashlyticsCollectionEnabled(true);
      _initialized = true;
      return true;
    } on Object {
      _initialized = false;
      return false;
    } finally {
      _initialization = null;
    }
  }

  @override
  Future<void> updateConsent(bool enabled) async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    if (enabled) {
      await initialize();
      return;
    }
    try {
      if (_initialized) {
        await _crashlytics.setCrashlyticsCollectionEnabled(false);
      }
    } on Object {
      // Disabling collection is best-effort and must remain non-blocking.
    }
  }

  @override
  Future<void> record(CrashReport report) async {
    if (!hasConsent()) return;
    if (!_initialized && !await initialize()) return;
    try {
      final metadata = sanitizer.sanitize(<String, Object?>{
        'source': report.source,
        'library': report.library,
        ...report.metadata,
      });
      for (final entry in metadata.entries) {
        await _crashlytics.setCustomKey(entry.key, entry.value);
      }
      await _crashlytics.recordError(
        StateError('PoMarket ${report.exceptionType}'),
        report.stackTrace,
        fatal: report.fatal,
        reason: report.source,
      );
    } on Object {
      // Crash reporting failures are intentionally contained.
    }
  }
}
