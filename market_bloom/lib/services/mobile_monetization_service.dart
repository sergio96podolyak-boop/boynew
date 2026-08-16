import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import 'monetization_service.dart';
import 'purchase_verification_service.dart';

typedef MonetizationConsentGate = Future<bool> Function();

class MobileMonetizationService
    implements MonetizationService, ConsentAwareMonetizationService {
  MobileMonetizationService({
    PurchaseVerificationService? purchaseVerificationService,
    MonetizationConsentGate? consentGate,
  }) : _purchaseVerificationService =
           purchaseVerificationService ??
           const DisabledPurchaseVerificationService(),
       _consentGate = consentGate ?? (() async => false);

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

  final PurchaseVerificationService _purchaseVerificationService;
  final MonetizationConsentGate _consentGate;
  final InAppPurchase _inAppPurchase = InAppPurchase.instance;
  final Map<String, ProductDetails> _products = {};
  final Map<String, Completer<StorePurchaseResult>> _pendingPurchases = {};
  final List<StorePurchaseResult> _restoredPurchases = <StorePurchaseResult>[];

  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;
  RewardedAd? _rewardedAd;
  Future<void>? _rewardedLoad;
  InterstitialAd? _interstitialAd;
  Future<void>? _interstitialLoad;
  Completer<List<StorePurchaseResult>>? _restoreCompleter;
  bool _storeAvailable = false;
  bool _initialized = false;
  bool _adsInitialized = false;
  bool _disposed = false;

  String? get _rewardedId {
    if (Platform.isAndroid) {
      if (_androidProductionRewardedId.isNotEmpty) {
        return _androidProductionRewardedId;
      }
      return kDebugMode ? _androidTestRewardedId : null;
    }
    if (_iosProductionRewardedId.isNotEmpty) return _iosProductionRewardedId;
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
  String? priceFor(StoreProduct product) =>
      _products[_productIds[product]]?.price;

  @override
  Future<void> initialize() async {
    if (_disposed) return;
    if (!_initialized) {
      _purchaseSubscription = _inAppPurchase.purchaseStream.listen(
        _handlePurchases,
        onError: (_) => _failPendingPurchases(),
      );
      _storeAvailable = await _inAppPurchase.isAvailable();
      if (_storeAvailable) {
        final response = await _inAppPurchase.queryProductDetails(
          _productIds.values.toSet(),
        );
        for (final product in response.productDetails) {
          _products[product.id] = product;
        }
      }
      _initialized = true;
    }
    await refreshConsent();
  }

  @override
  Future<void> refreshConsent() async {
    if (_disposed) return;
    var allowed = false;
    try {
      allowed = await _consentGate();
    } on Object {
      allowed = false;
    }
    if (!allowed) {
      _rewardedAd?.dispose();
      _rewardedAd = null;
      _interstitialAd?.dispose();
      _interstitialAd = null;
      return;
    }
    if (!_adsInitialized && (_rewardedId != null || _interstitialId != null)) {
      try {
        await MobileAds.instance.initialize();
        _adsInitialized = true;
      } on Object {
        return;
      }
    }
    await Future.wait<void>([_loadRewarded(), _loadInterstitial()]);
  }

  Future<void> _loadRewarded() {
    if (_rewardedAd != null || _disposed) return Future.value();
    final id = _rewardedId;
    if (id == null) return Future.value();
    final active = _rewardedLoad;
    if (active != null) return active;
    final completer = Completer<void>();
    _rewardedLoad = completer.future;
    RewardedAd.load(
      adUnitId: id,
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
    if (_interstitialAd != null || _disposed) return Future.value();
    final id = _interstitialId;
    if (id == null) return Future.value();
    final active = _interstitialLoad;
    if (active != null) return active;
    final completer = Completer<void>();
    _interstitialLoad = completer.future;
    InterstitialAd.load(
      adUnitId: id,
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
    if (!await _consentGate()) return false;
    await _loadRewarded();
    final ad = _rewardedAd;
    if (ad == null || _disposed) return false;
    _rewardedAd = null;
    final completer = Completer<bool>();
    var earned = false;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (shown) {
        shown.dispose();
        if (!completer.isCompleted) completer.complete(earned);
        unawaited(_loadRewarded());
      },
      onAdFailedToShowFullScreenContent: (shown, _) {
        shown.dispose();
        if (!completer.isCompleted) completer.complete(false);
      },
    );
    ad.show(onUserEarnedReward: (_, _) => earned = true);
    return completer.future;
  }

  @override
  Future<bool> showInterstitial(InterstitialPlacement placement) async {
    if (!await _consentGate()) return false;
    await _loadInterstitial();
    final ad = _interstitialAd;
    if (ad == null || _disposed) return false;
    _interstitialAd = null;
    final completer = Completer<bool>();
    var shown = false;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (_) => shown = true,
      onAdDismissedFullScreenContent: (value) {
        value.dispose();
        if (!completer.isCompleted) completer.complete(shown);
        unawaited(_loadInterstitial());
      },
      onAdFailedToShowFullScreenContent: (value, _) {
        value.dispose();
        if (!completer.isCompleted) completer.complete(false);
      },
    );
    ad.show();
    return completer.future;
  }

  @override
  Future<StorePurchaseResult> purchase(StoreProduct product) async {
    if (!_storeAvailable || _disposed) return StorePurchaseResult.failed(product);
    final productId = _productIds[product];
    final details = _products[productId];
    if (productId == null || details == null) {
      return StorePurchaseResult.failed(product);
    }
    final existing = _pendingPurchases[productId];
    if (existing != null) return existing.future;
    final completer = Completer<StorePurchaseResult>();
    _pendingPurchases[productId] = completer;
    final param = PurchaseParam(productDetails: details);
    final nonConsumable =
        product == StoreProduct.noAds || product == StoreProduct.starterPack;
    final started = nonConsumable
        ? await _inAppPurchase.buyNonConsumable(purchaseParam: param)
        : await _inAppPurchase.buyConsumable(purchaseParam: param);
    if (!started) {
      _completePurchaseResult(productId, StorePurchaseResult.failed(product));
    }
    return completer.future.timeout(
      const Duration(minutes: 2),
      onTimeout: () {
        _pendingPurchases.remove(productId);
        return StorePurchaseResult(
          product: product,
          state: PurchaseState.pending,
        );
      },
    );
  }

  Future<void> _handlePurchases(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      final product = _productForId(purchase.productID);
      if (product == null) continue;
      switch (purchase.status) {
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          final requested =
              _pendingPurchases.containsKey(purchase.productID) ||
              _restoreCompleter != null;
          final verification = await _purchaseVerificationService.verify(
            PurchaseVerificationRequest(
              product: product,
              productId: purchase.productID,
              transactionId: purchase.purchaseID ?? '',
              source: purchase.verificationData.source,
              serverVerificationData:
                  purchase.verificationData.serverVerificationData,
              localVerificationData:
                  purchase.verificationData.localVerificationData,
              restored: purchase.status == PurchaseStatus.restored,
              transactionDate: purchase.transactionDate,
            ),
          );
          final verified = verification.isVerified;
          final result = StorePurchaseResult(
            product: product,
            state: verified
                ? purchase.status == PurchaseStatus.restored
                      ? PurchaseState.restored
                      : PurchaseState.purchased
                : verification.canRetry
                ? PurchaseState.pending
                : PurchaseState.failed,
            transactionId: verification.transactionId ?? purchase.purchaseID,
            verified: verified,
          );
          _completePurchaseResult(purchase.productID, result);
          if (purchase.status == PurchaseStatus.restored) {
            _restoredPurchases.add(result);
          }
          if (verified && requested && purchase.pendingCompletePurchase) {
            await _inAppPurchase.completePurchase(purchase);
          }
        case PurchaseStatus.error:
          _completePurchaseResult(
            purchase.productID,
            StorePurchaseResult.failed(product),
          );
        case PurchaseStatus.canceled:
          _completePurchaseResult(
            purchase.productID,
            StorePurchaseResult(
              product: product,
              state: PurchaseState.cancelled,
            ),
          );
        case PurchaseStatus.pending:
          break;
      }
    }
  }

  StoreProduct? _productForId(String id) {
    for (final entry in _productIds.entries) {
      if (entry.value == id) return entry.key;
    }
    return null;
  }

  void _completePurchaseResult(String id, StorePurchaseResult result) {
    final completer = _pendingPurchases.remove(id);
    if (completer != null && !completer.isCompleted) completer.complete(result);
  }

  void _failPendingPurchases() {
    for (final entry in _pendingPurchases.entries) {
      if (!entry.value.isCompleted) {
        entry.value.complete(
          StorePurchaseResult(
            product: _productForId(entry.key) ?? StoreProduct.noAds,
            state: PurchaseState.pending,
          ),
        );
      }
    }
    _pendingPurchases.clear();
  }

  @override
  Future<List<StorePurchaseResult>> restorePurchases() async {
    if (_disposed || !_storeAvailable) return const <StorePurchaseResult>[];
    final active = _restoreCompleter;
    if (active != null) return active.future;
    final completer = Completer<List<StorePurchaseResult>>();
    _restoreCompleter = completer;
    _restoredPurchases.clear();
    try {
      await _inAppPurchase.restorePurchases();
      await Future<void>.delayed(const Duration(seconds: 1));
      completer.complete(List.unmodifiable(_restoredPurchases));
    } on Object {
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
    _interstitialAd?.dispose();
    _rewardedAd = null;
    _interstitialAd = null;
    unawaited(_purchaseSubscription?.cancel());
    _failPendingPurchases();
  }
}
