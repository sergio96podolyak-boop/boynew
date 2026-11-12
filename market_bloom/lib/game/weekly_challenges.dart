/// Weekly challenges: three rotating goals per calendar week (Monday start),
/// plus a bonus chest once all three are claimed.
///
/// Progress is measured against lifetime counters the game already tracks.
/// At the start of each week the current counter values are stored as
/// baselines, so progress is always "what you did this week". The model is
/// UI-independent and tolerant of malformed saved data.
library;

enum WeeklyChallengeMetric { sales, itemsStocked, coinsEarned, upgrades, actions }

class WeeklyChallenge {
  const WeeklyChallenge({
    required this.id,
    required this.metric,
    required this.target,
    required this.coinReward,
    required this.gemReward,
  });

  final String id;
  final WeeklyChallengeMetric metric;
  final int target;
  final int coinReward;
  final int gemReward;
}

class WeeklyChallengeProgress {
  const WeeklyChallengeProgress({
    required this.challenge,
    required this.progress,
    required this.claimed,
  });

  final WeeklyChallenge challenge;
  final int progress;
  final bool claimed;

  bool get completed => progress >= challenge.target;
  bool get readyToClaim => completed && !claimed;
  double get fraction =>
      challenge.target <= 0 ? 1 : (progress / challenge.target).clamp(0.0, 1.0);
}

abstract final class WeeklyChallengeBalance {
  static const int challengesPerWeek = 3;
  static const int chestCoins = 150;
  static const int chestGems = 5;

  /// Target, coin reward and gem reward for a metric at a given store level.
  static (int target, int coins, int gems) tuning(
    WeeklyChallengeMetric metric,
    int storeLevel,
  ) {
    final level = storeLevel < 1 ? 1 : storeLevel;
    return switch (metric) {
      WeeklyChallengeMetric.sales => (40 + 15 * level, 60 + 20 * level, 2),
      WeeklyChallengeMetric.itemsStocked => (
        60 + 20 * level,
        50 + 15 * level,
        1,
      ),
      WeeklyChallengeMetric.coinsEarned => (
        400 + 200 * level,
        80 + 25 * level,
        2,
      ),
      WeeklyChallengeMetric.upgrades => (3 + level ~/ 2, 70 + 20 * level, 2),
      WeeklyChallengeMetric.actions => (150 + 40 * level, 50 + 15 * level, 1),
    };
  }
}

class WeeklyChallengeState {
  const WeeklyChallengeState({
    this.weekStart,
    this.storeLevelAtStart = 1,
    this.baselines = const <WeeklyChallengeMetric, int>{},
    this.claimedIds = const <String>{},
    this.chestClaimed = false,
  });

  factory WeeklyChallengeState.fromJson(Object? value) {
    if (value is! Map) return const WeeklyChallengeState();
    final rawWeek = value['weekStart'];
    final week = rawWeek is String ? DateTime.tryParse(rawWeek) : null;
    final rawLevel = value['storeLevelAtStart'];
    final baselines = <WeeklyChallengeMetric, int>{};
    final rawBaselines = value['baselines'];
    if (rawBaselines is Map) {
      for (final metric in WeeklyChallengeMetric.values) {
        final v = rawBaselines[metric.name];
        if (v is num && v >= 0) baselines[metric] = v.toInt();
      }
    }
    final rawClaimed = value['claimedIds'];
    return WeeklyChallengeState(
      weekStart: week == null ? null : weekStartFor(week),
      storeLevelAtStart: rawLevel is num && rawLevel >= 1 ? rawLevel.toInt() : 1,
      baselines: Map.unmodifiable(baselines),
      claimedIds: rawClaimed is List
          ? Set.unmodifiable(rawClaimed.whereType<String>())
          : const <String>{},
      chestClaimed: value['chestClaimed'] == true,
    );
  }

  /// Local midnight of the Monday that starts the week containing [time].
  static DateTime weekStartFor(DateTime time) {
    final day = DateTime(time.year, time.month, time.day);
    return day.subtract(Duration(days: day.weekday - DateTime.monday));
  }

