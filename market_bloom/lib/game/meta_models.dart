/// Persistent, UI-independent models for PoMarket's long-term progression.
///
/// The parsers in this file intentionally accept [Object] rather than assuming
/// perfectly shaped maps. Browser storage can be edited, truncated, or contain
/// values written by an older release, so every model restores safe defaults.
library;

enum AchievementMetric {
  totalSales,
  itemsStocked,
  totalCoinsEarned,
  upgradesPurchased,
  storeLevel,
  dailyStreak,
  highestBalance,
  totalActions,
  playTimeMinutes,
}

enum AchievementTier { bronze, silver, gold, platinum }

class AchievementDefinition {
  const AchievementDefinition({
    required this.id,
    required this.title,
    required this.description,
    required this.metric,
    required this.target,
    required this.badge,
    required this.tier,
  });

  factory AchievementDefinition.fromJson(Object? value) {
    final json = _asMap(value);
    return AchievementDefinition(
      id: _safeId(json['id'], fallback: 'unknown'),
      title: _safeText(json['title'], fallback: 'Achievement'),
      description: _safeText(
        json['description'],
        fallback: 'Keep growing your PoMarket business.',
      ),
      metric: _enumByName(
        AchievementMetric.values,
        json['metric'],
        AchievementMetric.totalActions,
      ),
      target: _positiveInt(json['target'], fallback: 1),
      badge: _safeText(json['badge'], fallback: '🏅', maxLength: 8),
      tier: _enumByName(
        AchievementTier.values,
        json['tier'],
        AchievementTier.bronze,
      ),
    );
  }

  final String id;
  final String title;
  final String description;
  final AchievementMetric metric;
  final int target;

  /// An emoji badge keeps the domain model portable across Flutter and Dart.
  final String badge;
  final AchievementTier tier;

  Map<String, Object> toJson() => <String, Object>{
    'id': id,
    'title': title,
    'description': description,
    'metric': metric.name,
    'target': target,
    'badge': badge,
    'tier': tier.name,
  };
}

class AchievementProgress {
  const AchievementProgress({
    required this.achievementId,
    this.currentValue = 0,
    this.unlockedAt,
  });

  factory AchievementProgress.fromJson(Object? value) {
    final json = _asMap(value);
    return AchievementProgress(
      achievementId: _safeId(
        json['achievementId'] ?? json['id'],
        fallback: 'unknown',
      ),
      currentValue: _nonNegativeInt(json['currentValue'] ?? json['progress']),
      unlockedAt: _optionalDateTime(json['unlockedAt']),
    );
  }

  final String achievementId;
  final int currentValue;
  final DateTime? unlockedAt;

  bool get isUnlocked => unlockedAt != null;

  double fractionFor(AchievementDefinition definition) {
    if (isUnlocked) return 1;
    return (currentValue / definition.target).clamp(0.0, 1.0);
  }

  AchievementProgress evaluate({
    required AchievementDefinition definition,
    required int value,
    required DateTime now,
  }) {
    final nextValue = value < 0 ? 0 : value;
    final unlockTime =
        unlockedAt ?? (nextValue >= definition.target ? now.toUtc() : null);
    return AchievementProgress(
      achievementId: definition.id,
      currentValue: nextValue,
      unlockedAt: unlockTime,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'achievementId': achievementId,
    'currentValue': currentValue,
    'unlockedAt': unlockedAt?.toUtc().toIso8601String(),
  };
}

abstract final class AchievementCatalog {
  static const List<AchievementDefinition> all = <AchievementDefinition>[
    AchievementDefinition(
      id: 'first_sale',
      title: 'First Checkout',
      description: 'Complete your first customer sale.',
      metric: AchievementMetric.totalSales,
      target: 1,
      badge: '🛒',
      tier: AchievementTier.bronze,
    ),
    AchievementDefinition(
      id: 'shelf_starter',
      title: 'Shelf Starter',
      description: 'Stock 25 products on your shelves.',
      metric: AchievementMetric.itemsStocked,
      target: 25,
      badge: '📦',
      tier: AchievementTier.bronze,
    ),
    AchievementDefinition(
      id: 'bustling_market',
      title: 'Bustling Market',
      description: 'Serve 50 happy customers.',
      metric: AchievementMetric.totalSales,
      target: 50,
      badge: '🏪',
      tier: AchievementTier.silver,
    ),
    AchievementDefinition(
      id: 'coin_club',
      title: 'Coin Club',
      description: 'Earn 1,000 coins across your business.',
      metric: AchievementMetric.totalCoinsEarned,
      target: 1000,
      badge: '🪙',
      tier: AchievementTier.silver,
    ),
    AchievementDefinition(
      id: 'upgrade_pro',
      title: 'Upgrade Pro',
      description: 'Purchase 10 business upgrades.',
      metric: AchievementMetric.upgradesPurchased,
      target: 10,
      badge: '🛠️',
      tier: AchievementTier.gold,
    ),
    AchievementDefinition(
      id: 'growing_business',
      title: 'Growing Business',
      description: 'Reach store level 5.',
      metric: AchievementMetric.storeLevel,
      target: 5,
      badge: '📈',
      tier: AchievementTier.gold,
    ),
    AchievementDefinition(
      id: 'streak_starter',
      title: 'Streak Starter',
      description: 'Open PoMarket 3 days in a row.',
      metric: AchievementMetric.dailyStreak,
      target: 3,
      badge: '🔥',
      tier: AchievementTier.gold,
    ),
    AchievementDefinition(
      id: 'market_mogul',
      title: 'Market Mogul',
      description: 'Hold a balance of 5,000 coins.',
      metric: AchievementMetric.highestBalance,
      target: 5000,
      badge: '👑',
      tier: AchievementTier.platinum,
    ),
  ];

