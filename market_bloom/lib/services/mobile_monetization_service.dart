import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import 'monetization_service.dart';

typedef PurchaseVerifier =
    Future<bool> Function(StoreProduct product, PurchaseDetails purchase);
typedef MonetizationConsentGate = Future<bool> Function();

class MobileMonetizationService implements MonetizationService {
  MobileMonetizationService({
    PurchaseVerifier? purchaseVerifier,
    MonetizationConsentGate? consentGate,
  }) : _purchaseVerifier = purchaseVerifier ?? ((_, _) async => false),
       _consentGate = consentGate ?? (() async => true);

  static const _androidTestRewardedId =
      'ca-app-pub-3940256099942544/5224354917';
  static const _iosTestRewardedId = 'ca-app-pub-3940256099942544/1712485313';
  static const _androidTestInterstitialId =
      'ca-app-pub-3940256099942544/1033173712';
  static const _iosTestInterstitialId =
      'ca-app-pub-3940256099942544/4411468910';

  static const _androidProductionRewardedId = String.fromEnvironment(
    'ADMOB_REWARDED_ANDROID',
  );
  static const _iosProductionRewardedId = String.fromEnvironment(
    'ADMOB_REWARDED_IOS',
  );
  static const _androidProductionInterstitialId = String.fromEnvironment(
    'ADMOB_INTERSTITIAL_ANDROID',
  );
  static const _iosProductionInterstitialId = String.fromEnvironment(
    'ADMOB_INTERSTITIAL_IOS',
  );

  static const Map<StoreProduct, String> _productIds = {
    StoreProduct.noAds: 'pomarket_no_ads',
    StoreProduct.coinPack: 'pomarket_coin_pack',
    StoreProduct.gemPack: 'pomarket_gem_pack',
    StoreProduct.emergencySupply: 'pomarket_emergency_supply',
    StoreProduct.starterPack: 'pomarket_starter_pack',
  };

  final PurchaseVerifier _purchaseVerifier;
  final MonetizationConsentGate _consentGate;
  final InAppPurchase _inAppPurchase = InAppPurchase.instance;
  final Map<String, ProductDetails> _products = {};
  final Map<String, Completer<StorePurchaseResult>> _pendingPurchases = {};

  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;
  RewardedAd? _rewardedAd;
  Future<void>? _rewardedLoad;
  InterstitialAd? _interstitialAd;
  Future<void>? _interstitialLoad;
  Completer<List<StorePurchaseResult>>? _restoreCompleter;
  final List<StorePurchaseResult> _restoredPurchases = <StorePurchaseResult>[];
  bool _storeAvailable = false;
  bool _disposed = false;

  String? get _rewardedId {
    if (Platform.isAndroid) {
      if (_androidProductionRewardedId.isNotEmpty) {
        return _androidProductionRewardedId;
      }
      return kDebugMode ? _androidTestRewardedId : null;
    }
    if (_iosProductionRewardedId.isNotEmpty) {
      return _iosProductionRewardedId;
    }
    return kDebugMode ? _iosTestRewardedId : null;
  }

  String? get _interstitialId {
    if (Platform.isAndroid) {
      if (_androidProductionInterstitialId.isNotEmpty) {
        return _androidProductionInterstitialId;
      }
      return kDebugMode ? _androidTestInterstitialId : null;
    }
    if (_iosProductionInterstitialId.isNotEmpty) {
      return _iosProductionInterstitialId;
    }
    return kDebugMode ? _iosTestInterstitialId : null;
  }

  @override
  bool get isPreview => Platform.isAndroid
      ? _androidProductionRewardedId.isEmpty
      : _iosProductionRewardedId.isEmpty;

  @override
  bool get storeAvailable => _storeAvailable && _products.isNotEmpty;

  @override
  bool get rewardedAdsAvailable => _rewardedAd != null;

  @override
  bool get interstitialAdsAvailable => _interstitialAd != null;

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

    if (await _consentGate() &&
        (_rewardedId != null || _interstitialId != null)) {
      await MobileAds.instance.initialize();
      await Future.wait<void>([_loadRewarded(), _loadInterstitial()]);
    }

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
    final adUnitId = _rewardedId;
    if (adUnitId == null) {
      return Future.value();
    }
    final currentLoad = _rewardedLoad;
    if (currentLoad != null) {
      return currentLoad;
    }

