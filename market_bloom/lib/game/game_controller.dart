import 'dart:async';
import 'dart:collection';
import 'dart:math';

import 'package:flutter/material.dart';

import '../services/game_storage.dart';
import '../services/monetization_service.dart';
import 'game_models.dart';
import 'meta_models.dart';

class GameController extends ChangeNotifier {
  GameController({
    required this.storage,
    required this.monetization,
    Random? random,
    DateTime Function()? now,
  }) : _random = random ?? Random(),
       _now = now ?? DateTime.now;

  static const stockZone = Offset(0.16, 0.79);
  static const shelfZone = Offset(0.43, 0.47);
  static const checkoutZone = Offset(0.77, 0.25);
  static const entrance = Offset(0.5, 0.04);
  static const exit = Offset(0.62, -0.08);

  final GameStorage storage;
  final MonetizationService monetization;
  final Random _random;
  final DateTime Function() _now;

  Offset playerPosition = const Offset(0.5, 0.72);
  Offset movement = Offset.zero;
  final List<MarketCustomer> customers = [];

  int coins = 25;
  int gems = 3;
  int carried = 0;
  int shelfStock = 0;
  int totalSales = 0;
  int totalCoinsEarned = 0;
  int stockedTotal = 0;
  int upgradesBought = 0;
  int questStage = 0;
  int questBaseline = 0;
  int bagLevel = 1;
  int shelfLevel = 1;
  int priceLevel = 1;
  int speedLevel = 1;
  int offlineEarnings = 0;
  int totalActions = 0;
  int highestBalance = 25;
  int highestScore = 0;
  double totalPlaySeconds = 0;
  bool adsRemoved = false;
  bool muted = false;
  bool onboardingComplete = false;

  bool initialized = false;
  bool paused = false;
  bool rewardInProgress = false;
  bool storePurchaseInProgress = false;

  double _customerSpawnTimer = 0.8;
  double _stockActionTimer = 0;
  double _shelfActionTimer = 0;
  double _saveTimer = 0;
  double _historyTimer = 0;
  int _customerId = 0;
  bool _dirty = false;
  bool _saveRequested = false;
  Future<void>? _saveInProgress;
  Timer? _saveDebounce;

  DailyBonusState dailyBonus = const DailyBonusState();
  DailyBonusResult? pendingDailyBonus;
  List<AchievementProgress> _achievementProgress =
      const <AchievementProgress>[];
  List<PerformanceSample> _performanceHistory = const <PerformanceSample>[];
  List<LeaderboardEntry> _leaderboard = const <LeaderboardEntry>[];
  final Queue<AchievementDefinition> _achievementUnlocks =
      Queue<AchievementDefinition>();

  int get bagCapacity => 3 + bagLevel;
  int get shelfCapacity => 4 + shelfLevel * 2;
  int get itemPrice => 4 + priceLevel * 2;
  double get playerSpeed => 0.22 + speedLevel * 0.018;
  int get storeLevel => 1 + totalSales ~/ 8 + upgradesBought ~/ 4;
  int get salesIntoLevel => totalSales % 8;
  double get levelProgress => salesIntoLevel / 8;
  int get instantAdReward => max(40, itemPrice * 8);
  bool get isMonetizationPreview => monetization.isPreview;
  bool get storePurchasesAvailable => monetization.storeAvailable;
  int get businessScore =>
      totalCoinsEarned +
      totalSales * 25 +
      storeLevel * 100 +
      upgradesBought * 80 +
      dailyBonus.currentStreak * 30;
  Duration get totalPlayTime => Duration(seconds: totalPlaySeconds.floor());
  List<AchievementProgress> get achievementProgress =>
      List<AchievementProgress>.unmodifiable(_achievementProgress);
  List<PerformanceSample> get performanceHistory =>
      List<PerformanceSample>.unmodifiable(_performanceHistory);
  List<LeaderboardEntry> get leaderboard =>
      List<LeaderboardEntry>.unmodifiable(_leaderboard);
  int get unlockedAchievementCount =>
      _achievementProgress.where((item) => item.isUnlocked).length;
  bool get hasPendingAchievement => _achievementUnlocks.isNotEmpty;

