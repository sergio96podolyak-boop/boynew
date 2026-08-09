import 'monetization_factory_stub.dart'
    if (dart.library.io) 'monetization_factory_io.dart'
    as platform_factory;

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

  /// Attempts to restore previously purchased products.
  ///
  /// Preview builds that do not connect to a real store return an empty list
  /// without performing any side effects.
  Future<List<StorePurchaseResult>> restorePurchases();

  void dispose();
}

MonetizationService createMonetizationService() {
  return platform_factory.createPlatformMonetizationService();
}

/// Safe no-op adapter used when mobile ads and stores are unavailable.
///
/// It never simulates an earned ad reward or a successful purchase.
class PreviewMonetizationService implements MonetizationService {
  @override
  void dispose() {}

  @override
  Future<void> initialize() async {}

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
  Future<StorePurchaseResult> purchase(StoreProduct product) async {
    return StorePurchaseResult.failed(product);
  }

  @override
  Future<List<StorePurchaseResult>> restorePurchases() async {
    return const <StorePurchaseResult>[];
  }

  @override
  Future<bool> showRewardedAd(RewardPlacement placement) async => false;

  @override
  Future<bool> showInterstitial(InterstitialPlacement placement) async => false;
}
