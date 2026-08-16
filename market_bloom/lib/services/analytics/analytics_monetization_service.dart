import '../monetization_service.dart';
import 'analytics_event.dart';
import 'analytics_service.dart';

class AnalyticsMonetizationService
    implements MonetizationService, ConsentAwareMonetizationService {
  AnalyticsMonetizationService({
    required this.delegate,
    required this.analytics,
  });

  final MonetizationService delegate;
  final AnalyticsService analytics;

  @override
  bool get interstitialAdsAvailable => delegate.interstitialAdsAvailable;
  @override
  bool get isPreview => delegate.isPreview;
  @override
  bool get rewardedAdsAvailable => delegate.rewardedAdsAvailable;
  @override
  bool get storeAvailable => delegate.storeAvailable;
  @override
  void dispose() => delegate.dispose();
  @override
  Future<void> initialize() => delegate.initialize();
  @override
  String? priceFor(StoreProduct product) => delegate.priceFor(product);

  @override
  Future<void> refreshConsent() async {
    if (delegate is ConsentAwareMonetizationService) {
      await (delegate as ConsentAwareMonetizationService).refreshConsent();
    }
  }

  @override
  Future<StorePurchaseResult> purchase(StoreProduct product) async {
    try {
      final result = await delegate.purchase(product);
      analytics.track(
        _purchaseEvent(result.state),
        parameters: <String, Object?>{
          'product': product.name,
          'state': result.state.name,
          'verified': result.verified,
        },
        dedupeKey: result.transactionId,
      );
      return result;
    } on Object {
      analytics.track(
        AnalyticsEventName.purchaseFailed,
        parameters: <String, Object?>{
          'product': product.name,
          'reason': 'service_exception',
        },
      );
      rethrow;
    }
  }

  @override
  Future<List<StorePurchaseResult>> restorePurchases() async {
    try {
      final results = await delegate.restorePurchases();
      final verified = results.where((result) => result.canDeliver).length;
      analytics.track(
        verified > 0
            ? AnalyticsEventName.purchaseRestoreCompleted
            : AnalyticsEventName.purchaseRestoreFailed,
        parameters: <String, Object?>{
          'verified_count': verified,
          'result_count': results.length,
        },
      );
      return results;
    } on Object {
      analytics.track(
        AnalyticsEventName.purchaseRestoreFailed,
        parameters: const <String, Object?>{'reason': 'service_exception'},
      );
      rethrow;
    }
  }

  AnalyticsEventName _purchaseEvent(PurchaseState state) => switch (state) {
    PurchaseState.purchased || PurchaseState.restored =>
      AnalyticsEventName.purchaseCompleted,
    PurchaseState.pending => AnalyticsEventName.purchasePending,
    PurchaseState.cancelled => AnalyticsEventName.purchaseCancelled,
    PurchaseState.failed => AnalyticsEventName.purchaseFailed,
  };

  @override
  Future<bool> showInterstitial(InterstitialPlacement placement) =>
      delegate.showInterstitial(placement);
  @override
  Future<bool> showRewardedAd(RewardPlacement placement) =>
      delegate.showRewardedAd(placement);
}
