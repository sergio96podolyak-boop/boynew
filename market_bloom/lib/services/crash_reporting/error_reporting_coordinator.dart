import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../analytics/analytics_event.dart';
import '../analytics/analytics_service.dart';
import 'crash_reporter.dart';
import 'crash_sanitizer.dart';

class ErrorReportingCoordinator {
  ErrorReportingCoordinator({
    required this.analytics,
    required this.crashReporter,
    this.sanitizer = const CrashSanitizer(),
  });

  final AnalyticsService analytics;
  final CrashReporter crashReporter;
  final CrashSanitizer sanitizer;

  FlutterExceptionHandler? _previousFlutterHandler;
  bool Function(Object, StackTrace)? _previousPlatformHandler;
  bool _installed = false;

  void install() {
    if (_installed) return;
    _installed = true;
    _previousFlutterHandler = FlutterError.onError;
    _previousPlatformHandler = ui.PlatformDispatcher.instance.onError;
    FlutterError.onError = forwardFlutterError;
    ui.PlatformDispatcher.instance.onError = forwardPlatformError;
  }

  void forwardFlutterError(FlutterErrorDetails details) {
    final type = sanitizer.safeType(details.exception);
    final library = sanitizer.safeLibrary(details.library);
    analytics.track(
      AnalyticsEventName.errorRecorded,
      parameters: <String, Object?>{
        'source': 'flutter',
        'error_type': type,
        'library': library,
      },
    );
    unawaited(
      _recordSafely(
        CrashReport(
          source: 'flutter',
          exceptionType: type,
          stackTrace: details.stack ?? StackTrace.current,
          library: library,
          fatal: false,
        ),
      ),
    );
    final previous = _previousFlutterHandler;
    if (previous != null && previous != forwardFlutterError) {
      previous(details);
    } else {
      FlutterError.presentError(details);
    }
  }

  bool forwardPlatformError(Object error, StackTrace stack) {
    final type = sanitizer.safeType(error);
    analytics.track(
      AnalyticsEventName.errorRecorded,
      parameters: <String, Object?>{
        'source': 'platform',
        'error_type': type,
      },
    );
    unawaited(
      _recordSafely(
        CrashReport(
          source: 'platform',
          exceptionType: type,
          stackTrace: stack,
          fatal: true,
        ),
      ),
    );
    final previous = _previousPlatformHandler;
    return previous?.call(error, stack) ?? false;
  }

  Future<void> _recordSafely(CrashReport report) async {
    try {
      await crashReporter.record(report);
    } on Object {
      // The crash reporter itself must never cause another application error.
    }
  }

  void restore() {
    if (!_installed) return;
    FlutterError.onError = _previousFlutterHandler;
    ui.PlatformDispatcher.instance.onError = _previousPlatformHandler;
    _installed = false;
  }
}
