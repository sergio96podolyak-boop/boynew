import 'package:flutter_test/flutter_test.dart';
import 'package:pomarket/services/monetization_service.dart';
import 'package:pomarket/services/release_configuration.dart';

void main() {
  const valid = ReleaseConfiguration(
    privacyPolicyUrl: 'https://pomarket.example/privacy',
    cloudSaveEndpoint: 'https://api.pomarket.example',
    purchaseVerificationEndpoint: 'https://purchases.pomarket.example',
    androidRewardedAdUnitId: 'android-rewarded',
    iosRewardedAdUnitId: 'ios-rewarded',
    androidInterstitialAdUnitId: 'android-interstitial',
    iosInterstitialAdUnitId: 'ios-interstitial',
  );

  test('release configuration accepts complete Android and iOS values', () {
    expect(valid.validationErrors(android: true, ios: false), isEmpty);
    expect(valid.validationErrors(android: false, ios: true), isEmpty);
  });

  test('release configuration rejects missing and non-HTTPS values', () {
    const configuration = ReleaseConfiguration(
      privacyPolicyUrl: '',
      cloudSaveEndpoint: 'http://api.example.test',
      purchaseVerificationEndpoint: 'not-a-url',
      androidRewardedAdUnitId: '',
      iosRewardedAdUnitId: 'ios-rewarded',
      androidInterstitialAdUnitId: '',
      iosInterstitialAdUnitId: 'ios-interstitial',
    );
    final errors = configuration.validationErrors(android: true, ios: false);
    expect(errors, contains('POMARKET_PRIVACY_POLICY_URL is missing.'));
    expect(
      errors,
      contains('POMARKET_CLOUD_SAVE_ENDPOINT must be an absolute HTTPS URL.'),
    );
    expect(
      errors,
      contains(
        'POMARKET_PURCHASE_VERIFICATION_ENDPOINT must be an absolute HTTPS URL.',
      ),
    );
    expect(errors, contains('ADMOB_REWARDED_ANDROID is missing.'));
    expect(errors, contains('ADMOB_INTERSTITIAL_ANDROID is missing.'));
  });

  test('store guard blocks unverified store access without blocking ads', () async {
    final delegate = _FakeMonetizationService();
    final guard = StoreAvailabilityGuard(
      delegate: delegate,
      storeEnabled: false,
    );
    expect(guard.storeAvailable, isFalse);
    expect(guard.priceFor(StoreProduct.noAds), isNull);
    expect(
      (await guard.purchase(StoreProduct.noAds)).state,
      PurchaseState.failed,
    );
    expect(await guard.showRewardedAd(RewardPlacement.instantCoins), isTrue);
    await guard.refreshConsent();
    expect(delegate.refreshCalls, 1);
  });
}

class _FakeMonetizationService
    implements MonetizationService, ConsentAwareMonetizationService {
  int refreshCalls = 0;

  @override
  bool get interstitialAdsAvailable => true;
  @override
  bool get isPreview => false;
  @override
  bool get rewardedAdsAvailable => true;
  @override
  bool get storeAvailable => true;
  @override
  void dispose() {}
  @override
  Future<void> initialize() async {}
  @override
  String? priceFor(StoreProduct product) => r'$0.99';
  @override
  Future<StorePurchaseResult> purchase(StoreProduct product) async =>
      StorePurchaseResult(
        product: product,
        state: PurchaseState.purchased,
        transactionId: 'transaction',
        verified: true,
      );
  @override
  Future<void> refreshConsent() async => refreshCalls++;
  @override
  Future<List<StorePurchaseResult>> restorePurchases() async => const [];
  @override
  Future<bool> showInterstitial(InterstitialPlacement placement) async => true;
  @override
  Future<bool> showRewardedAd(RewardPlacement placement) async => true;
}