  String? storePrice(StoreProduct product) => monetization.priceFor(product);

  Quest get quest {
    switch (questStage) {
      case 0:
        return Quest(
          title: 'Stock 5 products on the shelf',
          progress: stockedTotal,
          target: 5,
          reward: 25,
        );
      case 1:
        return Quest(
          title: 'Complete 3 sales',
          progress: totalSales,
          target: 3,
          reward: 35,
        );
      case 2:
        return Quest(
          title: 'Buy a business upgrade',
          progress: upgradesBought,
          target: 1,
          reward: 2,
        );
      default:
        final target = 5 + ((questStage - 3) % 4) * 2;
        return Quest(
          title: 'Complete $target more sales',
          progress: totalSales - questBaseline,
          target: target,
          reward: 45 + (questStage - 3) * 8,
        );
    }
  }

  List<UpgradeOffer> get upgrades => [
    UpgradeOffer(
      type: UpgradeType.bag,
      title: 'Bigger Bag',
      subtitle: 'Carry $bagCapacity products',
      level: bagLevel,
      cost: _upgradeCost(35, bagLevel),
      icon: Icons.shopping_bag_rounded,
      color: const Color(0xFFF6A623),
    ),
    UpgradeOffer(
      type: UpgradeType.shelf,
      title: 'Expanded Shelf',
      subtitle: 'Capacity: $shelfCapacity products',
      level: shelfLevel,
      cost: _upgradeCost(45, shelfLevel),
      icon: Icons.shelves,
      color: const Color(0xFF5B8DEF),
    ),
    UpgradeOffer(
      type: UpgradeType.price,
      title: 'Premium Products',
      subtitle: 'Profit per sale: $itemPrice',
      level: priceLevel,
      cost: _upgradeCost(60, priceLevel),
      icon: Icons.workspace_premium_rounded,
      color: const Color(0xFFE85D75),
    ),
    UpgradeOffer(
      type: UpgradeType.speed,
      title: 'Running Shoes',
      subtitle: 'Movement speed +${speedLevel * 8}%',
      level: speedLevel,
      cost: _upgradeCost(40, speedLevel),
      icon: Icons.directions_run_rounded,
      color: const Color(0xFF38B879),
    ),
  ];

  String get interactionHint {
    if (_near(playerPosition, stockZone, 0.13)) {
      return carried >= bagCapacity
          ? 'Bag full — head to the shelf'
          : 'Collecting products from storage';
    }
    if (_near(playerPosition, shelfZone, 0.14)) {
      if (carried == 0) {
        return 'Your bag is empty';
      }
      if (shelfStock >= shelfCapacity) {
        return 'The shelf is full';
      }
      return 'Stocking products on the shelf';
    }
    if (_near(playerPosition, checkoutZone, 0.13)) {
      return 'Customers pay here';
    }
    return 'Use the joystick and keep the shelf stocked';
  }

