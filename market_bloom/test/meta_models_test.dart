import 'package:flutter_test/flutter_test.dart';
import 'package:pomarket/game/meta_models.dart';

void main() {
  group('achievements', () {
    test('catalog IDs are unique and progress unlocks once', () {
      expect(AchievementCatalog.byId.length, AchievementCatalog.all.length);
      final definition = AchievementCatalog.find('first_sale')!;
      final locked = AchievementProgress(achievementId: definition.id);
      final unlocked = locked.evaluate(
        definition: definition,
        value: 1,
        now: DateTime.utc(2026, 7, 26, 10),
      );
      final evaluatedAgain = unlocked.evaluate(
        definition: definition,
        value: 12,
        now: DateTime.utc(2026, 7, 27, 10),
      );

      expect(unlocked.isUnlocked, isTrue);
      expect(unlocked.fractionFor(definition), 1);
      expect(evaluatedAgain.unlockedAt, unlocked.unlockedAt);
    });

    test('restores valid catalog progress and drops unknown IDs', () {
      final restored = AchievementCatalog.restoreProgress(<Object?>[
        <String, Object?>{
          'achievementId': 'first_sale',
          'currentValue': '1',
          'unlockedAt': '2026-07-26T12:00:00Z',
        },
        <String, Object?>{
          'achievementId': 'future_removed_badge',
          'currentValue': 999,
        },
      ]);

      expect(restored, hasLength(1));
      expect(restored.single.achievementId, 'first_sale');
      expect(restored.single.isUnlocked, isTrue);
    });
  });

  group('performance history', () {
    test('sorts, filters corrupt dates, and caps old samples', () {
      final restored = PerformanceSample.restoreList(<Object?>[
        _sample('2026-07-26T12:02:00Z', 30),
        <String, Object?>{'recordedAt': 'not-a-date'},
        _sample('2026-07-26T12:00:00Z', 10),
        _sample('2026-07-26T12:01:00Z', 20),
      ], maximum: 2);

      expect(restored.map((sample) => sample.balance), <int>[20, 30]);
    });
  });

  group('leaderboard', () {
    test('sanitizes names, ranks scores, deduplicates, and caps results', () {
      final ranked = LeaderboardEntry.top(<Object?>[
        _entry('a', '  Ada   Lovelace  ', 500),
        _entry('b', '', 700),
        _entry('a', 'Ada', 900),
        _entry('c', 'Grace', -50),
      ], maximum: 2);

      expect(ranked.map((entry) => entry.score), <int>[900, 700]);
      expect(ranked.first.nickname, 'Ada');
      expect(ranked.last.nickname, 'Player');
    });
  });

  group('daily bonus', () {
    test('awards once per day and grows a consecutive streak', () {
      const initial = DailyBonusState();
      final first = initial.claim(DateTime(2026, 7, 25, 9));
      final duplicate = first.state.claim(DateTime(2026, 7, 25, 22));
      final second = duplicate.state.claim(DateTime(2026, 7, 26, 8));

      expect(first.result.wasAwarded, isTrue);
      expect(first.result.streak, 1);
      expect(first.result.coinsAwarded, 30);
      expect(duplicate.result.wasAwarded, isFalse);
      expect(second.result.streak, 2);
      expect(second.result.coinsAwarded, 40);
      expect(second.state.longestStreak, 2);
    });

    test('resets after a missed day and awards a fifth-day gem', () {
      var state = const DailyBonusState();
      DailyBonusResult? latestReward;
      for (var day = 1; day <= 5; day++) {
        final claim = state.claim(DateTime(2026, 7, day));
        state = claim.state;
        latestReward = claim.result;
      }
      final fifth = state.claim(DateTime(2026, 7, 5, 12));
      final missed = state.claim(DateTime(2026, 7, 8));

      expect(state.currentStreak, 5);
      expect(state.claim(DateTime(2026, 7, 5)).result.wasAwarded, isFalse);
      expect(fifth.result.wasAwarded, isFalse);
      expect(latestReward!.gemsAwarded, 1);
      expect(latestReward.isMilestone, isTrue);
      expect(missed.state.currentStreak, 1);
      expect(missed.state.longestStreak, 5);
    });

    test('round-trips state with a stable local calendar key', () {
      const json = <String, Object?>{
        'currentStreak': '3',
        'longestStreak': 8,
        'totalClaims': 11,
        'lastClaimedOn': '2026-07-26',
      };
      final state = DailyBonusState.fromJson(json);

      expect(state.currentStreak, 3);
      expect(state.lastClaimedOn, DateTime(2026, 7, 26));
      expect(state.toJson(), <String, Object?>{
        'currentStreak': 3,
        'longestStreak': 8,
        'totalClaims': 11,
        'lastClaimedOn': '2026-07-26',
      });
    });
  });
}

Map<String, Object?> _sample(String timestamp, int balance) =>
    <String, Object?>{
      'recordedAt': timestamp,
      'balance': balance,
      'businessScore': balance * 2,
      'totalSales': 1,
      'storeLevel': 1,
      'totalActions': 2,
    };

Map<String, Object?> _entry(String id, String nickname, int score) =>
    <String, Object?>{
      'id': id,
      'nickname': nickname,
      'score': score,
      'achievedAt': '2026-07-26T12:00:00Z',
      'storeLevel': 2,
      'totalSales': 5,
    };
