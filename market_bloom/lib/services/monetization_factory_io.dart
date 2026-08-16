import 'dart:io';

import 'app_settings.dart';
import 'cloud_save/player_identity.dart';
import 'mobile_monetization_service.dart';
import 'monetization_service.dart';
import 'purchase_verification_service.dart';

MonetizationService createPlatformMonetizationService({
  AppSettings? settings,
}) {
  if (Platform.isAndroid || Platform.isIOS) {
    const endpoint = String.fromEnvironment(
      'POMARKET_PURCHASE_VERIFICATION_ENDPOINT',
    );
    final verificationConfigured = endpoint.trim().isNotEmpty;
    final identityStore = SharedPreferencesPlayerIdentityStore();
    final verificationService = verificationConfigured
        ? RestPurchaseVerificationService(
            baseUrl: endpoint,
            identityStore: identityStore,
          )
        : const DisabledPurchaseVerificationService();
    return StoreAvailabilityGuard(
      storeEnabled: verificationConfigured,
      delegate: MobileMonetizationService(
        purchaseVerificationService: verificationService,
        consentGate: () async => settings?.adsEnabled ?? false,
      ),
    );
  }
  return PreviewMonetizationService();
}
