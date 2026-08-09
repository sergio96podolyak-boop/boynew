import 'dart:math';

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

  test('stocked shelves create sales and coins', () {
    game.debugSetPlayerPosition(GameController.stockZone);
    _advance(game, 2.2);
    game.debugSetPlayerPosition(GameController.shelfZone);
    _advance(game, 2);
    game.debugSetPlayerPosition(const Offset(0.5, 0.72));

    final startingCoins = game.coins;
    _advance(game, 24);

    expect(game.totalSales, greaterThan(0));
    expect(game.coins, greaterThan(startingCoins));
  });

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
    game.debugSetPlayerPosition(const Offset(0.5, 0.72));
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