  Future<void> initialize() async {
    var shouldPersist = false;
    try {
      final saved = await storage.load();
      if (saved != null) {
        _restore(saved);
        final lastSaved = DateTime.tryParse(saved['savedAt'] as String? ?? '');
        if (lastSaved != null) {
          final seconds = _now().difference(lastSaved).inSeconds;
          if (seconds >= 45) {
            final cappedSeconds = min(
              seconds,
              const Duration(hours: 4).inSeconds,
            );
            offlineEarnings = min(
              5000,
              (cappedSeconds / 30 * max(1, itemPrice ~/ 2)).floor(),
            );
          }
        }
      }
      shouldPersist = _applyDailyBonus();
      _recordPerformanceSample(force: _performanceHistory.isEmpty);
      _updateHighs();
      _evaluateAchievements();
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'PoMarket storage',
          context: ErrorDescription('while loading saved progress'),
        ),
      );
    } finally {
      initialized = true;
      if (shouldPersist) {
        await save();
      }
      notifyListeners();
    }
  }

  void setMovement(Offset value) {
    movement = value.distance > 1 ? value / value.distance : value;
  }

  void tick(double dt) {
    if (!initialized || paused || dt <= 0) {
      return;
    }

    final safeDt = min(dt, 0.05);
    final actionsBefore = totalActions;
    final salesBefore = totalSales;
    _updatePlayer(safeDt);
    _updateStations(safeDt);
    _updateCustomers(safeDt);
    totalPlaySeconds += safeDt;
    _dirty = true;

    _customerSpawnTimer -= safeDt;
    if (_customerSpawnTimer <= 0 && customers.length < min(8, 3 + storeLevel)) {
      _spawnCustomer();
      _customerSpawnTimer = max(1.35, 3.2 - storeLevel * 0.12);
    }

    _saveTimer += safeDt;
    _historyTimer += safeDt;
    if (_historyTimer >= 30) {
      _historyTimer = 0;
      _recordPerformanceSample(force: true);
    }
    if (actionsBefore != totalActions || salesBefore != totalSales) {
      _afterProgressChanged();
    }
    if (_saveTimer >= 5) {
      _saveTimer = 0;
      if (_dirty) {
        unawaited(save());
      }
    }
    notifyListeners();
  }

  void _updatePlayer(double dt) {
    if (movement == Offset.zero) {
      return;
    }
    final next = playerPosition + movement * playerSpeed * dt;
    playerPosition = Offset(
      next.dx.clamp(0.06, 0.94),
      next.dy.clamp(0.09, 0.94),
    );
  }

  void _updateStations(double dt) {
    if (_near(playerPosition, stockZone, 0.13) && carried < bagCapacity) {
      _stockActionTimer += dt;
      if (_stockActionTimer >= 0.42) {
        _stockActionTimer = 0;
        carried++;
        totalActions++;
      }
    } else {
      _stockActionTimer = 0;
    }

    if (_near(playerPosition, shelfZone, 0.14) &&
        carried > 0 &&
        shelfStock < shelfCapacity) {
      _shelfActionTimer += dt;
      if (_shelfActionTimer >= 0.28) {
        _shelfActionTimer = 0;
        carried--;
        shelfStock++;
        stockedTotal++;
        totalActions++;
      }
    } else {
      _shelfActionTimer = 0;
    }
  }

  final List<MarketCustomer> _checkoutQueue = [];

  void _updateCustomers(double dt) {
    final removed = <MarketCustomer>[];
    final playerAtCheckout = _near(playerPosition, checkoutZone, 0.13);

    _checkoutQueue.removeWhere(
      (c) =>
          !customers.contains(c) ||
          (c.phase != CustomerPhase.checkout &&
              c.phase != CustomerPhase.paying),
    );

    for (final customer in customers) {
      if (customer.phase == CustomerPhase.shopping) {
        customer.phaseTime += dt;
        if (shelfStock > 0 && customer.phaseTime >= 0.7) {
          shelfStock--;
          customer.hasProduct = true;
          customer.phase = CustomerPhase.checkout;
          customer.phaseTime = 0;
          if (!_checkoutQueue.contains(customer)) {
            _checkoutQueue.add(customer);
          }
        }
      } else if (customer.phase == CustomerPhase.checkout &&
          !_checkoutQueue.contains(customer)) {
        _checkoutQueue.add(customer);
      } else if (customer.phase == CustomerPhase.paying &&
          !_checkoutQueue.contains(customer)) {
        _checkoutQueue.insert(0, customer);
      }
    }

    for (final customer in customers) {
      final queueIndex = _checkoutQueue.indexOf(customer);

      switch (customer.phase) {
        case CustomerPhase.shopping:
          break;
        case CustomerPhase.entering:
        case CustomerPhase.leaving:
          customer.phaseTime += dt;
        case CustomerPhase.checkout:
          break;
        case CustomerPhase.paying:
          if (queueIndex == 0 && playerAtCheckout) {
            customer.phaseTime += dt;
          }
      }

      switch (customer.phase) {
        case CustomerPhase.entering:
          _moveCustomer(customer, shelfZone + const Offset(0.0, -0.11), dt);
          if (_near(customer.position, shelfZone, 0.13)) {
            customer.phase = CustomerPhase.shopping;
            customer.phaseTime = 0;
          }
        case CustomerPhase.shopping:
          break;
        case CustomerPhase.checkout:
          final effectiveIndex = queueIndex >= 0
              ? queueIndex
              : _checkoutQueue.length;
          final queueTarget =
              checkoutZone + Offset(-0.03, 0.10 + effectiveIndex * 0.075);
          _moveCustomer(customer, queueTarget, dt);

          if (queueIndex == 0 &&
              playerAtCheckout &&
              _near(customer.position, queueTarget, 0.04)) {
            customer.phase = CustomerPhase.paying;
            customer.phaseTime = 0;
          }
        case CustomerPhase.paying:
          if (customer.phaseTime >= max(0.45, 1.05 - storeLevel * 0.04)) {
            coins += itemPrice;
            totalCoinsEarned += itemPrice;
            totalSales++;
            totalActions++;
            customer.phase = CustomerPhase.leaving;
            customer.phaseTime = 0;
            _checkoutQueue.remove(customer);
          }
        case CustomerPhase.leaving:
          _moveCustomer(customer, exit, dt);
          if (customer.position.dy < -0.04) {
            removed.add(customer);
            _checkoutQueue.remove(customer);
          }
      }
    }

    customers.removeWhere(removed.contains);
  }

  void _spawnCustomer() {
    const palette = [
      Color(0xFF7957D5),
      Color(0xFFEF6C57),
      Color(0xFF3F88C5),
      Color(0xFFF2B134),
      Color(0xFF2A9D8F),
    ];
    customers.add(
      MarketCustomer(
        id: _customerId++,
        position: entrance + Offset((_random.nextDouble() - 0.5) * 0.08, 0),
        color: palette[_random.nextInt(palette.length)],
      ),
    );
  }

  void _moveCustomer(MarketCustomer customer, Offset target, double dt) {
    final delta = target - customer.position;
    if (delta.distance < 0.004) {
      customer.position = target;
      return;
    }
    final step = min(delta.distance, (0.105 + storeLevel * 0.004) * dt);
    customer.position += delta / delta.distance * step;
  }

  bool buyUpgrade(UpgradeType type) {
    final offer = upgrades.firstWhere((item) => item.type == type);
    if (coins < offer.cost) {
      return false;
    }
    coins -= offer.cost;
    switch (type) {
      case UpgradeType.bag:
        bagLevel++;
      case UpgradeType.shelf:
        shelfLevel++;
      case UpgradeType.price:
        priceLevel++;
      case UpgradeType.speed:
        speedLevel++;
    }
    upgradesBought++;
    totalActions++;
    _afterProgressChanged();
    notifyListeners();
    return true;
  }

  void claimQuest() {
    final current = quest;
    if (!current.completed) {
      return;
    }
    if (questStage == 2) {
      gems += current.reward;
    } else {
      coins += current.reward;
      totalCoinsEarned += current.reward;
    }
    questStage++;
    questBaseline = totalSales;
    totalActions++;
    _afterProgressChanged();
    notifyListeners();
  }

  Future<bool> claimInstantAdReward() async {
    if (rewardInProgress) {
      return false;
    }
    rewardInProgress = true;
    notifyListeners();
    final completed = await monetization.showRewardedAd(
      RewardPlacement.instantCoins,
    );
    if (completed) {
      coins += instantAdReward;
      totalCoinsEarned += instantAdReward;
      totalActions++;
      _afterProgressChanged(immediate: true);
    }
    rewardInProgress = false;
    await save();
    notifyListeners();
    return completed;
  }

  Future<bool> claimOfflineReward({required bool doubled}) async {
    if (offlineEarnings <= 0 || rewardInProgress) {
      return false;
    }
    var multiplier = 1;
    if (doubled) {
      rewardInProgress = true;
      notifyListeners();
      final completed = await monetization.showRewardedAd(
        RewardPlacement.doubleOfflineEarnings,
      );
      rewardInProgress = false;
      if (!completed) {
        notifyListeners();
        return false;
      }
      multiplier = 2;
    }
    final reward = offlineEarnings * multiplier;
    coins += reward;
    totalCoinsEarned += reward;
    offlineEarnings = 0;
    totalActions++;
    _afterProgressChanged(immediate: true);
    await save();
    notifyListeners();
    return true;
  }

  Future<bool> purchase(StoreProduct product) {
    return monetization.purchase(product);
  }

  Future<bool> purchaseStoreProduct(StoreProduct product) async {
    if (storePurchaseInProgress ||
        !storePurchasesAvailable ||
        (product == StoreProduct.noAds && adsRemoved)) {
      return false;
    }
    storePurchaseInProgress = true;
    notifyListeners();
    final purchased = await monetization.purchase(product);
    if (purchased) {
      switch (product) {
        case StoreProduct.noAds:
          adsRemoved = true;
        case StoreProduct.coinPack:
          coins += 1000;
        case StoreProduct.starterPack:
          coins += 500;
          gems += 20;
          bagLevel++;
          shelfLevel++;
      }
      totalActions++;
      _afterProgressChanged(immediate: true);
    }
    storePurchaseInProgress = false;
    await save();
    notifyListeners();
    return purchased;
  }

  Future<void> save() {
    _saveRequested = true;
    final activeSave = _saveInProgress;
    if (activeSave != null) {
      return activeSave;
    }

    final completer = Completer<void>();
    _saveInProgress = completer.future;
    unawaited(_flushSaves(completer));
    return completer.future;
  }

  Future<void> _flushSaves(Completer<void> completer) async {
    try {
      while (_saveRequested) {
        _saveRequested = false;
        _updateHighs();
        await storage.save(_saveSnapshot());
        _dirty = false;
      }
      completer.complete();
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'PoMarket storage',
          context: ErrorDescription('while saving player progress'),
        ),
      );
      completer.completeError(error, stackTrace);
    } finally {
      _saveInProgress = null;
      if (_saveRequested) {
        unawaited(save());
      }
    }
  }

  Map<String, dynamic> _saveSnapshot() {
    return <String, dynamic>{
      'version': 2,
      'savedAt': _now().toIso8601String(),
      'coins': coins,
      'gems': gems,
      'carried': carried,
      'shelfStock': shelfStock,
      'totalSales': totalSales,
      'totalCoinsEarned': totalCoinsEarned,
      'stockedTotal': stockedTotal,
      'upgradesBought': upgradesBought,
      'questStage': questStage,
      'questBaseline': questBaseline,
      'bagLevel': bagLevel,
      'shelfLevel': shelfLevel,
      'priceLevel': priceLevel,
      'speedLevel': speedLevel,
      'adsRemoved': adsRemoved,
      'totalActions': totalActions,
      'highestBalance': highestBalance,
      'highestScore': highestScore,
      'totalPlaySeconds': totalPlaySeconds,
      'muted': muted,
      'onboardingComplete': onboardingComplete,
      'playerX': playerPosition.dx,
      'playerY': playerPosition.dy,
      'dailyBonus': dailyBonus.toJson(),
      'achievements': _achievementProgress
          .map((item) => item.toJson())
          .toList(growable: false),
      'performanceHistory': _performanceHistory
          .map((item) => item.toJson())
          .toList(growable: false),
      'leaderboard': _leaderboard
          .map((item) => item.toJson())
          .toList(growable: false),
    };
  }

  Future<void> reset() async {
    _saveDebounce?.cancel();
    await storage.clear();
    coins = 25;
    gems = 3;
    carried = 0;
    shelfStock = 0;
    totalSales = 0;
    totalCoinsEarned = 0;
    stockedTotal = 0;
    upgradesBought = 0;
    questStage = 0;
    questBaseline = 0;
    bagLevel = 1;
    shelfLevel = 1;
    priceLevel = 1;
    speedLevel = 1;
    adsRemoved = false;
    offlineEarnings = 0;
    totalActions = 0;
    highestBalance = 25;
    highestScore = 0;
    totalPlaySeconds = 0;
    muted = false;
    onboardingComplete = false;
    dailyBonus = const DailyBonusState();
    pendingDailyBonus = null;
    _achievementProgress = const <AchievementProgress>[];
    _performanceHistory = const <PerformanceSample>[];
    _leaderboard = const <LeaderboardEntry>[];
    _achievementUnlocks.clear();
    customers.clear();
    playerPosition = const Offset(0.5, 0.72);
    _applyDailyBonus();
    _recordPerformanceSample(force: true);
    _updateHighs();
    _evaluateAchievements();
    notifyListeners();
    await save();
  }

  void setMuted(bool value) {
    if (muted == value) {
      return;
    }
    muted = value;
    _markDirty(immediate: true);
    notifyListeners();
  }

  void completeOnboarding() {
    if (onboardingComplete) {
      return;
    }
    onboardingComplete = true;
    _markDirty(immediate: true);
    notifyListeners();
  }

  void replayOnboarding() {
    onboardingComplete = false;
    notifyListeners();
  }

  void acknowledgeDailyBonus() {
    if (pendingDailyBonus == null) {
      return;
    }
    pendingDailyBonus = null;
    notifyListeners();
  }

  AchievementDefinition? takeAchievementUnlock() {
    return _achievementUnlocks.isEmpty
        ? null
        : _achievementUnlocks.removeFirst();
  }

  AchievementProgress progressFor(AchievementDefinition definition) {
    return _achievementProgress.firstWhere(
      (item) => item.achievementId == definition.id,
      orElse: () => AchievementProgress(achievementId: definition.id),
    );
  }

  LeaderboardEntry submitLeaderboardScore(String nickname) {
    _updateHighs();
    final timestamp = _now().toUtc();
    final entry = LeaderboardEntry(
      id: '${timestamp.microsecondsSinceEpoch}-${_random.nextInt(1 << 20).toRadixString(16)}',
      nickname: LeaderboardEntry.sanitizeNickname(nickname),
      score: businessScore,
      achievedAt: timestamp,
      storeLevel: storeLevel,
      totalSales: totalSales,
    );
    _leaderboard = LeaderboardEntry.top(<Object?>[
      ..._leaderboard.map((item) => item.toJson()),
      entry.toJson(),
    ]);
    _recordPerformanceSample(force: true);
    totalActions++;
    _markDirty(immediate: true);
    notifyListeners();
    return entry;
  }

  @visibleForTesting
  void debugSetPlayerPosition(Offset position) {
    playerPosition = position;
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    monetization.dispose();
    super.dispose();
  }

  void _restore(Map<String, dynamic> saved) {
    coins = _readInt(saved, 'coins', 25);
    gems = _readInt(saved, 'gems', 3);
    carried = _readInt(saved, 'carried', 0);
    shelfStock = _readInt(saved, 'shelfStock', 0);
    totalSales = _readInt(saved, 'totalSales', 0);
    totalCoinsEarned = _readInt(saved, 'totalCoinsEarned', 0);
    stockedTotal = _readInt(saved, 'stockedTotal', 0);
    upgradesBought = _readInt(saved, 'upgradesBought', 0);
    questStage = _readInt(saved, 'questStage', 0);
    questBaseline = _readInt(saved, 'questBaseline', 0);
    bagLevel = _readInt(saved, 'bagLevel', 1);
    shelfLevel = _readInt(saved, 'shelfLevel', 1);
    priceLevel = _readInt(saved, 'priceLevel', 1);
    speedLevel = _readInt(saved, 'speedLevel', 1);
    totalActions = _readInt(saved, 'totalActions', 0);
    highestBalance = _readInt(saved, 'highestBalance', coins);
    highestScore = _readInt(saved, 'highestScore', 0);
    totalPlaySeconds = _readDouble(saved, 'totalPlaySeconds', 0);
    adsRemoved = saved['adsRemoved'] is bool
        ? saved['adsRemoved'] as bool
        : false;
    muted = saved['muted'] is bool ? saved['muted'] as bool : false;
    onboardingComplete = saved['onboardingComplete'] is bool
        ? saved['onboardingComplete'] as bool
        : false;
    dailyBonus = DailyBonusState.fromJson(saved['dailyBonus']);
    _achievementProgress = AchievementCatalog.restoreProgress(
      saved['achievements'],
    );
    _performanceHistory = PerformanceSample.restoreList(
      saved['performanceHistory'],
    );
    _leaderboard = LeaderboardEntry.top(saved['leaderboard']);
    final restoredX = _readDouble(saved, 'playerX', 0.5);
    final restoredY = _readDouble(saved, 'playerY', 0.72);
    playerPosition = Offset(
      restoredX.clamp(0.06, 0.94),
      restoredY.clamp(0.09, 0.94),
    );
    carried = carried.clamp(0, bagCapacity);
    shelfStock = shelfStock.clamp(0, shelfCapacity);
  }

  int _readInt(Map<String, dynamic> data, String key, int fallback) {
    final value = data[key];
    return value is num ? value.toInt() : fallback;
  }

  double _readDouble(Map<String, dynamic> data, String key, double fallback) {
    final value = data[key];
    return value is num && value.isFinite ? value.toDouble() : fallback;
  }

  bool _applyDailyBonus() {
    final claim = dailyBonus.claim(_now());
    dailyBonus = claim.state;
    if (!claim.result.wasAwarded) {
      return false;
    }
    pendingDailyBonus = claim.result;
    coins += claim.result.coinsAwarded;
    gems += claim.result.gemsAwarded;
    totalCoinsEarned += claim.result.coinsAwarded;
    _dirty = true;
    return true;
  }

  void _afterProgressChanged({bool immediate = false}) {
    _updateHighs();
    _evaluateAchievements();
    _markDirty(immediate: immediate);
  }

  void _updateHighs() {
    highestBalance = max(highestBalance, coins);
    highestScore = max(highestScore, businessScore);
  }

  void _evaluateAchievements() {
    final previousById = <String, AchievementProgress>{
      for (final progress in _achievementProgress)
        progress.achievementId: progress,
    };
    final evaluated = <AchievementProgress>[];
    for (final definition in AchievementCatalog.all) {
      final previous =
          previousById[definition.id] ??
          AchievementProgress(achievementId: definition.id);
      final next = previous.evaluate(
        definition: definition,
        value: _metricValue(definition.metric),
        now: _now(),
      );
      evaluated.add(next);
      if (!previous.isUnlocked && next.isUnlocked) {
        _achievementUnlocks.add(definition);
      }
    }
    _achievementProgress = List<AchievementProgress>.unmodifiable(evaluated);
  }

  int _metricValue(AchievementMetric metric) {
    return switch (metric) {
      AchievementMetric.totalSales => totalSales,
      AchievementMetric.itemsStocked => stockedTotal,
      AchievementMetric.totalCoinsEarned => totalCoinsEarned,
      AchievementMetric.upgradesPurchased => upgradesBought,
      AchievementMetric.storeLevel => storeLevel,
      AchievementMetric.dailyStreak => dailyBonus.currentStreak,
      AchievementMetric.highestBalance => highestBalance,
      AchievementMetric.totalActions => totalActions,
      AchievementMetric.playTimeMinutes => totalPlaySeconds ~/ 60,
    };
  }

  void _recordPerformanceSample({required bool force}) {
    final now = _now().toUtc();
    if (!force && _performanceHistory.isNotEmpty) {
      final elapsed = now.difference(_performanceHistory.last.recordedAt);
      if (elapsed < const Duration(seconds: 25)) {
        return;
      }
    }
    final samples = <PerformanceSample>[
      ..._performanceHistory,
      PerformanceSample(
        recordedAt: now,
        balance: coins,
        businessScore: businessScore,
        totalSales: totalSales,
        storeLevel: storeLevel,
        totalActions: totalActions,
      ),
    ];
    _performanceHistory = PerformanceSample.restoreList(
      samples.map((item) => item.toJson()).toList(growable: false),
    );
    _dirty = true;
  }

  void _markDirty({bool immediate = false}) {
    _dirty = true;
    _saveDebounce?.cancel();
    _saveDebounce = Timer(
      immediate
          ? const Duration(milliseconds: 80)
          : const Duration(milliseconds: 550),
      () => unawaited(save()),
    );
  }

  int _upgradeCost(int base, int level) {
    return (base * pow(1.55, level - 1)).round();
  }

  bool _near(Offset a, Offset b, double radius) => (a - b).distance <= radius;
}