  static final Map<String, AchievementDefinition> byId =
      <String, AchievementDefinition>{
        for (final definition in all) definition.id: definition,
      };

  static AchievementDefinition? find(String id) => byId[id];

  static List<AchievementProgress> restoreProgress(Object? value) {
    if (value is! List) return const <AchievementProgress>[];
    final byAchievement = <String, AchievementProgress>{};
    for (final item in value) {
      final progress = AchievementProgress.fromJson(item);
      if (!byId.containsKey(progress.achievementId)) continue;
      final previous = byAchievement[progress.achievementId];
      if (previous == null ||
          progress.currentValue > previous.currentValue ||
          (previous.unlockedAt == null && progress.unlockedAt != null)) {
        byAchievement[progress.achievementId] = progress;
      }
    }
    return List<AchievementProgress>.unmodifiable(byAchievement.values);
  }
}

class PerformanceSample {
  const PerformanceSample({
    required this.recordedAt,
    required this.balance,
    required this.businessScore,
    required this.totalSales,
    required this.storeLevel,
    required this.totalActions,
  });

  factory PerformanceSample.fromJson(Object? value) {
    final json = _asMap(value);
    return PerformanceSample(
      recordedAt:
          _optionalDateTime(json['recordedAt'] ?? json['timestamp']) ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      balance: _nonNegativeInt(json['balance'] ?? json['coins']),
      businessScore: _nonNegativeInt(json['businessScore'] ?? json['score']),
      totalSales: _nonNegativeInt(json['totalSales'] ?? json['sales']),
      storeLevel: _positiveInt(
        json['storeLevel'] ?? json['level'],
        fallback: 1,
      ),
      totalActions: _nonNegativeInt(json['totalActions'] ?? json['actions']),
    );
  }

  final DateTime recordedAt;
  final int balance;
  final int businessScore;
  final int totalSales;
  final int storeLevel;
  final int totalActions;

  Map<String, Object> toJson() => <String, Object>{
    'recordedAt': recordedAt.toUtc().toIso8601String(),
    'balance': balance,
    'businessScore': businessScore,
    'totalSales': totalSales,
    'storeLevel': storeLevel,
    'totalActions': totalActions,
  };

  static List<PerformanceSample> restoreList(
    Object? value, {
    int maximum = 48,
  }) {
    if (value is! List || maximum <= 0) return const <PerformanceSample>[];
    final restored =
        value
            .map(PerformanceSample.fromJson)
            .where((sample) => sample.recordedAt.millisecondsSinceEpoch > 0)
            .toList()
          ..sort((a, b) => a.recordedAt.compareTo(b.recordedAt));
    if (restored.length > maximum) {
      return List<PerformanceSample>.unmodifiable(
        restored.sublist(restored.length - maximum),
      );
    }
    return List<PerformanceSample>.unmodifiable(restored);
  }
}

class LeaderboardEntry {
  const LeaderboardEntry({
    required this.id,
    required this.nickname,
    required this.score,
    required this.achievedAt,
    required this.storeLevel,
    required this.totalSales,
  });