    final completer = Completer<void>();
    _rewardedLoad = completer.future;
    RewardedAd.load(
      adUnitId: adUnitId,
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

  Future<void> _loadInterstitial() {
    if (_interstitialAd != null || _disposed) {
      return Future.value();
    }
    final adUnitId = _interstitialId;
    if (adUnitId == null) {
      return Future.value();
    }
    final currentLoad = _interstitialLoad;
    if (currentLoad != null) {
      return currentLoad;
    }

    final completer = Completer<void>();
    _interstitialLoad = completer.future;
    InterstitialAd.load(
      adUnitId: adUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          if (_disposed) {
            ad.dispose();
          } else {
            _interstitialAd = ad;
          }
          _interstitialLoad = null;
          completer.complete();
        },
        onAdFailedToLoad: (_) {
          _interstitialLoad = null;
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
  Future<bool> showInterstitial(InterstitialPlacement placement) async {
    await _loadInterstitial();
    final ad = _interstitialAd;
    if (ad == null || _disposed) {
      return false;
    }

    _interstitialAd = null;
    final completer = Completer<bool>();
    var shown = false;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (_) {
        shown = true;
      },
      onAdDismissedFullScreenContent: (shownAd) {
        shownAd.dispose();
        if (!completer.isCompleted) {
          completer.complete(shown);
        }
        unawaited(_loadInterstitial());
      },
      onAdFailedToShowFullScreenContent: (shownAd, _) {
        shownAd.dispose();
        if (!completer.isCompleted) {
          completer.complete(false);
        }
        unawaited(_loadInterstitial());
      },
    );
    ad.show();
    return completer.future;
  }

  @override
  Future<StorePurchaseResult> purchase(StoreProduct product) async {
    if (!_storeAvailable || _disposed) {
      return StorePurchaseResult.failed(product);
    }
    final productId = _productIds[product];
    final details = _products[productId];
    if (productId == null || details == null) {
      return StorePurchaseResult.failed(product);
    }

    final existing = _pendingPurchases[productId];
    if (existing != null) {
      return existing.future;
    }

    final completer = Completer<StorePurchaseResult>();
    _pendingPurchases[productId] = completer;
    final purchaseParam = PurchaseParam(productDetails: details);
    final nonConsumable =
        product == StoreProduct.noAds || product == StoreProduct.starterPack;
    final started = nonConsumable
        ? await _inAppPurchase.buyNonConsumable(purchaseParam: purchaseParam)
        : await _inAppPurchase.buyConsumable(purchaseParam: purchaseParam);
    if (!started) {
      _completePurchaseResult(productId, StorePurchaseResult.failed(product));
    }
    return completer.future.timeout(
      const Duration(minutes: 2),
      onTimeout: () {
        _pendingPurchases.remove(productId);
        return StorePurchaseResult.failed(product);
      },
    );
  }

  Future<void> _handlePurchases(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      final product = _productForId(purchase.productID);
      if (product == null) {
        continue;
      }
      StorePurchaseResult? result;
      switch (purchase.status) {
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          final verified = await _purchaseVerifier(product, purchase);
          result = StorePurchaseResult(
            product: product,
            state: purchase.status == PurchaseStatus.restored
                ? PurchaseState.restored
                : PurchaseState.purchased,
            transactionId: purchase.purchaseID,
            verified: verified,
          );
          _completePurchaseResult(purchase.productID, result);
          if (purchase.status == PurchaseStatus.restored) {
            _restoredPurchases.add(result);
          }
          if (verified && purchase.pendingCompletePurchase) {
            await _inAppPurchase.completePurchase(purchase);
          }
        case PurchaseStatus.error:
          result = StorePurchaseResult.failed(product);
          _completePurchaseResult(purchase.productID, result);
        case PurchaseStatus.canceled:
          result = StorePurchaseResult(
            product: product,
            state: PurchaseState.cancelled,
          );
          _completePurchaseResult(purchase.productID, result);
        case PurchaseStatus.pending:
          break;
      }
    }
  }

  StoreProduct? _productForId(String productId) {
    for (final entry in _productIds.entries) {
      if (entry.value == productId) {
        return entry.key;
      }
    }
    return null;
  }

  void _completePurchaseResult(String productId, StorePurchaseResult result) {
    final completer = _pendingPurchases.remove(productId);
    if (completer != null && !completer.isCompleted) {
      completer.complete(result);
    }
  }

  void _failPendingPurchases() {
    for (final entry in _pendingPurchases.entries) {
      final product = _productForId(entry.key);
      final completer = entry.value;
      if (!completer.isCompleted) {
        completer.complete(
          StorePurchaseResult.failed(product ?? StoreProduct.noAds),
        );
      }
    }
    _pendingPurchases.clear();
  }

  @override
  Future<List<StorePurchaseResult>> restorePurchases() async {
    if (_disposed || !_storeAvailable) {
      return const <StorePurchaseResult>[];
    }
    final activeRestore = _restoreCompleter;
    if (activeRestore != null) {
      return activeRestore.future;
    }
    final completer = Completer<List<StorePurchaseResult>>();
    _restoreCompleter = completer;
    _restoredPurchases.clear();
    try {
      await _inAppPurchase.restorePurchases();
      await Future<void>.delayed(const Duration(seconds: 1));
      completer.complete(
        List<StorePurchaseResult>.unmodifiable(_restoredPurchases),
      );
    } catch (_) {
      completer.complete(const <StorePurchaseResult>[]);
    } finally {
      _restoreCompleter = null;
    }
    return completer.future;
  }

  @override
  void dispose() {
    _disposed = true;
    _rewardedAd?.dispose();
    _rewardedAd = null;
    _interstitialAd?.dispose();
    _interstitialAd = null;
    unawaited(_purchaseSubscription?.cancel());
    _failPendingPurchases();
  }
}
