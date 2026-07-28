import 'monetization_factory_stub.dart'
    if (dart.library.io) 'monetization_factory_io.dart'
    as platform_factory;

enum RewardPlacement { instantCoins, doubleOfflineEarnings }

enum StoreProduct { noAds, coinPack, starterPack }

abstract interface class MonetizationService {
  bool get isPreview;

  bool get storeAvailable;

  String? priceFor(StoreProduct product);

  Future<void> initialize();

  Future<bool> showRewardedAd(RewardPlacement placement);

  Future<bool> purchase(StoreProduct product);

  void dispose();
}

MonetizationService createMonetizationService() {
  return platform_factory.createPlatformMonetizationService();
}

/// The game loop is fully playable before store credentials exist.
///
/// In preview builds this service grants rewarded-ad bonuses after a short
/// simulated break. Production builds replace it with an AdMob/IAP-backed
/// implementation after app IDs and store products are created.
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
  String? priceFor(StoreProduct product) => null;

  @override
  Future<bool> purchase(StoreProduct product) async => false;

  @override
  Future<bool> showRewardedAd(RewardPlacement placement) async {
    await Future<void>.delayed(const Duration(milliseconds: 700));
    return true;
  }
}
