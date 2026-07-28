import 'dart:async';
import 'dart:io';

import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import 'monetization_service.dart';

class MobileMonetizationService implements MonetizationService {
  static const _androidTestRewardedId =
      'ca-app-pub-3940256099942544/5224354917';
  static const _iosTestRewardedId = 'ca-app-pub-3940256099942544/1712485313';

  static const _androidProductionRewardedId = String.fromEnvironment(
    'ADMOB_REWARDED_ANDROID',
  );
  static const _iosProductionRewardedId = String.fromEnvironment(
    'ADMOB_REWARDED_IOS',
  );

  static const Map<StoreProduct, String> _productIds = {
    StoreProduct.noAds: 'pomarket_no_ads',
    StoreProduct.coinPack: 'pomarket_coin_pack',
    StoreProduct.starterPack: 'pomarket_starter_pack',
  };

  final InAppPurchase _inAppPurchase = InAppPurchase.instance;
  final Map<String, ProductDetails> _products = {};
  final Map<String, Completer<bool>> _pendingPurchases = {};

  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;
  RewardedAd? _rewardedAd;
  Future<void>? _rewardedLoad;
  bool _storeAvailable = false;
  bool _disposed = false;

  String get _rewardedId {
    if (Platform.isAndroid) {
      return _androidProductionRewardedId.isEmpty
          ? _androidTestRewardedId
          : _androidProductionRewardedId;
    }
    return _iosProductionRewardedId.isEmpty
        ? _iosTestRewardedId
        : _iosProductionRewardedId;
  }

  @override
  bool get isPreview => Platform.isAndroid
      ? _androidProductionRewardedId.isEmpty
      : _iosProductionRewardedId.isEmpty;

  @override
  bool get storeAvailable => _storeAvailable && _products.isNotEmpty;

  @override
  String? priceFor(StoreProduct product) {
    final productId = _productIds[product];
    return _products[productId]?.price;
  }

  @override
  Future<void> initialize() async {
    _purchaseSubscription = _inAppPurchase.purchaseStream.listen(
      _handlePurchases,
      onError: (_) => _failPendingPurchases(),
    );

    await MobileAds.instance.initialize();
    await _loadRewarded();

    _storeAvailable = await _inAppPurchase.isAvailable();
    if (_storeAvailable) {
      final response = await _inAppPurchase.queryProductDetails(
        _productIds.values.toSet(),
      );
      for (final product in response.productDetails) {
        _products[product.id] = product;
      }
    }
  }

  Future<void> _loadRewarded() {
    if (_rewardedAd != null || _disposed) {
      return Future.value();
    }
    final currentLoad = _rewardedLoad;
    if (currentLoad != null) {
      return currentLoad;
    }

    final completer = Completer<void>();
    _rewardedLoad = completer.future;
    RewardedAd.load(
      adUnitId: _rewardedId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          if (_disposed) {
            ad.dispose();
          } else {
            _rewardedAd = ad;
          }
          _rewardedLoad = null;
          completer.complete();
        },
        onAdFailedToLoad: (_) {
          _rewardedLoad = null;
          completer.complete();
        },
      ),
    );
    return completer.future;
  }

  @override
  Future<bool> showRewardedAd(RewardPlacement placement) async {
    await _loadRewarded();
    final ad = _rewardedAd;
    if (ad == null || _disposed) {
      return false;
    }

    _rewardedAd = null;
    final completer = Completer<bool>();
    var earnedReward = false;

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (shownAd) {
        shownAd.dispose();
        if (!completer.isCompleted) {
          completer.complete(earnedReward);
        }
        unawaited(_loadRewarded());
      },
      onAdFailedToShowFullScreenContent: (shownAd, _) {
        shownAd.dispose();
        if (!completer.isCompleted) {
          completer.complete(false);
        }
        unawaited(_loadRewarded());
      },
    );
    ad.show(
      onUserEarnedReward: (_, _) {
        earnedReward = true;
      },
    );
    return completer.future;
  }

  @override
  Future<bool> purchase(StoreProduct product) async {
    if (!_storeAvailable || _disposed) {
      return false;
    }
    final productId = _productIds[product];
    final details = _products[productId];
    if (productId == null || details == null) {
      return false;
    }

    final existing = _pendingPurchases[productId];
    if (existing != null) {
      return existing.future;
    }

    final completer = Completer<bool>();
    _pendingPurchases[productId] = completer;
    final purchaseParam = PurchaseParam(productDetails: details);
    final started = product == StoreProduct.noAds
        ? await _inAppPurchase.buyNonConsumable(purchaseParam: purchaseParam)
        : await _inAppPurchase.buyConsumable(purchaseParam: purchaseParam);
    if (!started) {
      _completePurchaseResult(productId, false);
    }
    return completer.future.timeout(
      const Duration(minutes: 2),
      onTimeout: () {
        _pendingPurchases.remove(productId);
        return false;
      },
    );
  }

  Future<void> _handlePurchases(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      switch (purchase.status) {
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          // Before production launch, replace this presence check with
          // server-side receipt validation and idempotent product delivery.
          final hasReceipt =
              purchase.verificationData.serverVerificationData.isNotEmpty;
          _completePurchaseResult(purchase.productID, hasReceipt);
        case PurchaseStatus.error:
        case PurchaseStatus.canceled:
          _completePurchaseResult(purchase.productID, false);
        case PurchaseStatus.pending:
          break;
      }
      if (purchase.pendingCompletePurchase) {
        await _inAppPurchase.completePurchase(purchase);
      }
    }
  }

  void _completePurchaseResult(String productId, bool success) {
    final completer = _pendingPurchases.remove(productId);
    if (completer != null && !completer.isCompleted) {
      completer.complete(success);
    }
  }

  void _failPendingPurchases() {
    for (final completer in _pendingPurchases.values) {
      if (!completer.isCompleted) {
        completer.complete(false);
      }
    }
    _pendingPurchases.clear();
  }

  @override
  void dispose() {
    _disposed = true;
    _rewardedAd?.dispose();
    _rewardedAd = null;
    unawaited(_purchaseSubscription?.cancel());
    _failPendingPurchases();
  }
}
