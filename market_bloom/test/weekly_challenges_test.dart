import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:pomarket/game/game_controller.dart';
import 'package:pomarket/game/weekly_challenges.dart';
import 'package:pomarket/services/game_storage.dart';
import 'package:pomarket/services/monetization_service.dart';

Map<WeeklyChallengeMetric, int> _totals({
  int sales = 0,
  int stocked = 0,
  int coins = 0,
  int upgrades = 0,
  int actions = 0,
}) => <WeeklyChallengeMetric, int>{
  WeeklyChallengeMetric.sales: sales,
  WeeklyChallengeMetric.itemsStocked: stocked,
  WeeklyChallengeMetric.coinsEarned: coins,
  WeeklyChallengeMetric.upgrades: upgrades,
  WeeklyChallengeMetric.actions: actions,
};

void main() {
  group('WeeklyChallengeState', () {
    test('week starts on Monday at local midnight', () {
      // Thursday 12 Nov 2026 -> Monday 9 Nov 2026.
      final start = WeeklyChallengeState.weekStartFor(
        DateTime(2026, 11, 12, 17, 30),
      );
      expect(start, DateTime(2026, 11, 9));
      expect(
        WeeklyChallengeState.weekStartFor(DateTime(2026, 11, 9)),
        DateTime(2026, 11, 9),
      );
      expect(
        WeeklyChallengeState.weekStartFor(DateTime(2026, 11, 15, 23, 59)),
        DateTime(2026, 11, 9),
      );
    });

    test('offers three distinct metrics that rotate between weeks', () {
      final week1 = const WeeklyChallengeState().rollover(
        DateTime(2026, 11, 12),
        storeLevel: 2,
        currentTotals: _totals(),
      );
      final week2 = week1.rollover(
        DateTime(2026, 11, 19),
        storeLevel: 2,
        currentTotals: _totals(),
      );

      final metrics1 = week1.challenges.map((c) => c.metric).toSet();
      final metrics2 = week2.challenges.map((c) => c.metric).toSet();
      expect(week1.challenges, hasLength(3));
      expect(metrics1, hasLength(3));
      expect(metrics2, hasLength(3));
      expect(metrics1, isNot(equals(metrics2)));
    });

    test('progress counts only what happened this week', () {
      final state = const WeeklyChallengeState().rollover(
        DateTime(2026, 11, 12),
        storeLevel: 1,
        currentTotals: _totals(sales: 100, stocked: 50, coins: 900),
      );
      final progress = state.progress(
        _totals(sales: 130, stocked: 70, coins: 1000, upgrades: 2, actions: 9),
      );
      for (final item in progress) {
        final expected = switch (item.challenge.metric) {
          WeeklyChallengeMetric.sales => 30,
          WeeklyChallengeMetric.itemsStocked => 20,
          WeeklyChallengeMetric.coinsEarned => 100,
          WeeklyChallengeMetric.upgrades => 2,
          WeeklyChallengeMetric.actions => 9,
        };
        expect(item.progress, expected);
        expect(item.claimed, isFalse);
      }
    });

    test('rolls over only when the calendar week changes', () {
      final state = const WeeklyChallengeState().rollover(
        DateTime(2026, 11, 9, 0, 1),
        storeLevel: 1,
        currentTotals: _totals(),
      );
      expect(state.needsRollover(DateTime(2026, 11, 15, 23, 59)), isFalse);
      expect(state.needsRollover(DateTime(2026, 11, 16)), isTrue);
      expect(const WeeklyChallengeState().needsRollover(DateTime(2026)), isTrue);
    });

    test('chest becomes ready only after all three are claimed', () {
      var state = const WeeklyChallengeState().rollover(
        DateTime(2026, 11, 12),
        storeLevel: 1,
        currentTotals: _totals(),
      );
      expect(state.chestReady, isFalse);
      for (final challenge in state.challenges) {
        expect(state.chestReady, isFalse);
        state = state.markClaimed(challenge.id);
      }
      expect(state.chestReady, isTrue);
      state = state.markChestClaimed();
      expect(state.chestReady, isFalse);
    });

    test('survives a save round trip and ignores malformed data', () {
      final state = const WeeklyChallengeState()
          .rollover(
            DateTime(2026, 11, 12),
            storeLevel: 3,
            currentTotals: _totals(sales: 7),
          )
          .markClaimed('x');
      final restored = WeeklyChallengeState.fromJson(state.toJson());
      expect(restored.weekStart, state.weekStart);
      expect(restored.storeLevelAtStart, 3);
      expect(restored.baselines[WeeklyChallengeMetric.sales], 7);
      expect(restored.claimedIds, contains('x'));

      final broken = WeeklyChallengeState.fromJson(<String, Object?>{
        'weekStart': 'not a date',
        'storeLevelAtStart': -4,
        'baselines': 'oops',
        'claimedIds': <Object?>[1, 'ok'],
      });
      expect(broken.weekStart, isNull);
      expect(broken.storeLevelAtStart, 1);
      expect(broken.baselines, isEmpty);
      expect(broken.claimedIds, <String>{'ok'});
      expect(WeeklyChallengeState.fromJson(null).weekStart, isNull);
    });

    test('targets and rewards grow with store level', () {
      for (final metric in WeeklyChallengeMetric.values) {
        final (lowTarget, lowCoins, _) = WeeklyChallengeBalance.tuning(
          metric,
          1,
        );
        final (highTarget, highCoins, _) = WeeklyChallengeBalance.tuning(
          metric,
          8,
        );
        expect(highTarget, greaterThan(lowTarget));
        expect(highCoins, greaterThan(lowCoins));
      }
    });
  });

  group('GameController weekly challenges', () {
    late DateTime now;
    late GameController game;

    setUp(() async {
      now = DateTime(2026, 11, 12, 10);
      game = GameController(
        storage: MemoryGameStorage(),
        monetization: PreviewMonetizationService(),
        random: Random(4),
        now: () => now,
      );
      await game.initialize();
    });

    test('starts a week on load with zero progress', () {
      expect(game.weeklyChallenges.weekStart, DateTime(2026, 11, 9));
      expect(game.weeklyChallengeProgress, hasLength(3));
      expect(
        game.weeklyChallengeProgress.every((item) => item.progress == 0),
        isTrue,
      );
      expect(game.weeklyTimeLeft, const Duration(days: 3, hours: 14));
    });

    test('unfinished challenges cannot be claimed', () {
      final id = game.weeklyChallengeProgress.first.challenge.id;
      final coinsBefore = game.coins;
      expect(game.claimWeeklyChallenge(id), isFalse);
      expect(game.claimWeeklyChallenge('unknown'), isFalse);
      expect(game.claimWeeklyChest(), isFalse);
      expect(game.coins, coinsBefore);
    });

    test('completing and claiming pays out once, then the chest', () {
      for (final item in game.weeklyChallengeProgress) {
        switch (item.challenge.metric) {
          case WeeklyChallengeMetric.sales:
            game.totalSales += item.challenge.target;
          case WeeklyChallengeMetric.itemsStocked:
            game.stockedTotal += item.challenge.target;
          case WeeklyChallengeMetric.coinsEarned:
            game.totalCoinsEarned += item.challenge.target;
          case WeeklyChallengeMetric.upgrades:
            game.upgradesBought += item.challenge.target;
          case WeeklyChallengeMetric.actions:
            game.totalActions += item.challenge.target;
        }
      }
      expect(game.weeklyReadyToClaimCount, 3);

      for (final item in game.weeklyChallengeProgress) {
        final coins = game.coins;
        final gems = game.gems;
        expect(game.claimWeeklyChallenge(item.challenge.id), isTrue);
        expect(game.coins, coins + item.challenge.coinReward);
        expect(game.gems, gems + item.challenge.gemReward);
        expect(game.claimWeeklyChallenge(item.challenge.id), isFalse);
      }

      expect(game.weeklyReadyToClaimCount, 1);
      final gems = game.gems;
      expect(game.claimWeeklyChest(), isTrue);
      expect(game.gems, gems + WeeklyChallengeBalance.chestGems);
      expect(game.claimWeeklyChest(), isFalse);
      expect(game.weeklyReadyToClaimCount, 0);
    });

    test('a new calendar week resets claims and baselines', () async {
      final firstWeek = game.weeklyChallenges.weekStart;
      game.totalSales += 5;
      now = DateTime(2026, 11, 17, 9);
      game.tick(0.05);
      for (var i = 0; i < 120; i++) {
        game.tick(0.05);
      }
      expect(game.weeklyChallenges.weekStart, DateTime(2026, 11, 16));
      expect(game.weeklyChallenges.weekStart, isNot(firstWeek));
      expect(
        game.weeklyChallengeProgress.every((item) => !item.claimed),
        isTrue,
      );
    });
  });
}
