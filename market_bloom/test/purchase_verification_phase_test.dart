import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pomarket/game/game_controller.dart';
import 'package:pomarket/services/cloud_save/player_identity.dart';
import 'package:pomarket/services/game_storage.dart';
import 'package:pomarket/services/monetization_service.dart';
import 'package:pomarket/services/purchase_verification_service.dart';

void main() {
  const request = PurchaseVerificationRequest(
    product: StoreProduct.coinPack,
    productId: 'pomarket_coin_pack',
    transactionId: 'transaction-100',
    source: 'google_play',
    serverVerificationData: 'signed-store-token',
    localVerificationData: 'local-store-token',
    restored: false,
    transactionDate: '1786701600000',
  );

  test('valid server verification binds the expected purchase fields', () async {
    late http.Request captured;
    final service = _service(
      MockClient((incoming) async {
        captured = incoming;
        return http.Response(
          jsonEncode(<String, Object>{
            'status': 'verified',
            'valid': true,
            'accountId': 'player-test-account',
            'productId': request.productId,
            'transactionId': request.transactionId,
          }),
          200,
        );
      }),
    );

    final result = await service.verify(request);
    final body = jsonDecode(captured.body) as Map<String, dynamic>;

    expect(result.status, PurchaseVerificationStatus.verified);
    expect(result.transactionId, request.transactionId);
    expect(captured.url.path, '/v1/purchases/verify');
    expect(captured.headers['idempotency-key'], contains(request.transactionId));
    expect(body['serverVerificationData'], 'signed-store-token');
    expect(body['accountId'], 'player-test-account');
    expect(body.containsKey('serverSecret'), isFalse);
  });

  test('invalid or mismatched server verification never verifies', () async {
    final invalid = _service(
      MockClient((_) async => http.Response('{"status":"invalid"}', 200)),
    );
    final mismatched = _service(
      MockClient(
        (_) async => http.Response(
          jsonEncode(<String, Object>{
            'status': 'verified',
            'valid': true,
            'accountId': 'player-test-account',
            'productId': 'different-product',
            'transactionId': request.transactionId,
          }),
          200,
        ),
      ),
    );

    expect(
      (await invalid.verify(request)).status,
      PurchaseVerificationStatus.invalid,
    );
    expect(
      (await mismatched.verify(request)).status,
      PurchaseVerificationStatus.invalid,
    );
  });

  test('duplicate and replayed verification use the same idempotency key', () async {
    final keys = <String>[];
    final service = _service(
      MockClient((incoming) async {
        keys.add(incoming.headers['idempotency-key']!);
        return http.Response(
          jsonEncode(<String, Object>{
            'status': 'verified',
            'valid': true,
            'accountId': 'player-test-account',
            'productId': request.productId,
            'transactionId': request.transactionId,
          }),
          200,
        );
      }),
    );

    expect((await service.verify(request)).isVerified, isTrue);
    expect((await service.verify(request)).isVerified, isTrue);
    expect(keys, hasLength(2));
    expect(keys.toSet(), hasLength(1));
  });

  test('pending verification is retryable and grants no authority', () async {
    final service = _service(
      MockClient((_) async => http.Response('{"status":"pending"}', 202)),
    );

    final result = await service.verify(request);

    expect(result.status, PurchaseVerificationStatus.pending);
    expect(result.isVerified, isFalse);
    expect(result.canRetry, isTrue);
  });

  test('offline verification fails closed and remains retryable', () async {
    final service = _service(
      MockClient((_) async => throw http.ClientException('offline')),
    );

    final result = await service.verify(request);

    expect(result.status, PurchaseVerificationStatus.unavailable);
    expect(result.isVerified, isFalse);
    expect(result.canRetry, isTrue);
  });

  test('restore verification sends restore context to the server', () async {
    late Map<String, dynamic> body;
    final service = _service(
      MockClient((incoming) async {
        body = jsonDecode(incoming.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode(<String, Object>{
            'status': 'verified',
            'valid': true,
            'accountId': 'player-test-account',
            'productId': 'pomarket_no_ads',
            'transactionId': 'restore-no-ads',
          }),
          200,
        );
      }),
    );
    const restoreRequest = PurchaseVerificationRequest(
      product: StoreProduct.noAds,
      productId: 'pomarket_no_ads',
      transactionId: 'restore-no-ads',
      source: 'app_store',
      serverVerificationData: 'app-store-receipt',
      localVerificationData: '',
      restored: true,
    );

    final result = await service.verify(restoreRequest);

    expect(result.isVerified, isTrue);
    expect(body['restored'], isTrue);
  });

  test('verified entitlement delivery is idempotent for replayed transactions', () async {
    final storage = MemoryGameStorage();
    final monetization = _PurchaseMonetizationService(
      purchaseResult: const StorePurchaseResult(
        product: StoreProduct.coinPack,
        state: PurchaseState.purchased,
        transactionId: 'replayed-transaction',
        verified: true,
      ),
    );
    final game = GameController(storage: storage, monetization: monetization);
    await game.initialize();
    final startingCoins = game.coins;

    expect(await game.purchaseStoreProduct(StoreProduct.coinPack), isTrue);
    expect(game.coins, startingCoins + 1000);
    expect(await game.purchaseStoreProduct(StoreProduct.coinPack), isFalse);
    expect(game.coins, startingCoins + 1000);
  });

  test('verified restore remains idempotent', () async {
    final monetization = _PurchaseMonetizationService(
      restored: const <StorePurchaseResult>[
        StorePurchaseResult(
          product: StoreProduct.noAds,
          state: PurchaseState.restored,
          transactionId: 'restore-no-ads-once',
          verified: true,
        ),
      ],
    );
    final game = GameController(
      storage: MemoryGameStorage(),
      monetization: monetization,
    );
    await game.initialize();

    expect(await game.restoreStorePurchases(), isTrue);
    expect(game.adsRemoved, isTrue);
    expect(await game.restoreStorePurchases(), isFalse);
  });

  test('legacy local purchase state without transaction history still loads', () async {
    final storage = MemoryGameStorage()
      ..data = <String, dynamic>{
        'version': 6,
        'coins': 250,
        'gems': 9,
        'adsRemoved': true,
        'dailyBonus': <String, Object>{
          'lastClaimedOn': '2026-08-14',
          'currentStreak': 1,
        },
      };
    final game = GameController(
      storage: storage,
      monetization: _PurchaseMonetizationService(),
      now: () => DateTime(2026, 8, 14, 12),
    );

    await game.initialize();

    expect(game.coins, 250);
    expect(game.gems, 9);
    expect(game.adsRemoved, isTrue);
  });
}

RestPurchaseVerificationService _service(http.Client client) =>
    RestPurchaseVerificationService(
      baseUrl: 'https://backend.example',
      client: client,
      identityStore: MemoryPlayerIdentityStore(),
    );

class _PurchaseMonetizationService implements MonetizationService {
  _PurchaseMonetizationService({
    this.purchaseResult = const StorePurchaseResult.failed(
      StoreProduct.coinPack,
    ),
    this.restored = const <StorePurchaseResult>[],
  });

  final StorePurchaseResult purchaseResult;
  final List<StorePurchaseResult> restored;

  @override
  bool get interstitialAdsAvailable => false;
  @override
  bool get isPreview => false;
  @override
  bool get rewardedAdsAvailable => false;
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
      purchaseResult;
  @override
  Future<List<StorePurchaseResult>> restorePurchases() async => restored;
  @override
  Future<bool> showInterstitial(InterstitialPlacement placement) async => false;
  @override
  Future<bool> showRewardedAd(RewardPlacement placement) async => false;
}