  final DateTime? weekStart;
  final int storeLevelAtStart;
  final Map<WeeklyChallengeMetric, int> baselines;
  final Set<String> claimedIds;
  final bool chestClaimed;

  bool needsRollover(DateTime now) {
    final start = weekStart;
    if (start == null) return true;
    final current = weekStartFor(now);
    return current.year != start.year ||
        current.month != start.month ||
        current.day != start.day;
  }

  /// Starts the week containing [now], snapshotting [currentTotals].
  WeeklyChallengeState rollover(
    DateTime now, {
    required int storeLevel,
    required Map<WeeklyChallengeMetric, int> currentTotals,
  }) {
    return WeeklyChallengeState(
      weekStart: weekStartFor(now),
      storeLevelAtStart: storeLevel < 1 ? 1 : storeLevel,
      baselines: Map.unmodifiable(<WeeklyChallengeMetric, int>{
        for (final metric in WeeklyChallengeMetric.values)
          metric: currentTotals[metric] ?? 0,
      }),
    );
  }

  /// Weeks since the Unix epoch; drives deterministic rotation.
  int get _weekIndex {
    final start = weekStart;
    if (start == null) return 0;
    final utcDay = DateTime.utc(start.year, start.month, start.day);
    return utcDay.millisecondsSinceEpoch ~/ Duration.millisecondsPerDay ~/ 7;
  }

  /// This week's challenges: three different metrics, rotating each week.
  List<WeeklyChallenge> get challenges {
    const metrics = WeeklyChallengeMetric.values;
    final offset = _weekIndex % metrics.length;
    final weekKey = weekStart == null
        ? 'none'
        : '${weekStart!.year}-${weekStart!.month}-${weekStart!.day}';
    return List<WeeklyChallenge>.unmodifiable(
      List<WeeklyChallenge>.generate(
        WeeklyChallengeBalance.challengesPerWeek,
        (i) {
          final metric = metrics[(offset + i * 2) % metrics.length];
          final (target, coins, gems) = WeeklyChallengeBalance.tuning(
            metric,
            storeLevelAtStart,
          );
          return WeeklyChallenge(
            id: '$weekKey-${metric.name}',
            metric: metric,
            target: target,
            coinReward: coins,
            gemReward: gems,
          );
        },
      ),
    );
  }

  List<WeeklyChallengeProgress> progress(
    Map<WeeklyChallengeMetric, int> currentTotals,
  ) {
    return List<WeeklyChallengeProgress>.unmodifiable(
      challenges.map((challenge) {
        final current = currentTotals[challenge.metric] ?? 0;
        final base = baselines[challenge.metric] ?? current;
        final done = current - base;
        return WeeklyChallengeProgress(
          challenge: challenge,
          progress: done < 0 ? 0 : done,
          claimed: claimedIds.contains(challenge.id),
        );
      }),
    );
  }

  bool get allClaimed =>
      challenges.every((challenge) => claimedIds.contains(challenge.id));

  bool get chestReady => allClaimed && !chestClaimed;

  WeeklyChallengeState _copy({Set<String>? claimedIds, bool? chestClaimed}) =>
      WeeklyChallengeState(
        weekStart: weekStart,
        storeLevelAtStart: storeLevelAtStart,
        baselines: baselines,
        claimedIds: claimedIds ?? this.claimedIds,
        chestClaimed: chestClaimed ?? this.chestClaimed,
      );

  WeeklyChallengeState markClaimed(String id) =>
      _copy(claimedIds: Set.unmodifiable(<String>{...claimedIds, id}));

  WeeklyChallengeState markChestClaimed() => _copy(chestClaimed: true);

  Duration timeLeft(DateTime now) {
    final start = weekStart ?? weekStartFor(now);
    final end = DateTime(start.year, start.month, start.day + 7);
    final left = end.difference(now);
    return left.isNegative ? Duration.zero : left;
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'weekStart': weekStart?.toIso8601String(),
    'storeLevelAtStart': storeLevelAtStart,
    'baselines': <String, int>{
      for (final entry in baselines.entries) entry.key.name: entry.value,
    },
    'claimedIds': claimedIds.toList(growable: false),
    'chestClaimed': chestClaimed,
  };
}
