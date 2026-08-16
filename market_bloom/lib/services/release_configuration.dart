import 'package:flutter/foundation.dart';

import 'release_platform_stub.dart'
    if (dart.library.io) 'release_platform_io.dart' as platform;

/// Compile-time production configuration used by Android and iOS releases.
///
/// Protected values remain supplied with `--dart-define`; this class only
/// verifies that release builds cannot start with missing or insecure values.
class ReleaseConfiguration {
  const ReleaseConfiguration({
    required this.privacyPolicyUrl,
    required this.cloudSaveEndpoint,
    required this.purchaseVerificationEndpoint,
    required this.androidRewardedAdUnitId,
    required this.iosRewardedAdUnitId,
    required this.androidInterstitialAdUnitId,
    required this.iosInterstitialAdUnitId,
  });

  factory ReleaseConfiguration.fromEnvironment() => const ReleaseConfiguration(
    privacyPolicyUrl: String.fromEnvironment('POMARKET_PRIVACY_POLICY_URL'),
    cloudSaveEndpoint: String.fromEnvironment('POMARKET_CLOUD_SAVE_ENDPOINT'),
    purchaseVerificationEndpoint: String.fromEnvironment(
      'POMARKET_PURCHASE_VERIFICATION_ENDPOINT',
    ),
    androidRewardedAdUnitId: String.fromEnvironment('ADMOB_REWARDED_ANDROID'),
    iosRewardedAdUnitId: String.fromEnvironment('ADMOB_REWARDED_IOS'),
    androidInterstitialAdUnitId: String.fromEnvironment(
      'ADMOB_INTERSTITIAL_ANDROID',
    ),
    iosInterstitialAdUnitId: String.fromEnvironment('ADMOB_INTERSTITIAL_IOS'),
  );

  final String privacyPolicyUrl;
  final String cloudSaveEndpoint;
  final String purchaseVerificationEndpoint;
  final String androidRewardedAdUnitId;
  final String iosRewardedAdUnitId;
  final String androidInterstitialAdUnitId;
  final String iosInterstitialAdUnitId;

  List<String> validationErrors({
    required bool android,
    required bool ios,
  }) {
    final errors = <String>[];
    _requireHttps(errors, 'POMARKET_PRIVACY_POLICY_URL', privacyPolicyUrl);
    _requireHttps(errors, 'POMARKET_CLOUD_SAVE_ENDPOINT', cloudSaveEndpoint);
    _requireHttps(
      errors,
      'POMARKET_PURCHASE_VERIFICATION_ENDPOINT',
      purchaseVerificationEndpoint,
    );
    if (android) {
      _requireValue(errors, 'ADMOB_REWARDED_ANDROID', androidRewardedAdUnitId);
      _requireValue(
        errors,
        'ADMOB_INTERSTITIAL_ANDROID',
        androidInterstitialAdUnitId,
      );
    }
    if (ios) {
      _requireValue(errors, 'ADMOB_REWARDED_IOS', iosRewardedAdUnitId);
      _requireValue(
        errors,
        'ADMOB_INTERSTITIAL_IOS',
        iosInterstitialAdUnitId,
      );
    }
    return List.unmodifiable(errors);
  }

  void validateCurrentPlatformRelease() {
    if (!kReleaseMode ||
        (!platform.isAndroidPlatform && !platform.isIosPlatform)) {
      return;
    }
    final errors = validationErrors(
      android: platform.isAndroidPlatform,
      ios: platform.isIosPlatform,
    );
    if (errors.isEmpty) return;
    throw StateError(
      'PoMarket release configuration is incomplete:\n- ${errors.join('\n- ')}',
    );
  }

  static void _requireValue(List<String> errors, String name, String value) {
    if (value.trim().isEmpty) errors.add('$name is missing.');
  }

  static void _requireHttps(List<String> errors, String name, String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      errors.add('$name is missing.');
      return;
    }
    final uri = Uri.tryParse(normalized);
    if (uri == null ||
        uri.scheme.toLowerCase() != 'https' ||
        uri.host.trim().isEmpty) {
      errors.add('$name must be an absolute HTTPS URL.');
    }
  }
}