  factory LeaderboardEntry.fromJson(Object? value) {
    final json = _asMap(value);
    final achievedAt =
        _optionalDateTime(json['achievedAt'] ?? json['timestamp']) ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    return LeaderboardEntry(
      id: _safeId(
        json['id'],
        fallback:
            'legacy-${achievedAt.millisecondsSinceEpoch}-${_nonNegativeInt(json['score'])}',
      ),
      nickname: sanitizeNickname(json['nickname'] ?? json['name']),
      score: _nonNegativeInt(json['score']),
      achievedAt: achievedAt,
      storeLevel: _positiveInt(
        json['storeLevel'] ?? json['level'],
        fallback: 1,
      ),
      totalSales: _nonNegativeInt(json['totalSales'] ?? json['sales']),
    );
  }

  final String id;
  final String nickname;
  final int score;
  final DateTime achievedAt;
  final int storeLevel;
  final int totalSales;

  Map<String, Object> toJson() => <String, Object>{
    'id': id,
    'nickname': nickname,
    'score': score,
    'achievedAt': achievedAt.toUtc().toIso8601String(),
    'storeLevel': storeLevel,
    'totalSales': totalSales,
  };

  static String sanitizeNickname(Object? value) {
    final raw = value is String ? value.trim() : '';
    final collapsed = raw.replaceAll(RegExp(r'\s+'), ' ');
    if (collapsed.isEmpty) return 'Player';
    return collapsed.length <= 20 ? collapsed : collapsed.substring(0, 20);
  }

  static List<LeaderboardEntry> top(Object? value, {int maximum = 10}) {
    if (value is! List || maximum <= 0) return const <LeaderboardEntry>[];
    final unique = <String, LeaderboardEntry>{};
    for (final item in value) {
      final entry = LeaderboardEntry.fromJson(item);
      final previous = unique[entry.id];
      if (previous == null || entry.score > previous.score) {
        unique[entry.id] = entry;
      }
    }
    final ranked = unique.values.toList()
      ..sort((a, b) {
        final scoreOrder = b.score.compareTo(a.score);
        return scoreOrder != 0
            ? scoreOrder
            : a.achievedAt.compareTo(b.achievedAt);
      });
    return List<LeaderboardEntry>.unmodifiable(ranked.take(maximum));
  }
}

class DailyBonusState {
  const DailyBonusState({
    this.currentStreak = 0,
    this.longestStreak = 0,
    this.totalClaims = 0,
    this.lastClaimedOn,
  });

  factory DailyBonusState.fromJson(Object? value) {
    final json = _asMap(value);
    final currentStreak = _nonNegativeInt(
      json['currentStreak'] ?? json['streak'],
    );
    return DailyBonusState(
      currentStreak: currentStreak,
      longestStreak: _nonNegativeInt(
        json['longestStreak'],
        fallback: currentStreak,
      ).clamp(currentStreak, 1000000),
      totalClaims: _nonNegativeInt(json['totalClaims']),
      lastClaimedOn: _optionalCalendarDate(
        json['lastClaimedOn'] ?? json['lastClaimDate'],
      ),
    );
  }

  final int currentStreak;
  final int longestStreak;
  final int totalClaims;

  /// Stored as a local calendar day; time-of-day is always midnight.
  final DateTime? lastClaimedOn;

  bool canClaimOn(DateTime now) {
    final today = _calendarDate(now);
    return lastClaimedOn == null || !_sameCalendarDay(lastClaimedOn!, today);
  }

  DailyBonusClaim claim(
    DateTime now, {
    int baseCoins = 30,
    int coinsPerDay = 10,
    int maximumCoins = 100,
    int gemMilestoneInterval = 5,
  }) {
    final today = _calendarDate(now);
    if (!canClaimOn(today)) {
      return DailyBonusClaim(
        state: this,
        result: DailyBonusResult(
          wasAwarded: false,
          streak: currentStreak,
          coinsAwarded: 0,
          gemsAwarded: 0,
          claimedOn: today,
        ),
      );
    }

    final yesterday = today.subtract(const Duration(days: 1));
    final consecutive =
        lastClaimedOn != null && _sameCalendarDay(lastClaimedOn!, yesterday);
    final nextStreak = consecutive ? currentStreak + 1 : 1;
    final safeBase = baseCoins < 0 ? 0 : baseCoins;
    final safeStep = coinsPerDay < 0 ? 0 : coinsPerDay;
    final safeMaximum = maximumCoins < safeBase ? safeBase : maximumCoins;
    final coinReward = (safeBase + ((nextStreak - 1) * safeStep)).clamp(
      safeBase,
      safeMaximum,
    );
    final gemReward =
        gemMilestoneInterval > 0 && nextStreak % gemMilestoneInterval == 0
        ? 1
        : 0;
    final state = DailyBonusState(
      currentStreak: nextStreak,
      longestStreak: nextStreak > longestStreak ? nextStreak : longestStreak,
      totalClaims: totalClaims + 1,
      lastClaimedOn: today,
    );
    return DailyBonusClaim(
      state: state,
      result: DailyBonusResult(
        wasAwarded: true,
        streak: nextStreak,
        coinsAwarded: coinReward,
        gemsAwarded: gemReward,
        claimedOn: today,
      ),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'currentStreak': currentStreak,
    'longestStreak': longestStreak,
    'totalClaims': totalClaims,
    'lastClaimedOn': lastClaimedOn == null
        ? null
        : _calendarKey(lastClaimedOn!),
  };
}

class DailyBonusResult {
  const DailyBonusResult({
    required this.wasAwarded,
    required this.streak,
    required this.coinsAwarded,
    required this.gemsAwarded,
    required this.claimedOn,
  });

