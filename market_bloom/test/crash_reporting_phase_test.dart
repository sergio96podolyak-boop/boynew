import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomarket/services/analytics/analytics_backend.dart';
import 'package:pomarket/services/analytics/analytics_event.dart';
import 'package:pomarket/services/analytics/analytics_service.dart';
import 'package:pomarket/services/crash_reporting/crash_reporter.dart';
import 'package:pomarket/services/crash_reporting/crash_sanitizer.dart';
import 'package:pomarket/services/crash_reporting/error_reporting_coordinator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Flutter errors are forwarded while preserving the previous handler', () async {
    final analyticsBackend = _MemoryAnalyticsBackend();
    final crashReporter = _MemoryCrashReporter();
    var previousCalls = 0;
    final original = FlutterError.onError;
    FlutterError.onError = (_) => previousCalls++;
    final coordinator = ErrorReportingCoordinator(
      analytics: _analytics(analyticsBackend),
      crashReporter: crashReporter,
    )..install();

    FlutterError.reportError(
      FlutterErrorDetails(
        exception: StateError('private message'),
        stack: StackTrace.current,
        library: 'PoMarket test',
      ),
    );
    await _flush();

    expect(previousCalls, 1);
    expect(crashReporter.reports, hasLength(1));
    expect(crashReporter.reports.single.source, 'flutter');
    expect(crashReporter.reports.single.exceptionType, 'StateError');
    expect(analyticsBackend.events.single.name, AnalyticsEventName.errorRecorded);
    coordinator.restore();
    FlutterError.onError = original;
  });

  test('uncaught platform errors are forwarded and preserve return behavior', () async {
    final analyticsBackend = _MemoryAnalyticsBackend();
    final crashReporter = _MemoryCrashReporter();
    final original = ui.PlatformDispatcher.instance.onError;
    ui.PlatformDispatcher.instance.onError = (_, _) => true;
    final coordinator = ErrorReportingCoordinator(
      analytics: _analytics(analyticsBackend),
      crashReporter: crashReporter,
    )..install();

    final handled = coordinator.forwardPlatformError(
      ArgumentError('private message'),
      StackTrace.current,
    );
    await _flush();

    expect(handled, isTrue);
    expect(crashReporter.reports.single.source, 'platform');
    expect(crashReporter.reports.single.fatal, isTrue);
    expect(analyticsBackend.events.single.name, AnalyticsEventName.errorRecorded);
    coordinator.restore();
    ui.PlatformDispatcher.instance.onError = original;
  });

  test('no-op reporter is safe when Crashlytics is unavailable', () async {
    const reporter = NoopCrashReporter();

    expect(await reporter.initialize(), isFalse);
    expect(reporter.isAvailable, isFalse);
    await reporter.record(
      CrashReport(
        source: 'test',
        exceptionType: 'StateError',
        stackTrace: StackTrace.current,
      ),
    );
  });

  test('crash metadata sanitizer removes sensitive values', () {
    const sanitizer = CrashSanitizer();

    final result = sanitizer.sanitize(const <String, Object?>{
      'source': 'flutter',
      'screen': 'market',
      'savePayload': 'private-save',
      'receipt': 'private-receipt',
      'transactionId': 'private-transaction',
      'deviceSecret': 'private-secret',
      'count': 2,
    });

    expect(result, <String, Object>{
      'source': 'flutter',
      'screen': 'market',
      'count': 2,
    });
  });

  test('reporter failures are contained and analytics still receives the error', () async {
    final analyticsBackend = _MemoryAnalyticsBackend();
    final coordinator = ErrorReportingCoordinator(
      analytics: _analytics(analyticsBackend),
      crashReporter: _ThrowingCrashReporter(),
    );

    expect(
      () => coordinator.forwardPlatformError(
        StateError('failure'),
        StackTrace.current,
      ),
      returnsNormally,
    );
    await _flush();

    expect(analyticsBackend.events, hasLength(1));
  });

  test('initialization failures do not affect startup flow', () async {
    final reporter = _InitializationFailureReporter();

    expect(await reporter.initialize(), isFalse);
    expect(reporter.isAvailable, isFalse);
  });
}

AnalyticsService _analytics(_MemoryAnalyticsBackend backend) => AnalyticsService(
  backend: backend,
  hasConsent: () => true,
);

Future<void> _flush() => Future<void>.delayed(const Duration(milliseconds: 10));

class _MemoryAnalyticsBackend implements AnalyticsBackend {
  final List<AnalyticsEvent> events = <AnalyticsEvent>[];

  @override
  bool get isAvailable => true;

  @override
  Future<void> send(AnalyticsEvent event) async => events.add(event);
}

class _MemoryCrashReporter implements CrashReporter {
  final List<CrashReport> reports = <CrashReport>[];

  @override
  bool get isAvailable => true;

  @override
  Future<bool> initialize() async => true;

  @override
  Future<void> record(CrashReport report) async => reports.add(report);
}

class _ThrowingCrashReporter implements CrashReporter {
  @override
  bool get isAvailable => true;

  @override
  Future<bool> initialize() async => true;

  @override
  Future<void> record(CrashReport report) async {
    throw StateError('reporter unavailable');
  }
}

class _InitializationFailureReporter implements CrashReporter {
  @override
  bool get isAvailable => false;

  @override
  Future<bool> initialize() async {
    try {
      throw StateError('missing Firebase configuration');
    } on Object {
      return false;
    }
  }

  @override
  Future<void> record(CrashReport report) async {}
}
