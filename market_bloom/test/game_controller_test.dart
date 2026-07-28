import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomarket/game/game_controller.dart';
import 'package:pomarket/game/game_models.dart';
import 'package:pomarket/services/game_storage.dart';
import 'package:pomarket/services/monetization_service.dart';

void main() {
  late MemoryGameStorage storage;
  late GameController game;

  setUp(() async {
    storage = MemoryGameStorage();
    game = GameController(
      storage: storage,
      monetization: PreviewMonetizationService(),
      random: Random(4),
    );
    await game.initialize();
  });

  test('player can collect stock and fill the shelf', () {
    game.debugSetPlayerPosition(GameController.stockZone);
    _advance(game, 2.2);

    expect(game.carried, game.bagCapacity);

    game.debugSetPlayerPosition(GameController.shelfZone);
    _advance(game, 2);

    expect(game.carried, 0);
    expect(game.shelfStock, game.bagCapacity);
    expect(game.stockedTotal, game.bagCapacity);
  });

  test('stocked shelves create sales and coins when player is at checkout', () {
    game.debugSetPlayerPosition(GameController.stockZone);
    _advance(game, 2.2);
    game.debugSetPlayerPosition(GameController.shelfZone);
    _advance(game, 2);
    game.debugSetPlayerPosition(GameController.checkoutZone);

    final startingCoins = game.coins;
    _advance(game, 24);

    expect(game.totalSales, greaterThan(0));
    expect(game.coins, greaterThan(startingCoins));
  });

  test(
    'customer payment requires player presence at checkout and pauses when player leaves',
    () {
      game.debugSetPlayerPosition(GameController.stockZone);
      _advance(game, 2.2);
      game.debugSetPlayerPosition(GameController.shelfZone);
      _advance(game, 2);

      // Player moves away from checkout
      game.debugSetPlayerPosition(const Offset(0.5, 0.72));

      // Advance time for customers to shop and reach checkout
      _advance(game, 5);

      // No customer can begin paying while the player is away
      expect(
        game.customers.where((c) => c.phase == CustomerPhase.paying),
        isEmpty,
      );

      final checkoutCustomer = game.customers.firstWhere(
        (c) => c.phase == CustomerPhase.checkout,
      );
      final initialPhaseTime = checkoutCustomer.phaseTime;

      // 1. No payment while player is away
      _advance(game, 3);
      expect(game.totalSales, 0);
      expect(checkoutCustomer.phaseTime, initialPhaseTime);

      // 2. Payment begins while player is at checkout
      game.debugSetPlayerPosition(GameController.checkoutZone);
      _advance(game, 0.2);
      expect(checkoutCustomer.phase, CustomerPhase.paying);
      final pausedPhaseTime = checkoutCustomer.phaseTime;

      // 3. Payment pauses when player leaves
      game.debugSetPlayerPosition(const Offset(0.5, 0.72));
      _advance(game, 3);
      expect(game.totalSales, 0);
      expect(checkoutCustomer.phaseTime, pausedPhaseTime);

      // 4. Payment resumes and completes when player returns
      game.debugSetPlayerPosition(GameController.checkoutZone);
      _advance(game, 2);
      expect(game.totalSales, greaterThan(0));
    },
  );

  test(
    'recovering a paying customer that is missing from the queue lets payment progress',
    () {
      final customer = MarketCustomer(
        id: 201,
        position: const Offset(0.5, 0.5),
        color: const Color(0xFF000000),
      );

      game.customers.clear();
      game.customers.add(customer);

      game.debugSetPlayerPosition(GameController.checkoutZone);
      customer.phase = CustomerPhase.paying;
      customer.position =
          GameController.checkoutZone + const Offset(-0.03, 0.10);

      _advance(game, 1.2);

      expect(customer.phase, CustomerPhase.leaving);
    },
  );

  test('front customer waits for the player before entering paying phase', () {
    final customerA = MarketCustomer(
      id: 101,
      position: const Offset(0.5, 0.5),
      color: const Color(0xFF000000),
    );
    final customerB = MarketCustomer(
      id: 102,
      position: const Offset(0.5, 0.5),
      color: const Color(0xFF111111),
    );

    game.customers.clear();
    game.customers.add(customerA);
    game.customers.add(customerB);

    game.debugSetPlayerPosition(const Offset(0.5, 0.72));
    customerA.phase = CustomerPhase.checkout;
    customerA.position =
        GameController.checkoutZone + const Offset(-0.03, 0.10);
    customerB.phase = CustomerPhase.checkout;
    customerB.position =
        GameController.checkoutZone + const Offset(-0.03, 0.175);

    game.tick(0.05);

    expect(customerA.phase, CustomerPhase.checkout);
    expect(customerB.phase, CustomerPhase.checkout);
    expect(
      game.customers.where((c) => c.phase == CustomerPhase.paying).length,
      0,
    );
  });

  test(
    'customers form a queue at checkout, only front customer pays, and next customer advances',
    () {
      game.debugSetPlayerPosition(GameController.stockZone);
      _advance(game, 2.2);
      game.debugSetPlayerPosition(GameController.shelfZone);
      _advance(game, 2);

      // Player stays away from checkout while multiple customers shop and queue
      game.debugSetPlayerPosition(const Offset(0.5, 0.72));
      _advance(game, 6);

      final queued = game.customers
          .where(
            (c) =>
                c.phase == CustomerPhase.checkout ||
                c.phase == CustomerPhase.paying,
          )
          .toList();

      expect(queued.length, greaterThanOrEqualTo(2));

      // 1. Multiple customers do not occupy the same checkout position
      final firstPos = queued[0].position;
      final secondPos = queued[1].position;
      expect(firstPos, isNot(equals(secondPos)));

      // 2. No customer can begin paying while the player is away
      expect(
        game.customers.where((c) => c.phase == CustomerPhase.paying).length,
        0,
      );

      // 3. Payment begins when the player is at checkout
      game.debugSetPlayerPosition(GameController.checkoutZone);
      _advance(game, 0.2);

      expect(queued[0].phase, CustomerPhase.paying);
      expect(queued[1].phase, CustomerPhase.checkout);
      expect(
        game.customers.where((c) => c.phase == CustomerPhase.paying).length,
        1,
      );

      // 4. The next customer advances after the first payment completes
      _advance(game, 1.2);
      expect(game.totalSales, 1);

      _advance(game, 0.5);
      final nextFirst = game.customers.firstWhere(
        (c) =>
            c.phase == CustomerPhase.checkout ||
            c.phase == CustomerPhase.paying,
      );
      expect(nextFirst.id, queued[1].id);
      expect(nextFirst.phase, CustomerPhase.paying);
      expect(
        game.customers.where((c) => c.phase == CustomerPhase.paying).length,
        1,
      );
    },
  );

  test(
    'checkout queue preserves arrival order regardless of list position and enforces single paying customer',
    () {
      final customerA = MarketCustomer(
        id: 101,
        position: const Offset(0.5, 0.5),
        color: const Color(0xFF000000),
      );
      final customerB = MarketCustomer(
        id: 102,
        position: const Offset(0.5, 0.5),
        color: const Color(0xFF111111),
      );

      // Customer A is first in customers list, Customer B is second
      game.customers.clear();
      game.customers.add(customerA);
      game.customers.add(customerB);

      // 1. Customer B reaches checkout first
      customerB.phase = CustomerPhase.checkout;
      customerB.position =
          GameController.checkoutZone + const Offset(-0.03, 0.10);
      game.tick(0.05);

      // 2. Customer A reaches checkout second
      customerA.phase = CustomerPhase.checkout;
      customerA.position =
          GameController.checkoutZone + const Offset(-0.03, 0.175);
      game.tick(0.05);

      // 3. First arrival (Customer B) remains at front and waits until the player is at checkout
      expect(customerB.phase, CustomerPhase.checkout);
      expect(customerA.phase, CustomerPhase.checkout);
      expect(
        game.customers.where((c) => c.phase == CustomerPhase.paying).length,
        0,
      );

      // 4. Later arrival (Customer A) cannot begin paying first
      game.debugSetPlayerPosition(const Offset(0.5, 0.72));
      _advance(game, 2);
      expect(game.totalSales, 0);
      expect(customerA.phase, CustomerPhase.checkout);

      // 5. Once the player is at checkout, the first arrival begins paying and the second remains queued
      game.debugSetPlayerPosition(GameController.checkoutZone);
      _advance(game, 0.2);
      expect(customerB.phase, CustomerPhase.paying);
      expect(customerA.phase, CustomerPhase.checkout);
      expect(
        game.customers.where((c) => c.phase == CustomerPhase.paying).length,
        1,
      );

      // 6. After first payment completes, second customer advances to front
      _advance(game, 1.2);
      expect(game.totalSales, 1);
      expect(customerB.phase, CustomerPhase.leaving);

      _advance(game, 0.5);
      expect(customerA.phase, CustomerPhase.paying);
      expect(
        game.customers.where((c) => c.phase == CustomerPhase.paying).length,
        1,
      );
    },
  );

  test('upgrades spend coins and persist', () async {
    game.coins = 500;
    expect(game.buyUpgrade(UpgradeType.bag), isTrue);
    expect(game.bagLevel, 2);
    await game.save();

    final restored = GameController(
      storage: storage,
      monetization: PreviewMonetizationService(),
      random: Random(4),
    );
    await restored.initialize();

    expect(restored.bagLevel, 2);
    expect(restored.coins, lessThan(500));
  });

  test('preview monetization is a safe no-op', () async {
    final before = game.coins;

    expect(await game.claimInstantAdReward(), isFalse);
    expect(game.coins, before);
  });

  test(
    'store price model preserves the official localized price string',
    () async {
      final service = _FakeMonetizationService();
      final pricedGame = GameController(
        storage: MemoryGameStorage(),
        monetization: service,
      );
      await pricedGame.initialize();

      expect(pricedGame.storePrice(StoreProduct.coinPack), '₪3.90');
      expect(game.storePrice(StoreProduct.coinPack), isNull);
    },
  );

  test(
    'reward is granted once, respects cooldown, and not on dismissal',
    () async {
      var now = DateTime(2026, 7, 28, 12);
      final monetization = _FakeMonetizationService();
      final rewardGame = GameController(
        storage: MemoryGameStorage(),
        monetization: monetization,
        now: () => now,
      );
      await rewardGame.initialize();
      final reward = rewardGame.instantAdReward;
      final before = rewardGame.coins;

      expect(await rewardGame.claimInstantAdReward(), isTrue);
      expect(rewardGame.coins, before + reward);
      expect(await rewardGame.claimInstantAdReward(), isFalse);
      expect(monetization.rewardedCalls, 1);

      now = now.add(MonetizationPolicy.rewardedCooldown);
      monetization.nextRewardEarned = false;
      final afterEarnedReward = rewardGame.coins;
      expect(await rewardGame.claimInstantAdReward(), isFalse);
      expect(rewardGame.coins, afterEarnedReward);
      expect(monetization.rewardedCalls, 2);
    },
  );

  test(
    'rewarded daily limit persists and prevents additional ad requests',
    () async {
      var now = DateTime(2026, 7, 28, 8);
      final rewardStorage = MemoryGameStorage();
      final monetization = _FakeMonetizationService();
      final rewardGame = GameController(
        storage: rewardStorage,
        monetization: monetization,
        now: () => now,
      );
      await rewardGame.initialize();

      for (
        var claim = 0;
        claim < MonetizationPolicy.rewardedDailyLimit;
        claim++
      ) {
        expect(await rewardGame.claimInstantAdReward(), isTrue);
        now = now.add(MonetizationPolicy.rewardedCooldown);
      }
      expect(await rewardGame.claimInstantAdReward(), isFalse);
      expect(monetization.rewardedCalls, MonetizationPolicy.rewardedDailyLimit);
      await rewardGame.save();

      final restartedMonetization = _FakeMonetizationService();
      final restarted = GameController(
        storage: rewardStorage,
        monetization: restartedMonetization,
        now: () => now,
      );
      await restarted.initialize();

      expect(await restarted.claimInstantAdReward(), isFalse);
      expect(restartedMonetization.rewardedCalls, 0);
    },
  );

  test('verified purchase delivery is idempotent across restart', () async {
    final purchaseStorage = MemoryGameStorage();
    final monetization = _FakeMonetizationService()
      ..nextPurchase = const StorePurchaseResult(
        product: StoreProduct.coinPack,
        state: PurchaseState.purchased,
        transactionId: 'transaction-1',
        verified: true,
      );
    final purchaseGame = GameController(
      storage: purchaseStorage,
      monetization: monetization,
    );
    await purchaseGame.initialize();
    final before = purchaseGame.coins;

    expect(
      await purchaseGame.purchaseStoreProduct(StoreProduct.coinPack),
      isTrue,
    );
    expect(purchaseGame.coins, before + 1000);
    expect(
      await purchaseGame.purchaseStoreProduct(StoreProduct.coinPack),
      isFalse,
    );
    expect(purchaseGame.coins, before + 1000);
    await purchaseGame.save();

    final restartedMonetization = _FakeMonetizationService()
      ..nextPurchase = monetization.nextPurchase;
    final restarted = GameController(
      storage: purchaseStorage,
      monetization: restartedMonetization,
    );
    await restarted.initialize();
    final restartedBalance = restarted.coins;

    expect(
      await restarted.purchaseStoreProduct(StoreProduct.coinPack),
      isFalse,
    );
    expect(restarted.coins, restartedBalance);
    expect(restarted.storePrice(StoreProduct.coinPack), '₪3.90');
  });

  test('unverified purchase never grants content', () async {
    final monetization = _FakeMonetizationService()
      ..nextPurchase = const StorePurchaseResult(
        product: StoreProduct.gemPack,
        state: PurchaseState.purchased,
        transactionId: 'unverified-1',
      );
    final purchaseGame = GameController(
      storage: MemoryGameStorage(),
      monetization: monetization,
    );
    await purchaseGame.initialize();
    final before = purchaseGame.gems;

    expect(
      await purchaseGame.purchaseStoreProduct(StoreProduct.gemPack),
      isFalse,
    );
    expect(purchaseGame.gems, before);
  });

  test('cancelled purchase reports cancellation and grants nothing', () async {
    final service = _FakeMonetizationService()
      ..nextPurchase = const StorePurchaseResult(
        product: StoreProduct.coinPack,
        state: PurchaseState.cancelled,
      );
    final purchaseGame = GameController(
      storage: MemoryGameStorage(),
      monetization: service,
    );
    await purchaseGame.initialize();
    final before = purchaseGame.coins;

    expect(
      await purchaseGame.purchaseStoreProduct(StoreProduct.coinPack),
      isFalse,
    );
    expect(purchaseGame.lastPurchaseState, PurchaseState.cancelled);
    expect(purchaseGame.coins, before);
  });

  test('restore delivers a verified non-consumable once', () async {
    final monetization = _FakeMonetizationService()
      ..restoredPurchases = const <StorePurchaseResult>[
        StorePurchaseResult(
          product: StoreProduct.noAds,
          state: PurchaseState.restored,
          transactionId: 'restored-remove-ads',
          verified: true,
        ),
      ];
    final restoreGame = GameController(
      storage: MemoryGameStorage(),
      monetization: monetization,
    );
    await restoreGame.initialize();

    expect(await restoreGame.restoreStorePurchases(), isTrue);
    expect(restoreGame.adsRemoved, isTrue);
    expect(await restoreGame.restoreStorePurchases(), isFalse);
  });

  test(
    'interstitials only show at eligible natural breaks and Remove Ads blocks them',
    () async {
      var now = DateTime(2026, 7, 28, 12);
      final monetization = _FakeMonetizationService();
      final adGame = GameController(
        storage: MemoryGameStorage(),
        monetization: monetization,
        now: () => now,
      );
      await adGame.initialize();

      expect(
        await adGame.maybeShowInterstitial(InterstitialPlacement.shiftBreak),
        isFalse,
      );
      adGame.totalPlaySeconds = MonetizationPolicy
          .minimumInterstitialPlayTime
          .inSeconds
          .toDouble();
      expect(
        await adGame.maybeShowInterstitial(InterstitialPlacement.shiftBreak),
        isTrue,
      );
      expect(
        await adGame.maybeShowInterstitial(InterstitialPlacement.shiftBreak),
        isFalse,
      );

      now = now.add(MonetizationPolicy.interstitialSessionCooldown);
      monetization.nextPurchase = const StorePurchaseResult(
        product: StoreProduct.noAds,
        state: PurchaseState.purchased,
        transactionId: 'remove-ads-1',
        verified: true,
      );
      expect(await adGame.purchaseStoreProduct(StoreProduct.noAds), isTrue);
      expect(
        await adGame.maybeShowInterstitial(
          InterstitialPlacement.majorLevelBreak,
        ),
        isFalse,
      );
      expect(monetization.interstitialCalls, 1);
    },
  );

  test('hireable staff consume coins and persist their levels', () async {
    game.debugSetProgress(sales: 16);
    game.coins = 600;

    expect(game.hireStaff(StaffRole.cashier), isTrue);
    expect(game.staffLevel(StaffRole.cashier), 1);
    expect(game.coins, lessThan(600));

    await game.save();

    final restored = GameController(
      storage: storage,
      monetization: PreviewMonetizationService(),
      random: Random(4),
    );
    await restored.initialize();

    expect(restored.staffLevel(StaffRole.cashier), 1);
  });

  test(
    'field-level save migration preserves valid progress and reconciles corruption',
    () async {
      final migrationStorage = MemoryGameStorage()
        ..data = <String, dynamic>{
          'balance': 240,
          'premiumCurrency': 7,
          'sales': 16,
          'bagLevel': 'broken',
          'shelfLevel': 2,
          'stock': 999,
          'checkoutSpeedLevel': 4,
          'cashierHired': true,
          'cashierLevel': 2,
          'inventory': <String, Object>{'General': -5, 'Produce': 9999},
          'departments': <Object>[
            <String, Object>{'type': 'bakery', 'level': -2, 'unlocked': false},
            <String, Object>{'type': 'bakery', 'level': 2, 'unlocked': true},
            <String, Object>{'type': 'unknown', 'unlocked': true},
          ],
          'dailyBonus': <String, Object>{
            'currentStreak': 2,
            'lastClaimedOn': '2026-07-28',
          },
        };
      final restored = GameController(
        storage: migrationStorage,
        monetization: PreviewMonetizationService(),
        now: () => DateTime(2026, 7, 28, 12),
      );

      await restored.initialize();

      expect(restored.coins, 240);
      expect(restored.gems, 7);
      expect(restored.bagLevel, 1);
      expect(restored.shelfLevel, 2);
      expect(restored.shelfStock, restored.shelfCapacity);
      expect(restored.checkoutLevel, 4);
      expect(restored.bakeryUnlocked, isTrue);
      expect(restored.isStaffHired(StaffRole.cashier), isTrue);
      expect(restored.staffLevel(StaffRole.cashier), 2);
      expect(
        restored.staffMembers.where(
          (member) => member.role == StaffRole.cashier,
        ),
        hasLength(1),
      );
      expect(restored.inventoryFor('General'), 0);
      expect(
        restored.totalStoredInventory,
        lessThanOrEqualTo(restored.storageCapacity),
      );
    },
  );

  test(
    'Bakery stays locked at level 2 and unlocks exactly once at level 3',
    () {
      game.debugSetProgress(sales: 8);
      expect(game.storeLevel, 2);
      expect(game.bakeryUnlocked, isFalse);
      expect(game.takeDepartmentUnlock(), isNull);

      game.debugSetProgress(sales: 16);
      expect(game.storeLevel, 3);
      expect(game.bakeryUnlocked, isTrue);
      expect(game.bakeryReadyStock, GameBalance.bakeryStarterStock);
      expect(game.takeDepartmentUnlock(), DepartmentType.bakery);
      expect(game.takeDepartmentUnlock(), isNull);

      game.debugSetProgress(sales: 24);
      expect(game.storeLevel, 4);
      expect(game.bakeryUnlocked, isTrue);
      expect(game.bakeryReadyStock, GameBalance.bakeryStarterStock);
      expect(game.takeDepartmentUnlock(), isNull);
    },
  );

  test('Bakery produces pastries and lets the player collect them', () {
    game.debugSetProgress(sales: 16);

    expect(game.bakeryReadyStock, GameBalance.bakeryStarterStock);

    game.debugSetPlayerPosition(GameController.bakeryZone);
    _advance(
      game,
      GameBalance.bakeryCollectionSeconds * GameBalance.bakeryStarterStock +
          0.2,
    );

    expect(game.carried, GameBalance.bakeryStarterStock);
    expect(game.bakeryReadyStock, 0);

    game.debugSetPlayerPosition(const Offset(0.5, 0.72));
    _advance(
      game,
      GameBalance.bakeryProductionInterval.inMilliseconds / 1000 + 0.1,
    );

    expect(game.bakeryReadyStock, 1);
  });

  test('old level-3 save unlocks Bakery and restart preserves it', () async {
    final bakeryStorage = MemoryGameStorage()
      ..data = <String, dynamic>{
        'coins': 120,
        'totalSales': 16,
        'departments': <Object>[
          <String, Object>{'type': 'bakery', 'level': 0, 'unlocked': false},
        ],
        'dailyBonus': <String, Object>{'lastClaimedOn': '2026-07-28'},
      };
    final restored = GameController(
      storage: bakeryStorage,
      monetization: PreviewMonetizationService(),
      now: () => DateTime(2026, 7, 28, 12),
    );
    await restored.initialize();

    expect(restored.storeLevel, 3);
    expect(restored.bakeryUnlocked, isTrue);
    expect(restored.bakeryReadyStock, GameBalance.bakeryStarterStock);
    expect(restored.takeDepartmentUnlock(), isNull);
    restored.debugSetPlayerPosition(GameController.bakeryZone);
    _advance(restored, GameBalance.bakeryCollectionSeconds + 0.1);
    expect(restored.bakeryReadyStock, GameBalance.bakeryStarterStock - 1);
    await restored.save();

    final restarted = GameController(
      storage: bakeryStorage,
      monetization: PreviewMonetizationService(),
      now: () => DateTime(2026, 7, 28, 13),
    );
    await restarted.initialize();

    expect(restarted.bakeryUnlocked, isTrue);
    expect(restarted.bakeryReadyStock, GameBalance.bakeryStarterStock - 1);
    expect(restarted.takeDepartmentUnlock(), isNull);
  });

  test(
    'checkout upgrade never hires a cashier and changes real service speed',
    () {
      game.debugSetProgress(sales: 16);
      game.coins = 1000;

      expect(game.buyUpgrade(UpgradeType.checkout), isFalse);
      expect(game.isStaffHired(StaffRole.cashier), isFalse);

      expect(game.hireStaff(StaffRole.cashier), isTrue);
      final before = game.cashierCheckoutSeconds;
      expect(game.buyUpgrade(UpgradeType.checkout), isTrue);
      expect(game.cashierCheckoutSeconds, lessThan(before));
      expect(
        game.staffMembers.where((member) => member.role == StaffRole.cashier),
        hasLength(1),
      );
    },
  );

  test('hired cashier serves the FIFO queue once without player presence', () {
    game.debugSetProgress(sales: 16);
    game.coins = 1000;
    expect(game.hireStaff(StaffRole.cashier), isTrue);
    game.debugSetPlayerPosition(const Offset(0.5, 0.72));

    final first =
        MarketCustomer(
            id: 700,
            position: GameController.checkoutZone + const Offset(-0.03, 0.10),
            color: const Color(0xFF111111),
          )
          ..phase = CustomerPhase.checkout
          ..hasProduct = true;
    final second =
        MarketCustomer(
            id: 701,
            position: GameController.checkoutZone + const Offset(-0.03, 0.175),
            color: const Color(0xFF222222),
          )
          ..phase = CustomerPhase.checkout
          ..hasProduct = true;
    game.customers
      ..clear()
      ..add(first);
    game.tick(0.05);
    game.customers.add(second);

    final startingSales = game.totalSales;
    final startingCoins = game.coins;
    _advance(game, 0.2);

    expect(first.phase, CustomerPhase.paying);
    expect(first.checkoutOperator, CheckoutOperator.cashier);
    expect(second.phase, CustomerPhase.checkout);

    _advance(game, game.cashierCheckoutSeconds + 0.05);

    expect(first.phase, CustomerPhase.leaving);
    expect(game.totalSales, startingSales + 1);
    expect(game.coins, startingCoins + game.itemPrice);
    expect(second.phase, anyOf(CustomerPhase.checkout, CustomerPhase.paying));
  });

  test(
    'reconciliation gives every actor and staff record a unique valid ID',
    () {
      game.customers
        ..clear()
        ..addAll(<MarketCustomer>[
          MarketCustomer(
            id: 5,
            position: const Offset(-9, 12),
            color: const Color(0xFF111111),
          ),
          MarketCustomer(
            id: 5,
            position: const Offset(3, -4),
            color: const Color(0xFF222222),
          ),
        ]);

      game.debugReconcileState();

      expect(
        game.customers.map((customer) => customer.id).toSet(),
        hasLength(2),
      );
      for (final customer in game.customers) {
        expect(customer.position.dx, inInclusiveRange(-0.08, 1.08));
        expect(customer.position.dy, inInclusiveRange(-0.12, 1.0));
      }
      expect(
        game.staffMembers.map((member) => member.id).toSet(),
        hasLength(StaffRole.values.length),
      );
    },
  );

  test(
    'inventory orders respect delivery time and are delivered once',
    () async {
      var now = DateTime(2026, 7, 28, 12);
      final deliveryGame = GameController(
        storage: MemoryGameStorage(),
        monetization: PreviewMonetizationService(),
        now: () => now,
      );
      await deliveryGame.initialize();
      deliveryGame.coins = 400;

      final order = deliveryGame.placeInventoryOrder('Produce', 4, cost: 40);

      expect(order, isNotNull);
      expect(deliveryGame.pendingDeliveryCount, 1);
      expect(deliveryGame.fulfillPendingDelivery(order!.id), isFalse);

      now = now.add(GameBalance.inventoryOrderDelay);
      expect(deliveryGame.fulfillPendingDelivery(order.id), isTrue);
      expect(deliveryGame.fulfillPendingDelivery(order.id), isFalse);
      expect(deliveryGame.inventoryFor('Produce'), 4);
      expect(deliveryGame.inventoryFor('Produce'), isNonNegative);
    },
  );

  test(
    'quick restock orders General stock once without opening a menu',
    () async {
      var now = DateTime(2026, 7, 28, 12);
      final quickStorage = MemoryGameStorage()
        ..data = <String, dynamic>{
          'coins': 100,
          'inventory': <String, Object>{'General': 0},
          'dailyBonus': <String, Object>{'lastClaimedOn': '2026-07-28'},
        };
      final quickGame = GameController(
        storage: quickStorage,
        monetization: PreviewMonetizationService(),
        now: () => now,
      );
      await quickGame.initialize();

      expect(quickGame.canQuickRestock, isTrue);
      expect(quickGame.placeQuickRestock(), isNotNull);
      expect(quickGame.coins, 100 - GameBalance.quickRestockCost);
      expect(quickGame.hasPendingGeneralDelivery, isTrue);
      expect(quickGame.placeQuickRestock(), isNull);

      now = now.add(GameBalance.inventoryOrderDelay);
      final delivery = quickGame.pendingDeliveries.single;
      expect(quickGame.fulfillPendingDelivery(delivery.id), isTrue);
      expect(
        quickGame.inventoryFor('General'),
        GameBalance.quickRestockQuantity,
      );
      expect(quickGame.hasPendingGeneralDelivery, isFalse);
    },
  );

  test(
    'early-session simulation uses finite stock and retains a free recovery route',
    () async {
      expect(game.inventoryFor('General'), GameBalance.starterStorageStock);
      final initialSupply =
          game.inventoryFor('General') + game.carried + game.shelfStock;

      for (var cycle = 0; cycle < 4; cycle++) {
        game.debugSetPlayerPosition(GameController.stockZone);
        _advance(game, 2.5);
        game.debugSetPlayerPosition(GameController.shelfZone);
        _advance(game, 2);
        game.debugSetPlayerPosition(GameController.checkoutZone);
        _advance(game, 20);
      }

      expect(game.inventoryFor('General'), 0);
      expect(game.carried, 0);
      expect(game.shelfStock, 0);
      expect(game.totalSales, lessThanOrEqualTo(initialSupply));
      expect(game.coins, isNonNegative);

      game.coins = 0;
      expect(game.canClaimEmergencyStock, isTrue);
      expect(game.claimEmergencyStock(), isTrue);
      expect(game.inventoryFor('General'), GameBalance.emergencyStockQuantity);
      expect(game.claimEmergencyStock(), isFalse);
    },
  );

  test(
    'mid-session simulation charges for timed supply and respects capacity',
    () async {
      var now = DateTime(2026, 7, 28, 14);
      final midGame = GameController(
        storage: MemoryGameStorage(),
        monetization: PreviewMonetizationService(),
        random: Random(8),
        now: () => now,
      );
      await midGame.initialize();
      midGame.debugSetProgress(sales: 32, purchasedUpgrades: 4);
      midGame.coins = 500;
      final startingCoins = midGame.coins;
      final availableCapacity =
          midGame.storageCapacity - midGame.totalStoredInventory;

      final order = midGame.placeInventoryOrder(
        'General',
        availableCapacity,
        cost: 80,
      );

      expect(order, isNotNull);
      expect(midGame.coins, startingCoins - 80);
      expect(midGame.fulfillPendingDelivery(order!.id), isFalse);
      expect(midGame.placeInventoryOrder('General', 1, cost: 1), isNull);

      now = now.add(GameBalance.inventoryOrderDelay);
      expect(midGame.fulfillPendingDelivery(order.id), isTrue);
      expect(midGame.totalStoredInventory, midGame.storageCapacity);
      expect(midGame.totalStoredInventory, isNonNegative);
      expect(midGame.coins, isNonNegative);
    },
  );

  test(
    'long-session simulation never creates negative or unbounded resources',
    () async {
      var now = DateTime(2026, 7, 28, 16);
      final longGame = GameController(
        storage: MemoryGameStorage(),
        monetization: PreviewMonetizationService(),
        random: Random(12),
        now: () => now,
      );
      await longGame.initialize();
      longGame.debugSetProgress(sales: 64, purchasedUpgrades: 8);
      longGame.coins = 1200;

      for (var cycle = 0; cycle < 12; cycle++) {
        longGame.debugSetPlayerPosition(GameController.stockZone);
        _advance(longGame, 2.5);
        longGame.debugSetPlayerPosition(GameController.shelfZone);
        _advance(longGame, 2);
        longGame.debugSetPlayerPosition(GameController.checkoutZone);
        _advance(longGame, 10);

        final room =
            longGame.storageCapacity -
            longGame.totalStoredInventory -
            longGame.pendingDeliveries.fold<int>(
              0,
              (sum, delivery) => sum + delivery.quantity,
            );
        if (room > 0 && longGame.coins >= 20) {
          final order = longGame.placeInventoryOrder('General', min(4, room));
          if (order != null) {
            now = now.add(GameBalance.inventoryOrderDelay);
            expect(longGame.fulfillPendingDelivery(order.id), isTrue);
          }
        }
      }

      expect(longGame.coins, isNonNegative);
      expect(longGame.inventoryFor('General'), isNonNegative);
      expect(longGame.carried, inInclusiveRange(0, longGame.bagCapacity));
      expect(longGame.shelfStock, inInclusiveRange(0, longGame.shelfCapacity));
      expect(
        longGame.totalStoredInventory,
        lessThanOrEqualTo(longGame.storageCapacity),
      );
      expect(
        longGame.customers.map((customer) => customer.id).toSet(),
        hasLength(longGame.customers.length),
      );
    },
  );

  test(
    'restores progress, inventory, stats, settings, and score history',
    () async {
      game.completeOnboarding();
      game.setMuted(true);
      game.debugSetPlayerPosition(GameController.stockZone);
      _advance(game, 1.1);
      game.submitLeaderboardScore('  Market Hero  ');
      await game.save();

      final restored = GameController(
        storage: storage,
        monetization: PreviewMonetizationService(),
        random: Random(4),
      );
      await restored.initialize();

      expect(restored.carried, game.carried);
      expect(restored.totalActions, game.totalActions);
      expect(restored.totalPlayTime, game.totalPlayTime);
      expect(restored.onboardingComplete, isTrue);
      expect(restored.muted, isTrue);
      expect(restored.leaderboard.single.nickname, 'Market Hero');
      expect(restored.performanceHistory, isNotEmpty);
    },
  );

  test(
    'daily bonus is awarded once per local day and grows the streak',
    () async {
      final bonusStorage = MemoryGameStorage();
      var now = DateTime(2026, 7, 26, 9);
      final first = GameController(
        storage: bonusStorage,
        monetization: PreviewMonetizationService(),
        now: () => now,
      );
      await first.initialize();
      final firstBalance = first.coins;
      expect(first.dailyBonus.currentStreak, 1);
      expect(first.pendingDailyBonus?.wasAwarded, isTrue);
      await first.save();

      final sameDay = GameController(
        storage: bonusStorage,
        monetization: PreviewMonetizationService(),
        now: () => now.add(const Duration(hours: 10)),
      );
      await sameDay.initialize();
      expect(sameDay.coins, firstBalance);
      expect(sameDay.pendingDailyBonus, isNull);

      now = DateTime(2026, 7, 27, 8);
      final nextDay = GameController(
        storage: bonusStorage,
        monetization: PreviewMonetizationService(),
        now: () => now,
      );
      await nextDay.initialize();
      expect(nextDay.dailyBonus.currentStreak, 2);
      expect(nextDay.coins, greaterThan(firstBalance));
    },
  );

  test('achievement unlocks once and local leaderboard stays top ten', () {
    game.debugSetPlayerPosition(GameController.stockZone);
    _advance(game, 2.2);
    game.debugSetPlayerPosition(GameController.shelfZone);
    _advance(game, 2);
    game.debugSetPlayerPosition(GameController.checkoutZone);
    _advance(game, 24);

    expect(game.totalSales, greaterThan(0));
    expect(game.takeAchievementUnlock()?.id, 'first_sale');
    expect(game.takeAchievementUnlock(), isNull);

    for (var index = 0; index < 14; index++) {
      game.submitLeaderboardScore('Player $index');
    }
    expect(game.leaderboard, hasLength(10));
    expect(
      game.leaderboard.map((entry) => entry.score),
      orderedEquals(
        game.leaderboard.map((entry) => entry.score).toList()
          ..sort((a, b) => b.compareTo(a)),
      ),
    );
  });
}

class _FakeMonetizationService implements MonetizationService {
  bool nextRewardEarned = true;
  bool nextInterstitialShown = true;
  int rewardedCalls = 0;
  int interstitialCalls = 0;
  StorePurchaseResult nextPurchase = const StorePurchaseResult.failed(
    StoreProduct.coinPack,
  );
  List<StorePurchaseResult> restoredPurchases = const <StorePurchaseResult>[];

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
  String? priceFor(StoreProduct product) => '₪3.90';

  @override
  Future<StorePurchaseResult> purchase(StoreProduct product) async {
    return nextPurchase;
  }

  @override
  Future<List<StorePurchaseResult>> restorePurchases() async {
    return restoredPurchases;
  }

  @override
  Future<bool> showInterstitial(InterstitialPlacement placement) async {
    interstitialCalls++;
    return nextInterstitialShown;
  }

  @override
  Future<bool> showRewardedAd(RewardPlacement placement) async {
    rewardedCalls++;
    return nextRewardEarned;
  }
}

void _advance(GameController game, double seconds) {
  final frames = (seconds / 0.05).ceil();
  for (var frame = 0; frame < frames; frame++) {
    game.tick(0.05);
  }
}