  factory DailyBonusResult.fromJson(Object? value) {
    final json = _asMap(value);
    return DailyBonusResult(
      wasAwarded: _safeBool(json['wasAwarded'] ?? json['awarded']),
      streak: _nonNegativeInt(json['streak']),
      coinsAwarded: _nonNegativeInt(json['coinsAwarded'] ?? json['coins']),
      gemsAwarded: _nonNegativeInt(json['gemsAwarded'] ?? json['gems']),
      claimedOn:
          _optionalCalendarDate(json['claimedOn']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  final bool wasAwarded;
  final int streak;
  final int coinsAwarded;
  final int gemsAwarded;
  final DateTime claimedOn;

  bool get isMilestone => gemsAwarded > 0;

  Map<String, Object> toJson() => <String, Object>{
    'wasAwarded': wasAwarded,
    'streak': streak,
    'coinsAwarded': coinsAwarded,
    'gemsAwarded': gemsAwarded,
    'claimedOn': _calendarKey(claimedOn),
  };
}

class DailyBonusClaim {
  const DailyBonusClaim({required this.state, required this.result});

  final DailyBonusState state;
  final DailyBonusResult result;
}

Map<String, Object?> _asMap(Object? value) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) {
    return <String, Object?>{
      for (final entry in value.entries)
        if (entry.key is String) entry.key as String: entry.value,
    };
  }
  return const <String, Object?>{};
}

String _safeText(
  Object? value, {
  required String fallback,
  int maxLength = 80,
}) {
  final text = value is String ? value.trim() : '';
  if (text.isEmpty) return fallback;
  return text.length <= maxLength ? text : text.substring(0, maxLength);
}

String _safeId(Object? value, {required String fallback}) {
  final text = _safeText(value, fallback: fallback, maxLength: 64);
  final normalized = text
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9_-]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');
  return normalized.isEmpty ? fallback : normalized;
}

int _nonNegativeInt(Object? value, {int fallback = 0}) {
  final parsed = switch (value) {
    int number => number,
    num number when number.isFinite => number.round(),
    String text => num.tryParse(text.trim())?.round(),
    _ => null,
  };
  return parsed == null || parsed < 0 ? fallback : parsed;
}

int _positiveInt(Object? value, {required int fallback}) {
  final parsed = _nonNegativeInt(value, fallback: fallback);
  return parsed > 0 ? parsed : fallback;
}

bool _safeBool(Object? value) => switch (value) {
  true || 1 || '1' || 'true' => true,
  _ => false,
};

T _enumByName<T extends Enum>(List<T> values, Object? value, T fallback) {
  if (value is! String) return fallback;
  return values.cast<T?>().firstWhere(
        (item) => item?.name == value,
        orElse: () => fallback,
      ) ??
      fallback;
}

DateTime? _optionalDateTime(Object? value) {
  if (value is DateTime) return value.toUtc();
  if (value is int && value >= 0) {
    return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
  }
  if (value is! String || value.trim().isEmpty) return null;
  return DateTime.tryParse(value.trim())?.toUtc();
}

DateTime? _optionalCalendarDate(Object? value) {
  final parsed = value is DateTime
      ? value
      : value is String
      ? DateTime.tryParse(value.trim())
      : null;
  return parsed == null ? null : _calendarDate(parsed);
}

DateTime _calendarDate(DateTime value) =>
    DateTime(value.year, value.month, value.day);

bool _sameCalendarDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String _calendarKey(DateTime value) {
  final date = _calendarDate(value);
  return '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}
