import 'dart:async';

import '../app_settings.dart';
import '../crash_reporting/crash_reporter.dart';
import '../monetization_service.dart';

/// Applies the persisted privacy source of truth to optional runtime services.
class PrivacyRuntimeCoordinator {
  PrivacyRuntimeCoordinator({
    required this.settings,
    required this.crashReporter,
    required this.monetization,
  });

  final AppSettings settings;
  final CrashReporter crashReporter;
  final MonetizationService monetization;
  bool _started = false;
  bool _monetizationInitialized = false;

  void start() {
    if (_started) return;
    _started = true;
    settings.addListener(_apply);
    _apply();
  }

  void _apply() {
    if (!settings.isLoaded) return;
    if (crashReporter is ConsentAwareCrashReporter) {
      unawaited(
        (crashReporter as ConsentAwareCrashReporter).updateConsent(
          settings.crashReportingEnabled,
        ),
      );
    }
    if (settings.privacyConsent.hasDecision && !_monetizationInitialized) {
      _monetizationInitialized = true;
      unawaited(_initializeMonetizationSafely());
    } else if (monetization is ConsentAwareMonetizationService) {
      unawaited(
        _refreshMonetizationSafely(
          monetization as ConsentAwareMonetizationService,
        ),
      );
    }
  }

  Future<void> _initializeMonetizationSafely() async {
    try {
      await monetization.initialize().timeout(const Duration(seconds: 4));
    } on Object {
      _monetizationInitialized = false;
    }
  }

  Future<void> _refreshMonetizationSafely(
    ConsentAwareMonetizationService service,
  ) async {
    try {
      await service.refreshConsent();
    } on Object {
      // Optional monetization consent refresh must never block gameplay.
    }
  }

  void dispose() {
    settings.removeListener(_apply);
  }
}
