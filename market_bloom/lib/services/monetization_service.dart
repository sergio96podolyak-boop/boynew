import 'app_settings.dart';
import 'monetization_factory_stub.dart'
    if (dart.library.io) 'monetization_factory_io.dart'
    as platform_factory;
import 'release_configuration.dart';

enum RewardPlacement {
  instantCoins,
  emergencyStock,
  doubleOfflineEarnings,
  smallGemReward,
  deliveryBoost,
  cashierBoost,
}

enum InterstitialPlacement { shiftBreak, majorLevelBreak }

enum StoreProduct { noAds, coinPack, gemPack, emergencySupply, starterPack }

enum PurchaseState { purchased, restored, pending, failed, cancelled }

class StorePurchaseResult {
  const StorePurchaseResult({
    required this.product,
    required this.state,
    this.transactionId,
    this.verified = false,
  });

  const StorePurchaseResult.failed(StoreProduct product)
    : this(product: product, state: PurchaseState.failed);

  final StoreProduct product;
  final PurchaseState state;
  final String? transactionId;
  final bool verified;

  bool get canDeliver =>
      verified &&
      transactionId != null &&
      transactionId!.isNotEmpty &&
      (state == PurchaseState.purchased || state == PurchaseState.restored);
}

abstract final class MonetizationPolicy {
  static const rewardedCooldown = Duration(minutes: 3);
  static const rewardedDailyLimit = 8;
  static const minimumInterstitialPlayTime = Duration(minutes: 8);
  static const interstitialSessionCooldown = Duration(minutes: 12);
  static const interstitialAfterRewardCooldown = Duration(minutes: 5);
  static const interstitialDailyLimit = 3;
}

abstract interface class MonetizationService {
  bool get isPreview;
  bool get storeAvailable;
  bool get rewardedAdsAvailable;
  bool get interstitialAdsAvailable;
  String? priceFor(StoreProduct product);
  Future<void> initialize();
  Future<bool> showRewardedAd(RewardPlacement placement);
  Future<bool> showInterstitial(InterstitialPlacement placement);
  Future<StorePurchaseResult> purchase(StoreProduct product);
  Future<List<StorePurchaseResult>> restorePurchases();
  void dispose();
}

abstract interface class ConsentAwareMonetizationService {
  Future<void> refreshConsent();
}

MonetizationService createMonetizationService({AppSettings? settings}) {
  ReleaseConfiguration.fromEnvironment().validateCurrentPlatformRelease();
  return platform_factory.createPlatformMonetizationService(settings: settings);
}

/// Keeps ads operational while making store purchases unavailable unless the
/// production verification service is configured.
class StoreAvailabilityGuard
    implements MonetizationService, ConsentAwareMonetizationService {
  StoreAvailabilityGuard({
    required this.delegate,
    required this.storeEnabled,
  });

  final MonetizationService delegate;
  final bool storeEnabled;

  @override
  bool get isPreview => delegate.isPreview;
  @override
  bool get storeAvailable => storeEnabled && delegate.storeAvailable;
  @override
  bool get rewardedAdsAvailable => delegate.rewardedAdsAvailable;
  @override
  bool get interstitialAdsAvailable => delegate.interstitialAdsAvailable;
  @override
  String? priceFor(StoreProduct product) =>
      storeEnabled ? delegate.priceFor(product) : null;
  @override
  Future<void> initialize() => delegate.initialize();
  @override
  Future<void> refreshConsent() async {
    final service = delegate;
    if (service is ConsentAwareMonetizationService) {
      await (service as ConsentAwareMonetizationService).refreshConsent();
    }
  }

  @override
  Future<bool> showRewardedAd(RewardPlacement placement) =>
      delegate.showRewardedAd(placement);
  @override
  Future<bool> showInterstitial(InterstitialPlacement placement) =>
      delegate.showInterstitial(placement);
  @override
  Future<StorePurchaseResult> purchase(StoreProduct product) => storeEnabled
      ? delegate.purchase(product)
      : Future.value(StorePurchaseResult.failed(product));
  @override
  Future<List<StorePurchaseResult>> restorePurchases() => storeEnabled
      ? delegate.restorePurchases()
      : Future.value(const <StorePurchaseResult>[]);
  @override
  void dispose() => delegate.dispose();
}

class PreviewMonetizationService
    implements MonetizationService, ConsentAwareMonetizationService {
  @override
  void dispose() {}
  @override
  Future<void> initialize() async {}
  @override
  Future<void> refreshConsent() async {}
  @override
  bool get isPreview => true;
  @override
  bool get storeAvailable => false;
  @override
  bool get rewardedAdsAvailable => false;
  @override
  bool get interstitialAdsAvailable => false;
  @override
  String? priceFor(StoreProduct product) => null;
  @override
  Future<StorePurchaseResult> purchase(StoreProduct product) async =>
      StorePurchaseResult.failed(product);
  @override
  Future<List<StorePurchaseResult>> restorePurchases() async =>
      const <StorePurchaseResult>[];
  @override
  Future<bool> showRewardedAd(RewardPlacement placement) async => false;
  @override
  Future<bool> showInterstitial(InterstitialPlacement placement) async => false;
}
