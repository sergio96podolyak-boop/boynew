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

  test('rewarded preview grants coins', () async {
    final before = game.coins;
    final reward = game.instantAdReward;

    expect(await game.claimInstantAdReward(), isTrue);
    expect(game.coins, before + reward);
  });

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

void _advance(GameController game, double seconds) {
  final frames = (seconds / 0.05).ceil();
  for (var frame = 0; frame < frames; frame++) {
    game.tick(0.05);
  }
}
