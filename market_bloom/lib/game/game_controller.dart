import 'dart:async';
import 'dart:collection';
import 'dart:math';

import 'package:flutter/material.dart';

import '../services/game_storage.dart';
import '../services/monetization_service.dart';
import '../services/sfx/sfx_manager.dart';
import 'game_models.dart';
import 'operating_cost_policy.dart';
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
  static const shelfZone = Offset(0.35, 0.51);
  static const checkoutZone = Offset(0.77, 0.25);
  static const checkout2Zone = Offset(0.58, 0.25);
  static const checkout3Zone = Offset(0.92, 0.25);
  static const primaryCheckoutStationId = 'checkout-1';
  static const checkoutStationIds = <String>[
    'checkout-1',
    'checkout-2',
    'checkout-3',
  ];
  static const checkout2UnlockLevel = 2;
  static const checkout3UnlockLevel = 4;
  static const checkoutQueueGraceSeconds = 2.0;
  static const checkoutRebalanceSeconds = 2.5;
  static const checkoutPatienceWarning = 3.0;
  static const checkoutSatisfactionFloor = 0.2;
  static const bakeryZone = Offset(0.78, 0.76);
  static const stockerPickupZone = Offset(0.24, 0.73);
  static const stockerShelfZone = shelfZone;
  static const entrance = Offset(0.5, 0.04);
  static const exit = Offset(0.62, -0.08);

  final GameStorage storage;
  final MonetizationService monetization;
  final Random _random;
  final DateTime Function() _now;
  final ChangeNotifier _sceneNotifier = ChangeNotifier();
  final ChangeNotifier uiUpdateNotifier = ChangeNotifier();

  Offset playerPosition = const Offset(0.5, 0.72);
  Offset stockerPosition = stockerPickupZone;
  Offset movement = Offset.zero;
  Offset? _movementTarget;
  final List<MarketCustomer> customers = [];
  final List<CheckoutStationState> _checkoutStations =
      <CheckoutStationState>[
        CheckoutStationState(
          id: primaryCheckoutStationId,
          unlocked: true,
          active: true,
        ),
        CheckoutStationState(id: 'checkout-2'),
        CheckoutStationState(id: 'checkout-3'),
      ];
  final Map<String, List<MarketCustomer>> _checkoutQueues =
      <String, List<MarketCustomer>>{
        for (final id in checkoutStationIds) id: <MarketCustomer>[],
      };
  final List<FloatingTextEffect> floatingEffects = [];
  int comboCount = 0;
  double comboTimer = 0.0;

  void spawnFloatingText(
    String text,
    Offset position,
    Color color, {
    double fontSize = 16,
    bool isEmoji = false,
  }) {
    floatingEffects.add(
      FloatingTextEffect(
        text: text,
        position: position,
        color: color,
        fontSize: fontSize,
        isEmoji: isEmoji,
      ),
    );
    if (floatingEffects.length > 30) {
      floatingEffects.removeAt(0);
    }
  }

  void registerComboAction(Offset pos) {
    comboCount++;
    comboTimer = 3.5;
    if (comboCount > 1) {
      spawnFloatingText(
        '🔥 ${comboCount}x COMBO!',
        pos,
        const Color(0xFFFF9F1C),
        fontSize: 18,
      );
    }
  }

  int coins = 25;
  int gems = 3;
  int carried = 0;
  int shelfStock = 0;
  int bakeryReadyStock = 0;
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
  int checkoutLevel = 1;
  int restockLevel = 1;
  int offlineEarnings = 0;
  int totalActions = 0;
  int highestBalance = 25;
  int highestScore = 0;
  double totalPlaySeconds = 0;
  bool adsRemoved = false;
  bool muted = false;
  bool onboardingComplete = false;
  bool _tutorialReplayRequested = false;

  static const shiftDurationSeconds = 90.0;
  static const shiftPreparationSeconds = 8.0;
  static const shiftRushStartSeconds = 42.0;
  static const shiftClosingStartSeconds = 76.0;
  int shiftNumber = 1;
  double shiftElapsedSeconds = 0;
  int shiftSales = 0;
  int shiftRevenue = 0;
  int shiftMissedSales = 0;
  ShiftLedger _shiftLedger = ShiftLedger();
  bool _shiftOperatingCostsApplied = false;
  bool shiftMissionClaimed = false;
  bool fastCheckoutClaimed = false;
  DateTime? _dailyMissionClaimedOn;
  ShiftSummary? pendingShiftSummary;

  bool initialized = false;
  bool paused = false;
  bool rewardInProgress = false;
  bool storePurchaseInProgress = false;
  PurchaseState? lastPurchaseState;

  double _customerSpawnTimer = 0.8;
  double _stockActionTimer = 0;
  double _shelfActionTimer = 0;
  double _bakeryProductionTimer = 0;
  double _bakeryCollectTimer = 0;
  int _stockerLoad = 0;
  DepartmentType? _stockerDepartment;
  DepartmentType? _carriedDepartment;
  DepartmentType _selectedRestockDepartment = DepartmentType.generalGoods;
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
  final Queue<DepartmentType> _departmentUnlocks = Queue<DepartmentType>();
  final Map<StaffRole, StaffMember> _staff = <StaffRole, StaffMember>{};
  final List<DepartmentState> _departments = <DepartmentState>[];
  final List<InventoryDelivery> _pendingDeliveries = <InventoryDelivery>[];
  final Map<String, int> _inventoryByCategory = <String, int>{};
  final Map<DepartmentType, int> _departmentShelfStock =
      <DepartmentType, int>{};
  double _staffTimer = 0;
  double _deliveryTimer = 0;
  DateTime? _lastEmergencyStockAt;
  bool _bakeryActivated = false;
  int _lastObservedStoreLevel = 1;
  bool _restoredInventoryPresent = false;
  final Map<RewardPlacement, DateTime> _rewardLastClaimed =
      <RewardPlacement, DateTime>{};
  DateTime? _rewardClaimDay;
  int _rewardClaimsToday = 0;
  DateTime? _lastRewardedAt;
  DateTime? _lastInterstitialAt;
  DateTime? _interstitialDay;
  int _interstitialsToday = 0;
  final Set<String> _deliveredTransactionIds = <String>{};

  int get bagCapacity => 3 + bagLevel;
  int get shelfCapacity => 4 + shelfLevel * 2;
  int get storageCapacity =>
      20 + shelfLevel * 4 + max(0, activeDepartmentCount - 1) * 8;
  int get itemPrice => 4 + priceLevel * 2;
  double get playerSpeed => 0.22 + speedLevel * 0.018;
  int get storeLevel =>
      1 +
      totalSales ~/ GameBalance.salesPerStoreLevel +
      upgradesBought ~/ GameBalance.upgradesPerStoreLevel;
  int get salesIntoLevel => totalSales % GameBalance.salesPerStoreLevel;
  double get levelProgress => salesIntoLevel / GameBalance.salesPerStoreLevel;
  Offset? get movementTarget => _movementTarget;

  /// Notifies for simulation frames that only need a visual scene repaint.
  ///
  /// GameController listeners remain reserved for discrete UI state changes
  /// so HUDs, menus, and offstage destinations do not rebuild every frame.
  Listenable get scene => _sceneNotifier;
  bool get bakeryUnlocked => isDepartmentUnlocked(DepartmentType.bakery);
  int get stockerCarried => _stockerLoad;
  DepartmentType? get stockerTargetDepartment =>
      _stockerLoad > 0 ? _stockerDepartment : _nextRestockDepartment();
  DepartmentType? get carriedDepartment =>
      carried > 0 ? _carriedDepartment ?? DepartmentType.generalGoods : null;
  DepartmentType get selectedRestockDepartment => _selectedRestockDepartment;
  List<DepartmentType> get unlockedDepartments =>
      DepartmentType.values.where(isDepartmentUnlocked).toList(growable: false);
  int get activeDepartmentCount =>
      DepartmentType.values.where(isDepartmentUnlocked).length;
  int get totalShelfInventory => DepartmentType.values.fold<int>(
    0,
    (total, type) => total + departmentStock(type),
  );
  int get departmentSalesBonus => DepartmentType.values
      .where(isDepartmentUnlocked)
      .fold<int>(
        0,
        (total, type) =>
            total + (DepartmentCatalog.find(type)?.priceBonus ?? 0),
      );
  double get bakeryProductionSeconds {
    final bakerPower = staffProductivity(StaffRole.baker);
    return max(
      2.5,
      GameBalance.bakeryProductionInterval.inMilliseconds / 1000 -
          bakerPower * 0.55,
    );
  }

  Duration get effectiveInventoryOrderDelay {
    final courierPower = staffProductivity(StaffRole.courier);
    return Duration(
      milliseconds: max(
        2000,
        GameBalance.inventoryOrderDelay.inMilliseconds - courierPower * 600,
      ).round(),
    );
  }

  int get customerCapacity =>
      min(12, 3 + storeLevel + staffProductivity(StaffRole.promoter));
  double get customerSpawnInterval => max(
    0.85,
    3.2 - storeLevel * 0.12 - staffProductivity(StaffRole.promoter) * 0.15,
  );
  ShiftPhase get shiftPhase {
    if (pendingShiftSummary != null) {
      return ShiftPhase.summary;
    }
    if (shiftElapsedSeconds < shiftPreparationSeconds) {
      return ShiftPhase.preparation;
    }
    if (shiftElapsedSeconds < shiftRushStartSeconds) {
      return ShiftPhase.open;
    }
    if (shiftElapsedSeconds < shiftClosingStartSeconds) {
      return ShiftPhase.rush;
    }
    return ShiftPhase.closing;
  }

  bool get rushActive => shiftPhase == ShiftPhase.rush;

  MarketEventType get activeMarketEvent {
    if (rushActive) {
      return MarketEventType.rushHour;
    }
    if (customers.any(
      (customer) => customer.isVip && customer.phase != CustomerPhase.leaving,
    )) {
      return MarketEventType.vipCustomer;
    }
    if (shiftElapsedSeconds >= 18 && shiftElapsedSeconds < 24) {
      return MarketEventType.fastCheckout;
    }
    return MarketEventType.none;
  }

  bool get fastCheckoutActive =>
      activeMarketEvent == MarketEventType.fastCheckout;

  int get shiftMissionTarget => 5;
  int get shiftMissionProgress => min(shiftMissionTarget, shiftSales);
  bool get shiftMissionCompleted => shiftSales >= shiftMissionTarget;
  bool get dailyMissionCompleted =>
      totalSales > 0 && averageCustomerSatisfaction >= 0.8;
  bool get dailyMissionClaimed =>
      _dailyMissionClaimedOn != null &&
      _sameCalendarDay(_dailyMissionClaimedOn!, _now());

  ShiftLedger get shiftLedger => _shiftLedger.snapshot();

  void recordSale(int amount) {
    _shiftLedger.recordSale(amount);
    if (amount > 0) _dirty = true;
  }

  void recordStockOrderCost(int amount) {
    _shiftLedger.recordStockOrderCost(amount);
    if (amount > 0) _dirty = true;
  }

  void recordBonus(int amount) {
    _shiftLedger.recordBonus(amount);
    if (amount > 0) _dirty = true;
  }

  void recordMissedSaleEstimate(int amount) {
    _shiftLedger.recordMissedSaleEstimate(amount);
    if (amount > 0) _dirty = true;
  }

  void recordOperatingCost(
    int amount, {
    ShiftOperatingCostType type = ShiftOperatingCostType.department,
  }) {
    _shiftLedger.recordOperatingCost(amount, type: type);
    if (amount > 0) _dirty = true;
  }

  int get projectedShiftPayroll =>
      OperatingCostPolicy.totalPayroll(staffMembers);

  int get projectedDepartmentOperatingCosts =>
      OperatingCostPolicy.totalDepartmentOperatingCosts(_departments);

  bool get shiftOperatingCostsApplied => _shiftOperatingCostsApplied;

  void _applyShiftOperatingCostsOnce() {
    if (_shiftOperatingCostsApplied) return;
    final payroll = projectedShiftPayroll;
    final departmentCosts = projectedDepartmentOperatingCosts;
    if (payroll > 0) {
      recordOperatingCost(payroll, type: ShiftOperatingCostType.payroll);
    }
    if (departmentCosts > 0) {
      recordOperatingCost(
        departmentCosts,
        type: ShiftOperatingCostType.department,
      );
    }
    coins -= payroll + departmentCosts;
    _shiftOperatingCostsApplied = true;
    _dirty = true;
  }

  double get shiftProgress =>
      (shiftElapsedSeconds / shiftDurationSeconds).clamp(0, 1);

  double get averageCustomerSatisfaction {
    if (customers.isEmpty) {
      return 1;
    }
    return customers.fold<double>(
          0,
          (total, customer) => total + customer.satisfaction,
        ) /
        customers.length;
  }

  List<CheckoutStationState> get checkoutStations =>
      List<CheckoutStationState>.unmodifiable(_checkoutStations);

  List<MarketCustomer> checkoutQueueFor(String checkoutStationId) =>
      List<MarketCustomer>.unmodifiable(
        _checkoutQueues[checkoutStationId] ?? const <MarketCustomer>[],
      );

  bool checkoutStationHasCashier(String checkoutStationId) =>
      _cashierAtCheckoutStation(checkoutStationId);

  bool checkoutStationIsOperational(String checkoutStationId) {
    final station = _checkoutStations.where(
      (item) => item.id == checkoutStationId,
    );
    return station.isNotEmpty &&
        station.first.unlocked &&
        station.first.active &&
        (_playerAtCheckoutStation(checkoutStationId) ||
            _cashierAtCheckoutStation(checkoutStationId));
  }

  bool setCheckoutStationActive(String checkoutStationId, bool active) {
    final stationIndex = _checkoutStations.indexWhere(
      (station) => station.id == checkoutStationId,
    );
    if (stationIndex < 0) {
      return false;
    }
    final station = _checkoutStations[stationIndex];
    if (!station.unlocked ||
        station.id == primaryCheckoutStationId ||
        station.active == active) {
      return false;
    }
    station.active = active;
    unawaited(active ? SfxManager.instance.registerOpen() : SfxManager.instance.registerClose());
    if (!active) _rebalanceCheckoutQueues(force: true);
    _markDirty(immediate: true);
    notifyListeners();
    return true;
  }

  // Compatibility view for the original checkout used by the current UI.
  List<MarketCustomer> get checkoutQueue =>
      checkoutQueueFor(primaryCheckoutStationId);

  List<Offset> get checkoutQueueSlots => List<Offset>.generate(
    checkoutQueue.length,
    (index) => checkoutZone + Offset(-0.03, 0.10 + index * 0.085),
    growable: false,
  );
  bool get hasPendingGeneralDelivery => _pendingDeliveries.any(
    (delivery) => delivery.category.toLowerCase() == 'general',
  );
  bool get canQuickRestock {
    final pendingQuantity = _pendingDeliveries.fold<int>(
      0,
      (sum, delivery) => sum + delivery.quantity,
    );
    return inventoryFor('General') == 0 &&
        !hasPendingGeneralDelivery &&
        coins >= GameBalance.quickRestockCost &&
        totalStoredInventory +
                pendingQuantity +
                GameBalance.quickRestockQuantity <=
            storageCapacity;
  }

  double get cashierCheckoutSeconds {
    final staffBonus = max(0, staffProductivity(StaffRole.cashier) - 1) * 0.07;
    final upgradeBonus = max(0, checkoutLevel - 1) * 0.09;
    return max(
      GameBalance.minimumCheckoutSeconds,
      GameBalance.baseCheckoutSeconds - staffBonus - upgradeBonus,
    );
  }

  int get totalStoredInventory =>
      _inventoryByCategory.values.fold<int>(0, (sum, value) => sum + value);
  bool get canClaimEmergencyStock {
    if (coins >= GameBalance.quickRestockCost ||
        carried > 0 ||
        totalShelfInventory > 0 ||
        totalStoredInventory > 0 ||
        _pendingDeliveries.isNotEmpty) {
      return false;
    }
    final lastClaim = _lastEmergencyStockAt;
    return lastClaim == null ||
        _now().difference(lastClaim) >= GameBalance.emergencyStockCooldown;
  }

  int get instantAdReward => max(40, itemPrice * 8);
  bool get isMonetizationPreview => monetization.isPreview;
  bool get storePurchasesAvailable => monetization.storeAvailable;
  bool get rewardedAdsAvailable => monetization.rewardedAdsAvailable;
  int get rewardClaimsToday => _rewardClaimsToday;
  int get rewardDailyLimit => MonetizationPolicy.rewardedDailyLimit;
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
  int get pendingDeliveryCount => _pendingDeliveries.length;
  List<DepartmentState> get departments =>
      List<DepartmentState>.unmodifiable(_departments);

  Offset departmentZone(DepartmentType type) =>
      DepartmentCatalog.find(type)?.displayZone ?? shelfZone;

  String departmentCategory(DepartmentType type) =>
      DepartmentCatalog.find(type)?.category ?? 'General';

  int departmentStock(DepartmentType type) =>
      type == DepartmentType.generalGoods
      ? max(0, shelfStock)
      : max(0, _departmentShelfStock[type] ?? 0);

  int departmentCapacity(DepartmentType type) {
    if (type == DepartmentType.generalGoods) {
      return shelfCapacity;
    }
    final definition = DepartmentCatalog.find(type);
    final level = max(1, _departmentFor(type)?.level ?? 1);
    return max(1, (definition?.baseShelfCapacity ?? 4) + (level - 1) * 2);
  }

  int departmentStorage(DepartmentType type) =>
      inventoryFor(departmentCategory(type));

  int departmentItemPrice(DepartmentType type) {
    final definition = DepartmentCatalog.find(type);
    final level = max(1, _departmentFor(type)?.level ?? 1);
    return itemPrice + (definition?.priceBonus ?? 0) + max(0, level - 1) * 2;
  }

  double departmentDemand(DepartmentType type) {
    final level = max(1, _departmentFor(type)?.level ?? 1);
    return (1.04 - max(0, priceLevel - 1) * 0.055 + (level - 1) * 0.012).clamp(
      0.55,
      1.08,
    );
  }

  int departmentEstimatedProfit(DepartmentType type) =>
      max(1, departmentItemPrice(type) - 2 - max(0, priceLevel - 1));

  int departmentUpgradeCost(DepartmentType type) {
    final definition = DepartmentCatalog.find(type);
    final level = max(1, _departmentFor(type)?.level ?? 1);
    return 110 + level * 85 + (definition?.unlockCost ?? 0) ~/ 8;
  }

  bool hasPendingDepartmentDelivery(DepartmentType type) {
    final category = departmentCategory(type).toLowerCase();
    return _pendingDeliveries.any(
      (delivery) => delivery.category.toLowerCase() == category,
    );
  }

  bool canOrderDepartmentStock(DepartmentType type) {
    final definition = DepartmentCatalog.find(type);
    if (definition == null ||
        !isDepartmentUnlocked(type) ||
        hasPendingDepartmentDelivery(type) ||
        coins < definition.orderCost) {
      return false;
    }
    final pendingQuantity = _pendingDeliveries.fold<int>(
      0,
      (sum, delivery) => sum + delivery.quantity,
    );
    return totalStoredInventory + pendingQuantity + definition.orderQuantity <=
        storageCapacity;
  }

  InventoryDelivery? placeDepartmentOrder(DepartmentType type) {
    final definition = DepartmentCatalog.find(type);
    if (definition == null || !canOrderDepartmentStock(type)) {
      return null;
    }
    return placeInventoryOrder(
      definition.category,
      definition.orderQuantity,
      cost: definition.orderCost,
    );
  }

  bool selectRestockDepartment(DepartmentType type) {
    if (!isDepartmentUnlocked(type)) {
      return false;
    }
    _selectedRestockDepartment = type;
    _markDirty(immediate: true);
    notifyListeners();
    return true;
  }

  bool upgradeDepartment(DepartmentType type) {
    final state = _departmentFor(type);
    if (state == null ||
        !state.unlocked ||
        state.level >= 10 ||
        coins < departmentUpgradeCost(type)) {
      return false;
    }
    coins -= departmentUpgradeCost(type);
    state.level++;
    upgradesBought++;
    totalActions++;
    _afterProgressChanged(immediate: true);
    notifyListeners();
    return true;
  }

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
    UpgradeOffer(
      type: UpgradeType.checkout,
      title: 'Checkout Speed',
      subtitle: '${cashierCheckoutSeconds.toStringAsFixed(2)}s per customer',
      level: checkoutLevel,
      cost: _upgradeCost(80, checkoutLevel),
      icon: Icons.payments_rounded,
      color: const Color(0xFF8B66D8),
    ),
    UpgradeOffer(
      type: UpgradeType.restock,
      title: 'Restock Flow',
      subtitle: 'Keep shelves filled smoothly',
      level: restockLevel,
      cost: _upgradeCost(75, restockLevel),
      icon: Icons.local_shipping_rounded,
      color: const Color(0xFF1FA8A8),
    ),
  ];

  String get interactionHint {
    if (_near(playerPosition, stockZone, 0.13)) {
      final pickup = _manualPickupDepartment();
      if (pickup == null) {
        return 'Storage is empty — order more stock';
      }
      return carried >= bagCapacity
          ? 'Bag full — head to ${departmentCategory(carriedDepartment!)}'
          : 'Collecting ${departmentCategory(pickup)} from storage';
    }
    for (final type in unlockedDepartments) {
      if (_near(playerPosition, departmentZone(type), 0.13)) {
        if (carried == 0) {
          return '${departmentCategory(type)} display';
        }
        if (carriedDepartment != type) {
          return 'This crate belongs in ${departmentCategory(carriedDepartment!)}';
        }
        if (departmentStock(type) >= departmentCapacity(type)) {
          return 'The ${departmentCategory(type)} display is full';
        }
        return 'Stocking ${departmentCategory(type)}';
      }
    }
    if (_checkoutStations.any(
      (station) =>
          station.unlocked &&
          station.active &&
          _near(playerPosition, checkoutStationZone(station.id), 0.13),
    )) {
      return 'Customers pay here';
    }
    return '';
  }

  Future<void> initialize() async {
    var shouldPersist = false;
    try {
      final saved = await storage.load();
      if (saved != null) {
        _restore(saved);
        final savedAt = saved['savedAt'];
        final lastSaved = DateTime.tryParse(savedAt is String ? savedAt : '');
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
      _bootstrapSystems();
      _lastObservedStoreLevel = storeLevel;
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
    _movementTarget = null;
    movement = value.distance > 1 ? value / value.distance : value;
  }

  void moveTo(Offset target) {
    _movementTarget = Offset(
      target.dx.clamp(0.06, 0.94),
      target.dy.clamp(0.09, 0.94),
    );
  }

  void clearMovementTarget() {
    _movementTarget = null;
    movement = Offset.zero;
  }

  void tick(double dt) {
    if (!initialized || paused || dt <= 0) {
      return;
    }

    final safeDt = min(dt, 0.05);
    final actionsBefore = totalActions;
    final phaseBefore = shiftPhase;
    _updateShift(safeDt);
    _updatePlayer(safeDt);
    _updateStations(safeDt);
    _updateCustomers(safeDt);
    totalPlaySeconds += safeDt;
    _dirty = true;

    if (floatingEffects.isNotEmpty) {
      for (var i = floatingEffects.length - 1; i >= 0; i--) {
        final effect = floatingEffects[i];
        effect.elapsed += safeDt;
        if (effect.isExpired) {
          floatingEffects.removeAt(i);
        }
      }
    }

    if (comboTimer > 0) {
      comboTimer -= safeDt;
      if (comboTimer <= 0) {
        comboCount = 0;
      }
    }

    _customerSpawnTimer -= safeDt * (rushActive ? 1.35 : 1);
    if (_customerSpawnTimer <= 0 && customers.length < customerCapacity) {
      _spawnCustomer();
      _customerSpawnTimer = customerSpawnInterval;
    }

    _saveTimer += safeDt;
    _historyTimer += safeDt;
    if (_historyTimer >= 30) {
      _historyTimer = 0;
      _recordPerformanceSample(force: true);
    }
    if (actionsBefore != totalActions) {
      _afterProgressChanged();
    }
    if (_saveTimer >= 5) {
      _saveTimer = 0;
      if (_dirty) {
        unawaited(save());
      }
    }
    // Keep per-frame animation on a paint-only channel. Normal controller
    // listeners are notified only when UI-visible state actually changes.
    _sceneNotifier.notifyListeners();

    // Most state changes are covered by the _afterProgressChanged call
    // earlier in the tick. This handles the remaining state changes that
    // can occur without an "action".
    if (phaseBefore != shiftPhase) {
      notifyListeners();
    }
  }

  void _updateShift(double dt) {
    if (pendingShiftSummary != null) {
      return;
    }
    shiftElapsedSeconds = min(shiftDurationSeconds, shiftElapsedSeconds + dt);
    if (shiftElapsedSeconds >= shiftDurationSeconds) {
      _applyShiftOperatingCostsOnce();
      pendingShiftSummary = ShiftSummary(
        shiftNumber: shiftNumber,
        sales: shiftSales,
        revenue: shiftRevenue,
        missedSales: shiftMissedSales,
        satisfaction: averageCustomerSatisfaction,
        xp: shiftSales * 2 + max(0, 10 - shiftMissedSales),
        stockRemaining: totalShelfInventory + totalStoredInventory,
        ledger: _shiftLedger,
      );
      paused = true;
      _markDirty(immediate: true);
    }
  }

  void startNextShift() {
    shiftNumber++;
    shiftElapsedSeconds = 0;
    shiftSales = 0;
    shiftRevenue = 0;
    shiftMissedSales = 0;
    _shiftLedger = ShiftLedger();
    _shiftOperatingCostsApplied = false;
    shiftMissionClaimed = false;
    fastCheckoutClaimed = false;
    pendingShiftSummary = null;
    paused = false;
    _markDirty(immediate: true);
    notifyListeners();
  }

  bool claimShiftMission() {
    if (!shiftMissionCompleted || shiftMissionClaimed) {
      return false;
    }
    shiftMissionClaimed = true;
    coins += 20;
    totalCoinsEarned += 20;
    recordBonus(20);
    totalActions++;
    _afterProgressChanged(immediate: true);
    notifyListeners();
    return true;
  }

  bool claimDailyMission() {
    if (!dailyMissionCompleted || dailyMissionClaimed) {
      return false;
    }
    _dailyMissionClaimedOn = _now();
    coins += 15;
    totalCoinsEarned += 15;
    recordBonus(15);
    totalActions++;
    _afterProgressChanged(immediate: true);

    return true;
  }

  bool claimFastCheckoutBonus() {
    if (!fastCheckoutActive ||
        fastCheckoutClaimed ||
        !_near(playerPosition, checkoutZone, 0.13)) {
      return false;
    }
    fastCheckoutClaimed = true;
    coins += 8;
    totalCoinsEarned += 8;
    recordBonus(8);
    totalActions++;
    _afterProgressChanged(immediate: true);

    return true;
  }

  void _updatePlayer(double dt) {
    final target = _movementTarget;
    if (target != null) {
      final delta = target - playerPosition;
      final maxStep = playerSpeed * dt;
      if (delta.distance <= max(maxStep, 0.006)) {
        playerPosition = target;
        _movementTarget = null;
        movement = Offset.zero;
        return;
      }
      movement = delta / delta.distance;
    }

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
    if (bakeryUnlocked) {
      if (bakeryReadyStock < GameBalance.bakeryReadyCapacity) {
        _bakeryProductionTimer += dt;
        if (_bakeryProductionTimer >= bakeryProductionSeconds) {
          _bakeryProductionTimer = 0;
          bakeryReadyStock++;
          totalActions++;
          unawaited(SfxManager.instance.bakeryReady());
        }
      } else {
        _bakeryProductionTimer = 0;
      }

      if (_near(playerPosition, bakeryZone, 0.13) &&
          bakeryReadyStock > 0 &&
          carried < bagCapacity &&
          (carried == 0 || carriedDepartment == DepartmentType.bakery)) {
        _bakeryCollectTimer += dt;
        if (_bakeryCollectTimer >= GameBalance.bakeryCollectionSeconds) {
          _bakeryCollectTimer = 0;
          bakeryReadyStock--;
          _carriedDepartment = DepartmentType.bakery;
          carried++;
          totalActions++;
        }
      } else {
        _bakeryCollectTimer = 0;
      }
    } else {
      _bakeryProductionTimer = 0;
      _bakeryCollectTimer = 0;
    }

    final pickupDepartment = carried > 0
        ? carriedDepartment
        : _manualPickupDepartment();
    if (_near(playerPosition, stockZone, 0.13) &&
        pickupDepartment != null &&
        carried < bagCapacity &&
        departmentStorage(pickupDepartment) > 0 &&
        (carried == 0 || carriedDepartment == pickupDepartment)) {
      _stockActionTimer += dt;
      if (_stockActionTimer >=
          max(0.18, 0.42 - max(0, restockLevel - 1) * 0.025)) {
        _stockActionTimer = 0;
        final category = departmentCategory(pickupDepartment);
        _inventoryByCategory[category] = inventoryFor(category) - 1;
        _carriedDepartment = pickupDepartment;
        carried++;
        totalActions++;
        unawaited(SfxManager.instance.pickup());
      }
    } else {
      _stockActionTimer = 0;
    }

    final carriedType = carriedDepartment;
    if (carriedType != null &&
        _near(playerPosition, departmentZone(carriedType), 0.13) &&
        departmentStock(carriedType) < departmentCapacity(carriedType)) {
      _shelfActionTimer += dt;
      if (_shelfActionTimer >=
          max(0.12, 0.28 - max(0, restockLevel - 1) * 0.02)) {
        _shelfActionTimer = 0;
        carried--;
        _setDepartmentStock(carriedType, departmentStock(carriedType) + 1);
        if (carried == 0) {
          _carriedDepartment = null;
        }
        stockedTotal++;
        totalActions++;
        unawaited(SfxManager.instance.restock());
      }
    } else {
      _shelfActionTimer = 0;
    }

    _updateStocker(dt);

    _staffTimer += dt;
    if (_staffTimer >= 1.2) {
      _staffTimer = 0;
      _applyStaffAutomation();
    }

    _deliveryTimer += dt;
    if (_deliveryTimer >= 5) {
      _deliveryTimer = 0;
      _advancePendingDeliveries();
    }
  }

  void _setDepartmentStock(DepartmentType type, int value) {
    final clamped = value.clamp(0, departmentCapacity(type));
    if (type == DepartmentType.generalGoods) {
      shelfStock = clamped;
      return;
    }
    _departmentShelfStock[type] = clamped;
  }

  DepartmentType? _manualPickupDepartment() {
    final selected = _selectedRestockDepartment;
    if (isDepartmentUnlocked(selected) &&
        departmentStorage(selected) > 0 &&
        departmentStock(selected) < departmentCapacity(selected)) {
      return selected;
    }
    return _nextRestockDepartment();
  }

  DepartmentType? _nextRestockDepartment() {
    final candidates = unlockedDepartments
        .where(
          (type) =>
              departmentStorage(type) > 0 &&
              departmentStock(type) < departmentCapacity(type),
        )
        .toList();
    if (candidates.isEmpty) {
      return null;
    }
    candidates.sort((left, right) {
      final leftRatio = departmentStock(left) / departmentCapacity(left);
      final rightRatio = departmentStock(right) / departmentCapacity(right);
      final ratioComparison = leftRatio.compareTo(rightRatio);
      return ratioComparison != 0
          ? ratioComparison
          : left.index.compareTo(right.index);
    });
    return candidates.first;
  }

  bool get _allDepartmentShelvesFull => unlockedDepartments.every(
    (type) => departmentStock(type) >= departmentCapacity(type),
  );

  bool get _hasRestockableInventory => unlockedDepartments.any(
    (type) =>
        departmentStorage(type) > 0 &&
        departmentStock(type) < departmentCapacity(type),
  );

  void _updateStocker(double dt) {
    if (!isStaffHired(StaffRole.stocker)) {
      if (_stockerLoad > 0) {
        final type = _stockerDepartment ?? DepartmentType.generalGoods;
        final category = departmentCategory(type);
        _inventoryByCategory[category] = inventoryFor(category) + _stockerLoad;
      }
      stockerPosition = stockerPickupZone;
      _stockerLoad = 0;
      _stockerDepartment = null;
      return;
    }

    final stockerLevel = staffLevel(StaffRole.stocker);
    final stockerWorkers = staffWorkerCount(StaffRole.stocker);
    final speed =
        0.115 +
        stockerLevel * 0.012 +
        max(0, stockerWorkers - 1) * 0.01 +
        max(0, restockLevel - 1) * 0.004;

    if (_stockerLoad > 0) {
      final targetDepartment =
          _stockerDepartment ?? DepartmentType.generalGoods;
      stockerPosition = _moveStaffToward(
        stockerPosition,
        departmentZone(targetDepartment),
        speed,
        dt,
      );
      if (_near(stockerPosition, departmentZone(targetDepartment), 0.018)) {
        final delivered = min(
          _stockerLoad,
          departmentCapacity(targetDepartment) -
              departmentStock(targetDepartment),
        );
        if (delivered > 0) {
          _setDepartmentStock(
            targetDepartment,
            departmentStock(targetDepartment) + delivered,
          );
          stockedTotal += delivered;
          totalActions += delivered;
        }
        final remainder = _stockerLoad - delivered;
        if (remainder > 0) {
          final category = departmentCategory(targetDepartment);
          _inventoryByCategory[category] = inventoryFor(category) + remainder;
        }
        _stockerLoad = 0;
        _stockerDepartment = null;
      }
      return;
    }

    stockerPosition = _moveStaffToward(
      stockerPosition,
      stockerPickupZone,
      speed,
      dt,
    );
    final targetDepartment = _nextRestockDepartment();
    if (!_near(stockerPosition, stockerPickupZone, 0.018) ||
        targetDepartment == null) {
      return;
    }

    final loadCapacity = max(1, stockerLevel * max(1, stockerWorkers)).toInt();
    final category = departmentCategory(targetDepartment);
    _stockerLoad = min(
      loadCapacity,
      min(
        inventoryFor(category),
        departmentCapacity(targetDepartment) -
            departmentStock(targetDepartment),
      ),
    );
    _stockerDepartment = targetDepartment;
    _inventoryByCategory[category] = inventoryFor(category) - _stockerLoad;
  }

  Offset _moveStaffToward(
    Offset current,
    Offset target,
    double speed,
    double dt,
  ) {
    final delta = target - current;
    if (delta.distance <= 0.004) {
      return target;
    }
    final step = min(delta.distance, speed * dt);
    return current + delta / delta.distance * step;
  }

  List<MarketCustomer> _queueForCheckout(String checkoutStationId) =>
      _checkoutQueues.putIfAbsent(
        checkoutStationId,
        () => <MarketCustomer>[],
      );

  String _assignCheckoutStation(MarketCustomer customer) {
    final assigned = customer.checkoutStationId;
    if (assigned != null) {
      return assigned;
    }
    final activeStations = _checkoutStations
        .where((station) => station.unlocked && station.active)
        .toList(growable: false);
    final staffedStations = activeStations
        .where(
          (station) =>
              _playerAtCheckoutStation(station.id) ||
              _cashierAtCheckoutStation(station.id),
        )
        .toList(growable: false);
    final candidates = staffedStations.isNotEmpty
        ? staffedStations
        : activeStations;
    var station = candidates.isEmpty
        ? _checkoutStations.first
        : candidates.first;
    for (final candidate in candidates.skip(1)) {
      if (_queueForCheckout(candidate.id).length <
          _queueForCheckout(station.id).length) {
        station = candidate;
      }
    }
    customer.checkoutStationId = station.id;
    return station.id;
  }

  Offset checkoutStationZone(String checkoutStationId) {
    return switch (checkoutStationId) {
      'checkout-2' => checkout2Zone,
      'checkout-3' => checkout3Zone,
      _ => checkoutZone,
    };
  }

  bool _playerAtCheckoutStation(String checkoutStationId) =>
      _near(playerPosition, checkoutStationZone(checkoutStationId), 0.13);

  bool _cashierAtCheckoutStation(String checkoutStationId) {
    if (!isStaffHired(StaffRole.cashier)) {
      return false;
    }
    final activeStations = _checkoutStations
        .where((station) => station.unlocked && station.active)
        .toList(growable: false);
    final stationIndex = activeStations.indexWhere(
      (station) => station.id == checkoutStationId,
    );
    return stationIndex >= 0 &&
        stationIndex < staffWorkerCount(StaffRole.cashier);
  }

  void _removeCustomerFromCheckoutQueue(MarketCustomer customer) {
    final stationId = customer.checkoutStationId;
    if (stationId != null) {
      _checkoutQueues[stationId]?.remove(customer);
    }
  }

  CheckoutStationState? _bestCheckoutStation({String? excluding}) {
    final candidates = _checkoutStations
        .where((station) =>
            station.unlocked && station.active && station.id != excluding)
        .toList(growable: false);
    if (candidates.isEmpty) {
      return null;
    }
    candidates.sort((left, right) {
      final leftReady = _playerAtCheckoutStation(left.id) ||
          _cashierAtCheckoutStation(left.id);
      final rightReady = _playerAtCheckoutStation(right.id) ||
          _cashierAtCheckoutStation(right.id);
      if (leftReady != rightReady) return leftReady ? -1 : 1;
      final queueOrder = _queueForCheckout(left.id).length.compareTo(
        _queueForCheckout(right.id).length,
      );
      return queueOrder != 0
          ? queueOrder
          : checkoutStationIds.indexOf(left.id).compareTo(
              checkoutStationIds.indexOf(right.id),
            );
    });
    return candidates.first;
  }

  void _moveCustomerToCheckout(
    MarketCustomer customer,
    CheckoutStationState station,
  ) {
    _removeCustomerFromCheckoutQueue(customer);
    customer
      ..checkoutStationId = station.id
      ..checkoutOperator = null;
    final queue = _queueForCheckout(station.id);
    if (!queue.contains(customer)) {
      queue.add(customer);
    }
    spawnFloatingText(
      '↪ Queue moved',
      customer.position,
      const Color(0xFF5B8DEF),
      fontSize: 12,
    );
  }

  void _rebalanceCheckoutQueues({bool force = false}) {
    for (final station in _checkoutStations) {
      final queue = List<MarketCustomer>.of(_queueForCheckout(station.id));
      for (final customer in queue) {
        if (customer.phase != CustomerPhase.checkout &&
            customer.phase != CustomerPhase.paying) {
          continue;
        }
        final currentCanServe = station.unlocked &&
            station.active &&
            (_playerAtCheckoutStation(station.id) ||
                _cashierAtCheckoutStation(station.id));
        final needsMove = !station.unlocked ||
            !station.active ||
            (!currentCanServe &&
                customer.checkoutWaitTime >= checkoutRebalanceSeconds);
        if (!needsMove) {
          continue;
        }
        final target = _bestCheckoutStation(excluding: station.id);
        if (target == null) {
          continue;
        }
        final targetCanServe = _playerAtCheckoutStation(target.id) ||
            _cashierAtCheckoutStation(target.id);
        if (!force && currentCanServe == targetCanServe) {
          continue;
        }
        _moveCustomerToCheckout(customer, target);
      }
    }
  }

  void _updateCustomers(double dt) {
    final removed = <MarketCustomer>[];
    for (final queue in _checkoutQueues.values) {
      queue.removeWhere(
        (customer) =>
            !customers.contains(customer) ||
            (customer.phase != CustomerPhase.checkout &&
                customer.phase != CustomerPhase.paying),
      );
    }

    for (final customer in customers) {
      if (customer.phase == CustomerPhase.shopping) {
        _updateCustomerShopping(customer, dt);
      } else if (customer.phase == CustomerPhase.checkout) {
        final queue = _queueForCheckout(_assignCheckoutStation(customer));
        if (!queue.contains(customer)) {
          queue.add(customer);
        }
      } else if (customer.phase == CustomerPhase.paying) {
        final queue = _queueForCheckout(_assignCheckoutStation(customer));
        if (!queue.contains(customer)) {
          queue.insert(0, customer);
        }
      }
    }

    _rebalanceCheckoutQueues();

    for (final customer in customers) {
      final stationId = customer.checkoutStationId;
      final queue = stationId == null
          ? const <MarketCustomer>[]
          : _queueForCheckout(stationId);
      final queueIndex = queue.indexOf(customer);
      final playerAtCheckout = stationId != null &&
          _playerAtCheckoutStation(stationId);
      final cashierAvailable = stationId != null &&
          _cashierAtCheckoutStation(stationId);
      final waitingAtCheckout =
          customer.phase == CustomerPhase.checkout ||
          customer.phase == CustomerPhase.paying;
      final canProgress =
          queueIndex == 0 && (playerAtCheckout || cashierAvailable);
      if (waitingAtCheckout && !canProgress) {
        customer.checkoutWaitTime += dt;
        final patienceBefore = customer.patience;
        customer.patience = max(0, customer.patience - dt * 0.35);
        if (patienceBefore > checkoutPatienceWarning &&
            customer.patience <= checkoutPatienceWarning) {
          spawnFloatingText(
            'Getting impatient',
            customer.position,
            const Color(0xFFF6A623),
            fontSize: 12,
          );
          unawaited(SfxManager.instance.customerWarning());
        }
        if (customer.checkoutWaitTime > checkoutQueueGraceSeconds) {
          customer.satisfaction = max(
            checkoutSatisfactionFloor,
            customer.satisfaction - dt * 0.035,
          );
        }
        if (customer.patience <= checkoutPatienceWarning) {
          customer.emotion = 'worried';
        }
        if (customer.patience <= 0) {
          customer
            ..phase = CustomerPhase.leaving
            ..phaseTime = 0
            ..emotion = 'sad'
            ..checkoutOperator = null;
          shiftMissedSales++;
          recordMissedSaleEstimate(itemPrice);
          totalActions++;
          _removeCustomerFromCheckoutQueue(customer);
          spawnFloatingText(
            'Customer left',
            customer.position,
            const Color(0xFFE85D75),
            fontSize: 12,
          );
          unawaited(SfxManager.instance.customerLeave());
          continue;
        }
      }

      switch (customer.phase) {
        case CustomerPhase.shopping:
          break;
        case CustomerPhase.entering:
        case CustomerPhase.leaving:
          customer.phaseTime += dt;
        case CustomerPhase.checkout:
          break;
        case CustomerPhase.paying:
          customer.checkoutOperator ??= playerAtCheckout
              ? CheckoutOperator.player
              : cashierAvailable
              ? CheckoutOperator.cashier
              : null;
          final assignedOperatorAvailable =
              customer.checkoutOperator == CheckoutOperator.player
              ? playerAtCheckout
              : customer.checkoutOperator == CheckoutOperator.cashier
              ? cashierAvailable
              : false;
          if (!assignedOperatorAvailable) {
            customer.checkoutOperator = playerAtCheckout
                ? CheckoutOperator.player
                : cashierAvailable
                ? CheckoutOperator.cashier
                : null;
          }
          final operatorAvailable =
              customer.checkoutOperator == CheckoutOperator.player
              ? playerAtCheckout
              : customer.checkoutOperator == CheckoutOperator.cashier
              ? cashierAvailable
              : false;
          if (queueIndex == 0 && operatorAvailable) {
            customer.phaseTime += dt;
          }
      }

      switch (customer.phase) {
        case CustomerPhase.entering:
          final firstDepartment =
              customer.currentDepartment ?? DepartmentType.generalGoods;
          final firstTarget =
              departmentZone(firstDepartment) + const Offset(0, -0.10);
          _moveCustomer(customer, firstTarget, dt);
          if (_near(customer.position, firstTarget, 0.05)) {
            customer.phase = CustomerPhase.shopping;
            customer.phaseTime = 0;
          }
        case CustomerPhase.shopping:
          break;
        case CustomerPhase.checkout:
          final effectiveIndex = queueIndex >= 0
              ? queueIndex
              : queue.length;
          final queueTarget =
              checkoutStationZone(stationId ?? primaryCheckoutStationId) +
              Offset(-0.03, 0.10 + effectiveIndex * 0.085);
          _moveCustomer(customer, queueTarget, dt);

          if (queueIndex == 0 &&
              (playerAtCheckout || cashierAvailable) &&
              _near(customer.position, queueTarget, 0.04)) {
            customer.phase = CustomerPhase.paying;
            customer.phaseTime = 0;
            customer.checkoutWaitTime = 0;
            customer.emotion = 'happy';
            customer.checkoutOperator = playerAtCheckout
                ? CheckoutOperator.player
                : CheckoutOperator.cashier;
            unawaited(SfxManager.instance.checkoutScan());
          }
        case CustomerPhase.paying:
          final checkoutSeconds =
              customer.checkoutOperator == CheckoutOperator.cashier
              ? cashierCheckoutSeconds
              : max(0.45, GameBalance.baseCheckoutSeconds - storeLevel * 0.04);
          if (customer.phaseTime >= checkoutSeconds) {
            final tip = customer.satisfaction >= 0.82 ? customer.tipValue : 0;
            final saleValue = max(itemPrice, customer.basketValue) + tip;
            coins += saleValue;
            totalCoinsEarned += saleValue;
            totalSales++;
            shiftSales++;
            shiftRevenue += saleValue;
            recordSale(saleValue);
            totalActions++;
            if (customer.checkoutOperator == CheckoutOperator.player) {
              registerComboAction(customer.position);
            }
            spawnFloatingText(
              '+$saleValue\$${customer.isVip ? " ⭐" : ""}',
              customer.position,
              customer.isVip ? const Color(0xFFFFD700) : const Color(0xFF4CAF50),
              fontSize: customer.isVip ? 20 : 16,
            );
            unawaited(SfxManager.instance.sale());
            customer.phase = CustomerPhase.leaving;
            customer.phaseTime = 0;
            customer.checkoutOperator = null;
            _removeCustomerFromCheckoutQueue(customer);
          }
        case CustomerPhase.leaving:
          _moveCustomer(customer, exit, dt);
          if (customer.position.dy < -0.04) {
            removed.add(customer);
            _removeCustomerFromCheckoutQueue(customer);
          }
      }
    }

    customers.removeWhere(removed.contains);
  }

  void _updateCustomerShopping(MarketCustomer customer, double dt) {
    final department = customer.currentDepartment;
    if (department == null) {
      _finishCustomerShopping(customer);
      return;
    }

    final target = departmentZone(department) + const Offset(0, -0.10);
    _moveCustomer(customer, target, dt);
    if (!_near(customer.position, target, 0.05)) {
      return;
    }

    customer.phaseTime += dt;
    if (departmentStock(department) > 0 && customer.phaseTime >= 0.65) {
      _setDepartmentStock(department, departmentStock(department) - 1);
      final state = _departmentFor(department);
      if (state != null) {
        state.itemsSold++;
      }
      customer
        ..hasProduct = true
        ..basketValue += departmentItemPrice(department)
        ..shoppingIndex = customer.shoppingIndex + 1
        ..phaseTime = 0
        ..emotion = 'happy';
      if (customer.currentDepartment == null) {
        _finishCustomerShopping(customer);
      }
      return;
    }

    if (departmentStock(department) == 0) {
      customer
        ..patience = max(0, customer.patience - dt)
        ..satisfaction = max(0.2, customer.satisfaction - dt * 0.08)
        ..emotion = 'worried';
      if (customer.phaseTime >= 1.4) {
        customer.missedItems++;
        shiftMissedSales++;
        recordMissedSaleEstimate(departmentItemPrice(department));
        customer.shoppingIndex++;
        customer.phaseTime = 0;
        if (customer.currentDepartment == null) {
          _finishCustomerShopping(customer);
        }
      }
    }
  }

  void _finishCustomerShopping(MarketCustomer customer) {
    customer.phaseTime = 0;
    if (!customer.hasProduct) {
      customer.phase = CustomerPhase.leaving;
      customer.emotion = 'sad';
      return;
    }
    customer.phase = CustomerPhase.checkout;
    customer.checkoutWaitTime = 0;
    final queue = _queueForCheckout(_assignCheckoutStation(customer));
    if (!queue.contains(customer)) {
      queue.add(customer);
    }
  }

  void _spawnCustomer() {
    const palette = [
      Color(0xFF7957D5),
      Color(0xFFEF6C57),
      Color(0xFF3F88C5),
      Color(0xFFF2B134),
      Color(0xFF2A9D8F),
    ];
    final availableDepartments = unlockedDepartments.toList()..shuffle(_random);
    final desiredDepartments = min(
      availableDepartments.length,
      1 + storeLevel ~/ 4,
    );
    final shoppingList = availableDepartments
        .take(max(1, desiredDepartments))
        .toList(growable: false);
    final vip = _random.nextDouble() < 0.16;
    final customer = MarketCustomer(
      id: _customerId++,
      position: entrance + Offset((_random.nextDouble() - 0.5) * 0.08, 0),
      color: palette[_random.nextInt(palette.length)],
      patience: 7.4 + _random.nextDouble() * 1.4,
      satisfaction: 0.95 + _random.nextDouble() * 0.05,
      isVip: vip,
      tipValue: vip
          ? 5
          : _random.nextBool()
          ? 2
          : 0,
      basketCount: shoppingList.length,
      emotion: _random.nextDouble() < 0.3 ? 'happy' : 'neutral',
      shoppingList: shoppingList,
    );
    customers.add(customer);
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
    if (!canBuyUpgrade(type)) {
      return false;
    }
    coins -= offer.cost;
    switch (type) {
      case UpgradeType.bag:
        bagLevel++;
        break;
      case UpgradeType.shelf:
        shelfLevel++;
        break;
      case UpgradeType.price:
        priceLevel++;
        break;
      case UpgradeType.speed:
        speedLevel++;
        break;
      case UpgradeType.checkout:
        checkoutLevel++;
        _unlockCheckoutStationsForLevel();
        break;
      case UpgradeType.restock:
        restockLevel++;
        break;
    }
    upgradesBought++;
    totalActions++;
    _afterProgressChanged();

    return true;
  }

  bool canBuyUpgrade(UpgradeType type) {
    final offer = upgrades.firstWhere((item) => item.type == type);
    return coins >= offer.cost &&
        offer.level < 10 &&
        (type != UpgradeType.checkout || isStaffHired(StaffRole.cashier)) &&
        (type != UpgradeType.restock || isStaffHired(StaffRole.stocker));
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

  }

  Future<bool> claimInstantAdReward() async {
    const placement = RewardPlacement.instantCoins;
    if (rewardInProgress || !canClaimReward(placement)) {
      return false;
    }
    rewardInProgress = true;
    final wasPaused = paused;
    paused = true;

    var completed = false;
    try {
      completed = await monetization.showRewardedAd(placement);
    } catch (_) {
      completed = false;
    } finally {
      paused = wasPaused;
    }
    if (completed) {
      _recordRewardClaim(placement);
      coins += instantAdReward;
      totalCoinsEarned += instantAdReward;
      totalActions++;
      _afterProgressChanged(immediate: true);
    }
    rewardInProgress = false;
    await save();

    return completed;
  }

  Future<bool> claimOfflineReward({required bool doubled}) async {
    if (offlineEarnings <= 0 || rewardInProgress) {
      return false;
    }
    var multiplier = 1;
    if (doubled) {
      const placement = RewardPlacement.doubleOfflineEarnings;
      if (!canClaimReward(placement)) {
        return false;
      }
      rewardInProgress = true;
      final wasPaused = paused;
      paused = true;
  
      var completed = false;
      try {
        completed = await monetization.showRewardedAd(placement);
      } catch (_) {
        completed = false;
      } finally {
        paused = wasPaused;
      }
      rewardInProgress = false;
      if (!completed) {
    
        return false;
      }
      _recordRewardClaim(placement);
      multiplier = 2;
    }
    final reward = offlineEarnings * multiplier;
    coins += reward;
    totalCoinsEarned += reward;
    offlineEarnings = 0;
    totalActions++;
    _afterProgressChanged(immediate: true);
    await save();

    return true;
  }

  bool canClaimReward(RewardPlacement placement) {
    _resetDailyMonetizationCountersIfNeeded();
    if (!rewardedAdsAvailable ||
        rewardInProgress ||
        _rewardClaimsToday >= MonetizationPolicy.rewardedDailyLimit) {
      return false;
    }
    final lastClaimed = _rewardLastClaimed[placement];
    return lastClaimed == null ||
        _now().difference(lastClaimed) >= MonetizationPolicy.rewardedCooldown;
  }

  Duration rewardCooldownRemaining(RewardPlacement placement) {
    final lastClaimed = _rewardLastClaimed[placement];
    if (lastClaimed == null) {
      return Duration.zero;
    }
    final elapsed = _now().difference(lastClaimed);
    if (elapsed >= MonetizationPolicy.rewardedCooldown) {
      return Duration.zero;
    }
    return MonetizationPolicy.rewardedCooldown - elapsed;
  }

  Future<bool> maybeShowInterstitial(InterstitialPlacement placement) async {
    _resetDailyMonetizationCountersIfNeeded();
    final now = _now();
    if (adsRemoved ||
        paused ||
        !monetization.interstitialAdsAvailable ||
        totalPlayTime < MonetizationPolicy.minimumInterstitialPlayTime ||
        _interstitialsToday >= MonetizationPolicy.interstitialDailyLimit ||
        (_lastInterstitialAt != null &&
            now.difference(_lastInterstitialAt!) <
                MonetizationPolicy.interstitialSessionCooldown) ||
        (_lastRewardedAt != null &&
            now.difference(_lastRewardedAt!) <
                MonetizationPolicy.interstitialAfterRewardCooldown)) {
      return false;
    }
    final wasPaused = paused;
    paused = true;

    var shown = false;
    try {
      shown = await monetization.showInterstitial(placement);
    } catch (_) {
      shown = false;
    } finally {
      paused = wasPaused;
  
    }
    if (!shown) {
      return false;
    }
    _lastInterstitialAt = now;
    _interstitialsToday++;
    _markDirty(immediate: true);
    return true;
  }

  Future<bool> purchaseStoreProduct(StoreProduct product) async {
    if (storePurchaseInProgress ||
        !storePurchasesAvailable ||
        (product == StoreProduct.noAds && adsRemoved)) {
      return false;
    }
    storePurchaseInProgress = true;
    lastPurchaseState = PurchaseState.pending;

    final result = await monetization.purchase(product);
    final purchased = _deliverVerifiedPurchase(result);
    lastPurchaseState = purchased
        ? result.state
        : result.state == PurchaseState.cancelled
        ? PurchaseState.cancelled
        : PurchaseState.failed;
    storePurchaseInProgress = false;
    await save();

    return purchased;
  }

  Future<bool> restoreStorePurchases() async {
    if (storePurchaseInProgress || !storePurchasesAvailable) {
      return false;
    }
    storePurchaseInProgress = true;
    lastPurchaseState = PurchaseState.pending;

    final restored = await monetization.restorePurchases();
    var delivered = false;
    for (final result in restored) {
      delivered = _deliverVerifiedPurchase(result) || delivered;
    }
    lastPurchaseState = delivered
        ? PurchaseState.restored
        : PurchaseState.failed;
    storePurchaseInProgress = false;
    await save();

    return delivered;
  }

  bool _deliverVerifiedPurchase(StorePurchaseResult result) {
    final transactionId = result.transactionId;
    if (!result.canDeliver ||
        (result.state == PurchaseState.restored &&
            result.product != StoreProduct.noAds &&
            result.product != StoreProduct.starterPack) ||
        transactionId == null ||
        _deliveredTransactionIds.contains(transactionId)) {
      return false;
    }
    _deliveredTransactionIds.add(transactionId);
    switch (result.product) {
      case StoreProduct.noAds:
        adsRemoved = true;
      case StoreProduct.coinPack:
        coins += 1000;
        totalCoinsEarned += 1000;
      case StoreProduct.gemPack:
        gems += 40;
      case StoreProduct.emergencySupply:
        final available = max(0, storageCapacity - totalStoredInventory);
        _inventoryByCategory['General'] =
            inventoryFor('General') + min(12, available);
      case StoreProduct.starterPack:
        coins += 500;
        gems += 20;
        totalCoinsEarned += 500;
        bagLevel++;
        shelfLevel++;
    }
    totalActions++;
    _afterProgressChanged(immediate: true);
    return true;
  }

  void _recordRewardClaim(RewardPlacement placement) {
    final now = _now();
    _resetDailyMonetizationCountersIfNeeded();
    _rewardLastClaimed[placement] = now;
    _lastRewardedAt = now;
    _rewardClaimsToday++;
    _markDirty(immediate: true);
  }

  void _bootstrapSystems() {
    for (final role in StaffRole.values) {
      _ensureStaff(role);
    }
    final departmentByType = <DepartmentType, DepartmentState>{};
    for (final department in _departments) {
      final previous = departmentByType[department.type];
      if (previous == null) {
        departmentByType[department.type] = department;
      } else {
        previous.level = max(previous.level, department.level);
        previous.unlocked = previous.unlocked || department.unlocked;
        previous.activated = previous.activated || department.activated;
        previous.itemsSold = max(previous.itemsSold, department.itemsSold);
      }
    }
    _departments
      ..clear()
      ..addAll(
        DepartmentType.values.map(
          (type) =>
              departmentByType[type] ??
              DepartmentState(
                type: type,
                level: type == DepartmentType.generalGoods ? 1 : 0,
                unlocked: type == DepartmentType.generalGoods,
                activated: false,
              ),
        ),
      );
    for (final type in DepartmentType.values) {
      _departmentShelfStock.putIfAbsent(type, () => 0);
    }
    if (!_restoredInventoryPresent) {
      _inventoryByCategory['General'] = GameBalance.starterStorageStock;
    }
    _reconcileAfterLoad();
  }

  bool hireStaff(StaffRole role) {
    final member = _ensureStaff(role);
    if (!isStaffRoleUnlocked(role) || member.hired || coins < member.hireCost) {
      return false;
    }
    coins -= member.hireCost;
    member.hired = true;
    member.level = max(1, member.level);
    member.workerCount = 1;
    totalActions++;
    _afterProgressChanged();

    return true;
  }

  bool upgradeStaff(StaffRole role) {
    final member = _ensureStaff(role);
    if (!member.hired || member.level >= 10 || coins < member.upgradeCost) {
      return false;
    }
    coins -= member.upgradeCost;
    member.level++;
    totalActions++;
    _afterProgressChanged();

    return true;
  }

  bool hireAdditionalStaff(StaffRole role) {
    final member = _ensureStaff(role);
    final availableSlots = availableWorkerSlots(role);
    if (!member.hired ||
        member.workerCount >= availableSlots ||
        member.workerCount >= GameBalance.maxWorkersPerRole ||
        coins < member.additionalHireCost) {
      return false;
    }
    coins -= member.additionalHireCost;
    member.workerCount++;
    totalActions++;
    _afterProgressChanged();

    return true;
  }

  bool isStaffRoleUnlocked(StaffRole role) =>
      isStaffHired(role) ||
      storeLevel >= GameBalance.staffRoleUnlockLevel(role);

  int availableWorkerSlots(StaffRole role) => max(
    staffWorkerCount(role),
    GameBalance.availableWorkerSlots(role, storeLevel),
  );

  int? nextWorkerSlotLevel(StaffRole role) =>
      GameBalance.nextWorkerSlotLevel(role, storeLevel, staffWorkerCount(role));

  int staffLevel(StaffRole role) => _ensureStaff(role).level;

  int staffWorkerCount(StaffRole role) =>
      max(0, _ensureStaff(role).workerCount);

  int staffProductivity(StaffRole role) {
    final member = _ensureStaff(role);
    return member.hired ? member.productivity : 0;
  }

  int get totalHiredWorkers => StaffRole.values.fold<int>(
    0,
    (total, role) => total + staffWorkerCount(role),
  );

  bool isStaffHired(StaffRole role) => _ensureStaff(role).hired;

  List<StaffMember> get staffMembers =>
      StaffRole.values.map(_ensureStaff).toList(growable: false);

  StaffStatus staffStatus(StaffRole role) {
    final member = _ensureStaff(role);
    if (!member.hired) {
      return StaffStatus.notHired;
    }
    return switch (role) {
      StaffRole.cashier =>
        customers.any(
              (customer) =>
                  customer.phase == CustomerPhase.paying &&
                  customer.checkoutOperator == CheckoutOperator.cashier,
            )
            ? StaffStatus.serving
            : StaffStatus.idle,
      StaffRole.stocker =>
        _stockerLoad > 0
            ? StaffStatus.stocking
            : (_allDepartmentShelvesFull ||
                  (shelfStock >= shelfCapacity && !_hasRestockableInventory))
            ? StaffStatus.waitingForShelf
            : !_hasRestockableInventory
            ? StaffStatus.waitingForStock
            : StaffStatus.stocking,
      StaffRole.cleaner =>
        customers.any((customer) => customer.satisfaction < 1)
            ? StaffStatus.cleaning
            : StaffStatus.idle,
      StaffRole.baker =>
        bakeryUnlocked && bakeryReadyStock < GameBalance.bakeryReadyCapacity
            ? StaffStatus.baking
            : StaffStatus.idle,
      StaffRole.manager => StaffStatus.managing,
      StaffRole.courier =>
        _pendingDeliveries.isNotEmpty
            ? StaffStatus.delivering
            : StaffStatus.idle,
      StaffRole.promoter => StaffStatus.promoting,
    };
  }

  StaffMember _ensureStaff(StaffRole role) {
    return _staff.putIfAbsent(role, () => StaffMember(role: role));
  }

  int inventoryFor(String category) =>
      max(0, _inventoryByCategory[category] ?? 0);

  List<InventoryDelivery> get pendingDeliveries =>
      List<InventoryDelivery>.unmodifiable(_pendingDeliveries);

  bool isDeliveryReady(InventoryDelivery delivery) {
    return !_now().isBefore(delivery.readyAt);
  }

  InventoryDelivery? placeInventoryOrder(
    String category,
    int quantity, {
    int cost = 20,
  }) {
    final pendingQuantity = _pendingDeliveries.fold<int>(
      0,
      (sum, delivery) => sum + delivery.quantity,
    );
    if (category.trim().isEmpty ||
        quantity <= 0 ||
        cost < 0 ||
        coins < cost ||
        totalStoredInventory + pendingQuantity + quantity > storageCapacity) {
      return null;
    }
    coins -= cost;
    recordStockOrderCost(cost);
    final delivery = InventoryDelivery(
      id: 'delivery-${_now().microsecondsSinceEpoch}-${_random.nextInt(1000)}',
      category: category.trim(),
      quantity: quantity,
      cost: cost,
      readyAt: _now().add(effectiveInventoryOrderDelay),
    );
    _pendingDeliveries.add(delivery);
    totalActions++;
    _afterProgressChanged();

    return delivery;
  }

  InventoryDelivery? placeQuickRestock() {
    if (!canQuickRestock) {
      return null;
    }
    return placeInventoryOrder(
      'General',
      GameBalance.quickRestockQuantity,
      cost: GameBalance.quickRestockCost,
    );
  }

  bool fulfillPendingDelivery(String id) {
    final delivery = _pendingDeliveries.firstWhere(
      (item) => item.id == id,
      orElse: () => InventoryDelivery(
        id: '',
        category: '',
        quantity: 0,
        cost: 0,
        readyAt: _now(),
      ),
    );
    if (delivery.id.isEmpty ||
        delivery.completed ||
        _now().isBefore(delivery.readyAt)) {
      return false;
    }
    delivery.completed = true;
    unawaited(SfxManager.instance.deliveryArrived());
    _pendingDeliveries.remove(delivery);
    _inventoryByCategory[delivery.category] =
        inventoryFor(delivery.category) + delivery.quantity;
    totalActions++;
    _afterProgressChanged();

    return true;
  }

  bool claimEmergencyStock() {
    if (!canClaimEmergencyStock) {
      return false;
    }
    _inventoryByCategory['General'] =
        inventoryFor('General') + GameBalance.emergencyStockQuantity;
    _lastEmergencyStockAt = _now();
    totalActions++;
    _afterProgressChanged(immediate: true);

    return true;
  }

  bool isDepartmentUnlocked(DepartmentType type) {
    return _departmentFor(type)?.unlocked ?? false;
  }

  bool unlockDepartment(DepartmentType type) {
    final definition = DepartmentCatalog.find(type);
    final state = _departmentFor(type);
    if (definition == null ||
        state == null ||
        state.unlocked ||
        storeLevel < definition.unlockLevel ||
        coins < definition.unlockCost) {
      return false;
    }
    coins -= definition.unlockCost;
    _activateDepartment(state, announce: true);
    totalActions++;
    _afterProgressChanged(immediate: true);

    return true;
  }

  void _activateDepartment(DepartmentState state, {required bool announce}) {
    final definition = DepartmentCatalog.find(state.type);
    if (definition == null) {
      return;
    }
    final wasUnlocked = state.unlocked;
    state
      ..unlocked = true
      ..level = max(1, state.level);
    if (!state.activated) {
      state.activated = true;
      _setDepartmentStock(
        state.type,
        max(
          departmentStock(state.type),
          min(definition.starterShelfStock, departmentCapacity(state.type)),
        ),
      );
      final availableStorage = max(0, storageCapacity - totalStoredInventory);
      if (state.type != DepartmentType.generalGoods &&
          availableStorage > 0 &&
          definition.starterStorageStock > 0) {
        _inventoryByCategory[definition.category] =
            inventoryFor(definition.category) +
            min(availableStorage, definition.starterStorageStock);
      }
    }
    if (announce && !wasUnlocked) {
      _departmentUnlocks.add(state.type);
    }
  }

  DepartmentType? takeDepartmentUnlock() {
    return _departmentUnlocks.isEmpty ? null : _departmentUnlocks.removeFirst();
  }

  DepartmentState? _departmentFor(DepartmentType type) {
    for (final department in _departments) {
      if (department.type == type) {
        return department;
      }
    }
    return null;
  }

  void _applyStaffAutomation() {
    final cleanerLevel = staffLevel(StaffRole.cleaner);
    final cleanerWorkers = staffWorkerCount(StaffRole.cleaner);
    final bakerWorkers = staffWorkerCount(StaffRole.baker);
    final managerPower = staffProductivity(StaffRole.manager);

    if (isStaffHired(StaffRole.cleaner) &&
        cleanerLevel > 0 &&
        customers.isNotEmpty) {
      var cleanedCustomers = 0;
      for (final customer in customers) {
        if (customer.satisfaction < 1.0) {
          customer.satisfaction = min(
            1.0,
            customer.satisfaction + 0.03 * cleanerLevel,
          );
          cleanedCustomers++;
          if (cleanedCustomers >= cleanerWorkers) {
            break;
          }
        }
      }
    }

    if (isStaffHired(StaffRole.baker) &&
        bakeryUnlocked &&
        bakeryReadyStock > 0) {
      final room =
          departmentCapacity(DepartmentType.bakery) -
          departmentStock(DepartmentType.bakery);
      final displayed = min(room, min(bakeryReadyStock, max(1, bakerWorkers)));
      if (displayed > 0) {
        bakeryReadyStock -= displayed;
        _setDepartmentStock(
          DepartmentType.bakery,
          departmentStock(DepartmentType.bakery) + displayed,
        );
        stockedTotal += displayed;
        totalActions += displayed;
      }
    }

    if (isStaffHired(StaffRole.manager) &&
        managerPower > 0 &&
        totalActions > 0) {
      final bonus = managerPower * 2;
      if (bonus > 0) {
        coins = max(0, coins + bonus);
        recordBonus(bonus);
      }
    }
  }

  void _advancePendingDeliveries() {
    for (final delivery in _pendingDeliveries) {
      if (!delivery.completed && _now().isAfter(delivery.readyAt)) {
        delivery.completed = true;
        unawaited(SfxManager.instance.deliveryArrived());
        _inventoryByCategory[delivery.category] =
            inventoryFor(delivery.category) + delivery.quantity;
      }
    }
    if (_pendingDeliveries.any((item) => item.completed)) {
      _pendingDeliveries.removeWhere((item) => item.completed);
      _afterProgressChanged();
    }
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
      'version': 7,
      'saveSchemaVersion': 2,
      'savedAt': _now().toIso8601String(),
      'coins': coins,
      'gems': gems,
      'carried': carried,
      'carriedDepartment': carriedDepartment?.name,
      'selectedRestockDepartment': _selectedRestockDepartment.name,
      'shelfStock': shelfStock,
      'bakeryReadyStock': bakeryReadyStock,
      'bakeryActivated': _bakeryActivated,
      'stockerX': stockerPosition.dx,
      'stockerY': stockerPosition.dy,
      'stockerLoad': _stockerLoad,
      'stockerDepartment': _stockerDepartment?.name,
      'totalSales': totalSales,
      'shiftNumber': shiftNumber,
      'shiftElapsedSeconds': shiftElapsedSeconds,
      'shiftSales': shiftSales,
      'shiftRevenue': shiftRevenue,
      'shiftMissedSales': shiftMissedSales,
      'shiftLedger': _shiftLedger.toJson(),
      'shiftOperatingCostsApplied': _shiftOperatingCostsApplied,
      'shiftMissionClaimed': shiftMissionClaimed,
      'fastCheckoutClaimed': fastCheckoutClaimed,
      'dailyMissionClaimedOn': _dailyMissionClaimedOn?.toIso8601String(),
      'totalCoinsEarned': totalCoinsEarned,
      'stockedTotal': stockedTotal,
      'upgradesBought': upgradesBought,
      'questStage': questStage,
      'questBaseline': questBaseline,
      'bagLevel': bagLevel,
      'shelfLevel': shelfLevel,
      'priceLevel': priceLevel,
      'speedLevel': speedLevel,
      'checkoutLevel': checkoutLevel,
      'checkoutStations': _checkoutStations
          .map(
            (station) => <String, Object>{
              'id': station.id,
              'unlocked': station.unlocked,
              'active': station.active,
            },
          )
          .toList(growable: false),
      'restockLevel': restockLevel,
      'adsRemoved': adsRemoved,
      'totalActions': totalActions,
      'highestBalance': highestBalance,
      'highestScore': highestScore,
      'totalPlaySeconds': totalPlaySeconds,
      'muted': muted,
      'onboardingComplete': onboardingComplete,
      'lastEmergencyStockAt': _lastEmergencyStockAt?.toIso8601String(),
      'rewardLastClaimed': _rewardLastClaimed.map(
        (placement, claimedAt) =>
            MapEntry(placement.name, claimedAt.toIso8601String()),
      ),
      'rewardClaimDay': _rewardClaimDay?.toIso8601String(),
      'rewardClaimsToday': _rewardClaimsToday,
      'lastRewardedAt': _lastRewardedAt?.toIso8601String(),
      'lastInterstitialAt': _lastInterstitialAt?.toIso8601String(),
      'interstitialDay': _interstitialDay?.toIso8601String(),
      'interstitialsToday': _interstitialsToday,
      'deliveredTransactions': _deliveredTransactionIds.toList(growable: false),
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
      'staff': _staff.entries
          .map(
            (entry) => <String, Object>{
              'id': entry.value.id,
              'role': entry.key.name,
              'level': entry.value.level,
              'hired': entry.value.hired,
              'workerCount': entry.value.workerCount,
              'assignment': entry.value.assignment.name,
            },
          )
          .toList(growable: false),
      'departments': _departments
          .map(
            (item) => <String, Object>{
              'type': item.type.name,
              'level': item.level,
              'unlocked': item.unlocked,
              'activated': item.activated,
              'itemsSold': item.itemsSold,
              'shelfStock': departmentStock(item.type),
            },
          )
          .toList(growable: false),
      'inventory': _inventoryByCategory.map(
        (key, value) => MapEntry(key, value),
      ),
      'deliveries': _pendingDeliveries
          .map(
            (item) => <String, Object>{
              'id': item.id,
              'category': item.category,
              'quantity': item.quantity,
              'cost': item.cost,
              'readyAt': item.readyAt.toIso8601String(),
              'completed': item.completed,
            },
          )
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
    bakeryReadyStock = 0;
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
    checkoutLevel = 1;
    restockLevel = 1;
    adsRemoved = false;
    lastPurchaseState = null;
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
    _departmentUnlocks.clear();
    _staff.clear();
    _departments.clear();
    _inventoryByCategory.clear();
    _departmentShelfStock.clear();
    _pendingDeliveries.clear();
    _resetCheckoutStations();
    stockerPosition = stockerPickupZone;
    _stockerLoad = 0;
    _stockerDepartment = null;
    _carriedDepartment = null;
    _selectedRestockDepartment = DepartmentType.generalGoods;
    _restoredInventoryPresent = false;
    _lastEmergencyStockAt = null;
    _bakeryActivated = false;
    _rewardLastClaimed.clear();
    _rewardClaimDay = null;
    _rewardClaimsToday = 0;
    _lastRewardedAt = null;
    _lastInterstitialAt = null;
    _interstitialDay = null;
    _interstitialsToday = 0;
    _deliveredTransactionIds.clear();
    customers.clear();
    playerPosition = const Offset(0.5, 0.72);
    movement = Offset.zero;
    _movementTarget = null;
    _bootstrapSystems();
    _lastObservedStoreLevel = storeLevel;
    _applyDailyBonus();
    _recordPerformanceSample(force: true);
    _updateHighs();
    _evaluateAchievements();

    await save();
  }

  void setMuted(bool value) {
    if (muted == value) {
      return;
    }
    muted = value;
    _markDirty(immediate: true);

  }

  void completeOnboarding() {
    if (onboardingComplete) {
      return;
    }
    onboardingComplete = true;
    _markDirty(immediate: true);

  }

  void replayOnboarding() {
    _tutorialReplayRequested = true;
    onboardingComplete = false;
    _markDirty(immediate: true);

  }

  bool takeTutorialReplayRequest() {
    if (!_tutorialReplayRequested) {
      return false;
    }
    _tutorialReplayRequested = false;
    return true;
  }

  void acknowledgeDailyBonus() {
    if (pendingDailyBonus == null) {
      return;
    }
    pendingDailyBonus = null;

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

    return entry;
  }

  @visibleForTesting
  void debugSetPlayerPosition(Offset position) {
    playerPosition = Offset(
      position.dx.clamp(0.06, 0.94),
      position.dy.clamp(0.09, 0.94),
    );
  }

  @visibleForTesting
  void debugSetProgress({int? sales, int? purchasedUpgrades}) {
    if (sales != null) {
      totalSales = max(0, sales);
    }
    if (purchasedUpgrades != null) {
      upgradesBought = max(0, purchasedUpgrades);
    }
    _afterProgressChanged(immediate: true);

  }

  @visibleForTesting
  void debugReconcileState() {
    _reconcileAfterLoad();
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    _sceneNotifier.dispose();
    monetization.dispose();
    super.dispose();
  }

  void _restore(Map<String, dynamic> saved) {
    coins = _readIntAny(saved, const ['coins', 'balance'], 25);
    gems = _readIntAny(saved, const ['gems', 'premiumCurrency'], 3);
    carried = _readIntAny(saved, const ['carried', 'bagStock'], 0);
    _carriedDepartment = _enumByName(
      DepartmentType.values,
      saved['carriedDepartment'],
    );
    _selectedRestockDepartment =
        _enumByName(
          DepartmentType.values,
          saved['selectedRestockDepartment'],
        ) ??
        DepartmentType.generalGoods;
    shelfStock = _readIntAny(saved, const ['shelfStock', 'stock'], 0);
    bakeryReadyStock = _readIntAny(
      saved,
      const ['bakeryReadyStock', 'readyBakeryStock'],
      0,
      maximum: GameBalance.bakeryReadyCapacity,
    );
    _bakeryActivated = _readBoolAny(saved, const ['bakeryActivated'], false);
    stockerPosition = Offset(
      _readDoubleAny(saved, const [
        'stockerX',
        'stockerPositionX',
      ], stockerPickupZone.dx).clamp(0.06, 0.94),
      _readDoubleAny(saved, const [
        'stockerY',
        'stockerPositionY',
      ], stockerPickupZone.dy).clamp(0.09, 0.94),
    );
    _stockerLoad = _readIntAny(
      saved,
      const ['stockerLoad', 'stockerCarried'],
      0,
      maximum: 100,
    );
    _stockerDepartment = _enumByName(
      DepartmentType.values,
      saved['stockerDepartment'],
    );
    totalSales = _readIntAny(saved, const ['totalSales', 'sales'], 0);
    shiftNumber = _readIntAny(saved, const ['shiftNumber'], 1, minimum: 1);
    shiftElapsedSeconds = _readDoubleAny(saved, const [
      'shiftElapsedSeconds',
    ], 0).clamp(0, shiftDurationSeconds);
    shiftSales = _readIntAny(saved, const ['shiftSales'], 0, minimum: 0);
    shiftRevenue = _readIntAny(saved, const ['shiftRevenue'], 0, minimum: 0);
    shiftMissedSales = _readIntAny(
      saved,
      const ['shiftMissedSales'],
      0,
      minimum: 0,
    );
    _shiftLedger = ShiftLedger.fromJson(saved['shiftLedger']);
    _shiftOperatingCostsApplied = _readBoolAny(
      saved,
      const ['shiftOperatingCostsApplied'],
      false,
    );
    shiftMissionClaimed = _readBoolAny(saved, const [
      'shiftMissionClaimed',
    ], false);
    fastCheckoutClaimed = _readBoolAny(saved, const [
      'fastCheckoutClaimed',
    ], false);
    _dailyMissionClaimedOn = _readDateAny(saved, const [
      'dailyMissionClaimedOn',
    ]);
    totalCoinsEarned = _readIntAny(saved, const [
      'totalCoinsEarned',
      'coinsEarned',
    ], 0);
    stockedTotal = _readIntAny(saved, const [
      'stockedTotal',
      'itemsStocked',
    ], 0);
    upgradesBought = _readIntAny(saved, const [
      'upgradesBought',
      'upgradesPurchased',
    ], 0);
    questStage = _readIntAny(saved, const ['questStage'], 0);
    questBaseline = _readIntAny(saved, const ['questBaseline'], 0);
    bagLevel = _readIntAny(saved, const ['bagLevel'], 1, minimum: 1);
    shelfLevel = _readIntAny(saved, const ['shelfLevel'], 1, minimum: 1);
    priceLevel = _readIntAny(saved, const ['priceLevel'], 1, minimum: 1);
    speedLevel = _readIntAny(saved, const ['speedLevel'], 1, minimum: 1);
    checkoutLevel = _readIntAny(
      saved,
      const ['checkoutLevel', 'checkoutSpeedLevel'],
      1,
      minimum: 1,
      maximum: 10,
    );
    restockLevel = _readIntAny(
      saved,
      const ['restockLevel', 'restockFlowLevel'],
      1,
      minimum: 1,
      maximum: 10,
    );
    totalActions = _readIntAny(saved, const ['totalActions', 'actions'], 0);
    highestBalance = _readIntAny(saved, const ['highestBalance'], coins);
    highestScore = _readIntAny(saved, const ['highestScore'], 0);
    totalPlaySeconds = _readDoubleAny(saved, const [
      'totalPlaySeconds',
      'playSeconds',
    ], 0);
    adsRemoved = _readBoolAny(saved, const ['adsRemoved', 'removeAds'], false);
    muted = _readBoolAny(saved, const ['muted'], false);
    onboardingComplete = _readBoolAny(saved, const [
      'onboardingComplete',
      'tutorialComplete',
    ], false);
    _lastEmergencyStockAt = _readDateAny(saved, const ['lastEmergencyStockAt']);
    _rewardLastClaimed.clear();
    final restoredRewardClaims = saved['rewardLastClaimed'];
    if (restoredRewardClaims is Map) {
      for (final entry in restoredRewardClaims.entries) {
        final placement = _enumByName(RewardPlacement.values, entry.key);
        final claimedAt = entry.value is String
            ? DateTime.tryParse(entry.value as String)
            : null;
        if (placement != null && claimedAt != null) {
          _rewardLastClaimed[placement] = claimedAt;
        }
      }
    }
    _rewardClaimDay = _readDateAny(saved, const ['rewardClaimDay']);
    _rewardClaimsToday = _readIntAny(
      saved,
      const ['rewardClaimsToday'],
      0,
      maximum: MonetizationPolicy.rewardedDailyLimit,
    );
    _lastRewardedAt = _readDateAny(saved, const ['lastRewardedAt']);
    _lastInterstitialAt = _readDateAny(saved, const ['lastInterstitialAt']);
    _interstitialDay = _readDateAny(saved, const ['interstitialDay']);
    _interstitialsToday = _readIntAny(
      saved,
      const ['interstitialsToday'],
      0,
      maximum: MonetizationPolicy.interstitialDailyLimit,
    );
    _deliveredTransactionIds
      ..clear()
      ..addAll(
        saved['deliveredTransactions'] is List
            ? (saved['deliveredTransactions'] as List)
                  .whereType<String>()
                  .where((id) => id.trim().isNotEmpty)
                  .take(500)
            : const <String>[],
      );
    dailyBonus = DailyBonusState.fromJson(saved['dailyBonus']);
    _achievementProgress = AchievementCatalog.restoreProgress(
      saved['achievements'],
    );
    _performanceHistory = PerformanceSample.restoreList(
      saved['performanceHistory'],
    );
    _leaderboard = LeaderboardEntry.top(saved['leaderboard']);
    _staff.clear();
    final restoredStaff = saved['staff'];
    if (restoredStaff is List) {
      for (final item in restoredStaff) {
        final itemMap = _asStringMap(item);
        if (itemMap == null) {
          continue;
        }
        final role = _enumByName(StaffRole.values, itemMap['role']);
        if (role == null) {
          continue;
        }
        final member = _ensureStaff(role);
        member.level = max(
          member.level,
          _readIntAny(itemMap, const ['level'], 0),
        );
        member.hired =
            member.hired ||
            _readBoolAny(itemMap, const ['hired', 'isHired'], false);
        member.workerCount = max(
          member.workerCount,
          _readIntAny(
            itemMap,
            const ['workerCount', 'count'],
            member.hired ? 1 : 0,
            maximum: GameBalance.maxWorkersPerRole,
          ),
        );
        member.hired = member.hired || member.workerCount > 0;
        member.assignment =
            _enumByName(StaffAssignment.values, itemMap['assignment']) ??
            StaffMember.defaultAssignmentFor(role);
      }
    }
    final legacyCashierHired = _readBoolAny(saved, const [
      'cashierHired',
      'hasCashier',
    ], false);
    if (legacyCashierHired) {
      final cashier = _ensureStaff(StaffRole.cashier);
      cashier
        ..hired = true
        ..workerCount = max(1, cashier.workerCount)
        ..level = max(
          cashier.level,
          _readIntAny(saved, const ['cashierLevel'], 1, minimum: 1),
        );
    }

    _departments.clear();
    _departmentShelfStock.clear();
    final restoredDepartments = saved['departments'];
    if (restoredDepartments is List) {
      final departmentByType = <DepartmentType, DepartmentState>{};
      for (final item in restoredDepartments) {
        final itemMap = _asStringMap(item);
        if (itemMap == null) {
          continue;
        }
        final type = _enumByName(DepartmentType.values, itemMap['type']);
        if (type == null) {
          continue;
        }
        final restored = DepartmentState(
          type: type,
          level: _readIntAny(itemMap, const ['level'], 0),
          unlocked: _readBoolAny(itemMap, const [
            'unlocked',
            'isUnlocked',
          ], false),
          activated: _readBoolAny(itemMap, const ['activated'], false),
          itemsSold: _readIntAny(itemMap, const ['itemsSold'], 0),
        );
        _departmentShelfStock[type] = max(
          _departmentShelfStock[type] ?? 0,
          _readIntAny(itemMap, const ['shelfStock'], 0),
        );
        final previous = departmentByType[type];
        if (previous == null) {
          departmentByType[type] = restored;
        } else {
          previous.level = max(previous.level, restored.level);
          previous.unlocked = previous.unlocked || restored.unlocked;
          previous.activated = previous.activated || restored.activated;
          previous.itemsSold = max(previous.itemsSold, restored.itemsSold);
        }
      }
      _departments.addAll(departmentByType.values);
    }

    _inventoryByCategory.clear();
    _restoredInventoryPresent =
        saved.containsKey('inventory') || saved.containsKey('storageInventory');
    final restoredInventory = saved['inventory'] ?? saved['storageInventory'];
    if (restoredInventory is Map) {
      for (final entry in restoredInventory.entries) {
        if (entry.key is String && entry.value is num) {
          _inventoryByCategory[entry.key as String] = max(
            0,
            (entry.value as num).toInt(),
          );
        }
      }
    }

    _pendingDeliveries.clear();
    final restoredDeliveries = saved['deliveries'];
    if (restoredDeliveries is List) {
      final seenDeliveryIds = <String>{};
      for (final item in restoredDeliveries) {
        final itemMap = _asStringMap(item);
        if (itemMap == null) {
          continue;
        }
        final id = itemMap['id'] is String ? itemMap['id'] as String : '';
        final category = itemMap['category'] is String
            ? (itemMap['category'] as String).trim()
            : '';
        final readyAt = _readDateAny(itemMap, const ['readyAt']);
        if (id.isEmpty ||
            category.isEmpty ||
            readyAt == null ||
            !seenDeliveryIds.add(id)) {
          continue;
        }
        _pendingDeliveries.add(
          InventoryDelivery(
            id: id,
            category: category,
            quantity: _readIntAny(itemMap, const ['quantity'], 0),
            cost: _readIntAny(itemMap, const ['cost'], 0),
            readyAt: readyAt,
            completed: _readBoolAny(itemMap, const ['completed'], false),
          ),
        );
      }
    }
    final restoredX = _readDoubleAny(saved, const [
      'playerX',
      'playerPositionX',
    ], 0.5);
    final restoredY = _readDoubleAny(saved, const [
      'playerY',
      'playerPositionY',
    ], 0.72);
    playerPosition = Offset(
      restoredX.clamp(0.06, 0.94),
      restoredY.clamp(0.09, 0.94),
    );
    _restoreCheckoutStations(saved['checkoutStations']);
    _reconcileAfterLoad();
  }

  void _resetCheckoutStations() {
    for (final station in _checkoutStations) {
      station.unlocked = station.id == primaryCheckoutStationId;
      station.active = station.id == primaryCheckoutStationId;
    }
    _checkoutQueues
      ..clear()
      ..addEntries(
        checkoutStationIds.map(
          (id) => MapEntry<String, List<MarketCustomer>>(
            id,
            <MarketCustomer>[],
          ),
        ),
      );
  }

  void _restoreCheckoutStations(Object? rawStations) {
    _resetCheckoutStations();
    if (rawStations is List) {
      for (final rawStation in rawStations) {
        if (rawStation is! Map) {
          continue;
        }
        final station = Map<String, dynamic>.from(rawStation);
        final id = station['id'];
        if (id is! String || !checkoutStationIds.contains(id)) {
          continue;
        }
        final state = _checkoutStations.firstWhere((item) => item.id == id);
        state.unlocked = station['unlocked'] == true;
        state.active = station['active'] == true && state.unlocked;
        _checkoutQueues.putIfAbsent(id, () => <MarketCustomer>[]);
      }
    }

    final primary = _checkoutStations.first;
    primary.unlocked = true;
    primary.active = true;
    _unlockCheckoutStationsForLevel();
  }

  void _unlockCheckoutStationsForLevel() {
    for (final station in _checkoutStations.skip(1)) {
      final requiredLevel = station.id == 'checkout-2'
          ? checkout2UnlockLevel
          : checkout3UnlockLevel;
      if (checkoutLevel >= requiredLevel) {
        final wasUnlocked = station.unlocked;
        station.unlocked = true;
        if (!wasUnlocked) {
          station.active = true;
        }
        _queueForCheckout(station.id);
      }
    }
  }

  void _reconcileAfterLoad() {
    _reconcileProgression(announce: false);

    for (final entry in _staff.entries) {
      if (entry.value.hired && entry.value.level < 1) {
        entry.value.level = 1;
      }
      if (entry.value.hired) {
        entry.value.workerCount = max(
          1,
          entry.value.workerCount,
        ).clamp(1, GameBalance.maxWorkersPerRole);
      } else {
        entry.value.level = max(0, entry.value.level);
        entry.value.workerCount = 0;
      }
    }

    if (!isStaffHired(StaffRole.stocker) && _stockerLoad > 0) {
      final type = _stockerDepartment ?? DepartmentType.generalGoods;
      final category = departmentCategory(type);
      _inventoryByCategory[category] = inventoryFor(category) + _stockerLoad;
      _stockerLoad = 0;
      _stockerDepartment = null;
      stockerPosition = stockerPickupZone;
    }
    if (_stockerLoad > 0 &&
        (_stockerDepartment == null ||
            !isDepartmentUnlocked(_stockerDepartment!))) {
      _stockerDepartment = DepartmentType.generalGoods;
    }
    _stockerLoad = _stockerLoad.clamp(0, storageCapacity);
    stockerPosition = Offset(
      stockerPosition.dx.clamp(0.06, 0.94),
      stockerPosition.dy.clamp(0.09, 0.94),
    );

    final seen = <int>{};
    for (final customer in customers) {
      if (customer.id < 0 || !seen.add(customer.id)) {
        while (seen.contains(_customerId)) {
          _customerId++;
        }
        customer.id = _customerId;
        seen.add(_customerId);
        _customerId++;
      } else {
        _customerId = max(_customerId, customer.id + 1);
      }
      customer.position = Offset(
        customer.position.dx.clamp(-0.08, 1.08),
        customer.position.dy.clamp(-0.12, 1.0),
      );
    }

    carried = carried.clamp(0, bagCapacity);
    if (carried == 0) {
      _carriedDepartment = null;
    } else if (_carriedDepartment == null ||
        !isDepartmentUnlocked(_carriedDepartment!)) {
      _carriedDepartment = DepartmentType.generalGoods;
    }
    if (!isDepartmentUnlocked(_selectedRestockDepartment)) {
      _selectedRestockDepartment = DepartmentType.generalGoods;
    }
    shelfStock = shelfStock.clamp(0, shelfCapacity);
    for (final type in DepartmentType.values) {
      if (type == DepartmentType.generalGoods) {
        continue;
      }
      _departmentShelfStock[type] = departmentStock(
        type,
      ).clamp(0, departmentCapacity(type));
    }
    bakeryReadyStock = bakeryReadyStock.clamp(
      0,
      GameBalance.bakeryReadyCapacity,
    );
    checkoutLevel = checkoutLevel.clamp(1, 10);
    restockLevel = restockLevel.clamp(1, 10);

    var remainingCapacity = storageCapacity;
    for (final key in _inventoryByCategory.keys.toList()..sort()) {
      final value = inventoryFor(key).clamp(0, remainingCapacity);
      _inventoryByCategory[key] = value;
      remainingCapacity -= value;
    }
    _pendingDeliveries.removeWhere(
      (delivery) =>
          delivery.id.isEmpty ||
          delivery.category.trim().isEmpty ||
          delivery.quantity <= 0 ||
          delivery.cost < 0,
    );
  }

  void _reconcileProgression({required bool announce}) {
    final level = storeLevel;
    for (final department in _departments) {
      final definition = DepartmentCatalog.find(department.type);
      if (definition == null) {
        continue;
      }
      if (department.type == DepartmentType.generalGoods) {
        _activateDepartment(department, announce: false);
        continue;
      }
      if (!department.unlocked &&
          definition.autoUnlock &&
          level >= definition.unlockLevel) {
        _activateDepartment(department, announce: announce);
      } else if (department.unlocked && !department.activated) {
        _activateDepartment(department, announce: false);
      }
    }
    if (bakeryUnlocked && !_bakeryActivated) {
      _bakeryActivated = true;
      bakeryReadyStock = max(bakeryReadyStock, GameBalance.bakeryStarterStock);
    }
  }

  int _readIntAny(
    Map<String, dynamic> data,
    List<String> keys,
    int fallback, {
    int minimum = 0,
    int maximum = 1000000000,
  }) {
    for (final key in keys) {
      final value = data[key];
      if (value is num && value.isFinite) {
        return value.toInt().clamp(minimum, maximum);
      }
    }
    return fallback.clamp(minimum, maximum);
  }

  double _readDoubleAny(
    Map<String, dynamic> data,
    List<String> keys,
    double fallback,
  ) {
    for (final key in keys) {
      final value = data[key];
      if (value is num && value.isFinite) {
        return max(0, value.toDouble());
      }
    }
    return max(0, fallback);
  }

  bool _readBoolAny(
    Map<String, dynamic> data,
    List<String> keys,
    bool fallback,
  ) {
    for (final key in keys) {
      final value = data[key];
      if (value is bool) {
        return value;
      }
    }
    return fallback;
  }

  DateTime? _readDateAny(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = data[key];
      if (value is String) {
        final parsed = DateTime.tryParse(value);
        if (parsed != null) {
          return parsed;
        }
      }
    }
    return null;
  }

  Map<String, dynamic>? _asStringMap(Object? value) {
    if (value is! Map) {
      return null;
    }
    return <String, dynamic>{
      for (final entry in value.entries)
        if (entry.key is String) entry.key as String: entry.value,
    };
  }

  T? _enumByName<T extends Enum>(List<T> values, Object? rawName) {
    if (rawName is! String) {
      return null;
    }
    for (final value in values) {
      if (value.name == rawName) {
        return value;
      }
    }
    return null;
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
    final currentLevel = storeLevel;
    _reconcileProgression(announce: currentLevel > _lastObservedStoreLevel);
    _lastObservedStoreLevel = currentLevel;
    _updateHighs();
    _evaluateAchievements();
    _markDirty(immediate: immediate);
    notifyListeners();
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

  void _resetDailyMonetizationCountersIfNeeded() {
    final today = _now();
    if (_rewardClaimDay == null || !_sameCalendarDay(_rewardClaimDay!, today)) {
      _rewardClaimDay = DateTime(today.year, today.month, today.day);
      _rewardClaimsToday = 0;
    }
    if (_interstitialDay == null ||
        !_sameCalendarDay(_interstitialDay!, today)) {
      _interstitialDay = DateTime(today.year, today.month, today.day);
      _interstitialsToday = 0;
    }
  }

  bool _sameCalendarDay(DateTime first, DateTime second) {
    return first.year == second.year &&
        first.month == second.month &&
        first.day == second.day;
  }

  int _upgradeCost(int base, int level) {
    return (base * pow(1.55, level - 1)).round();
  }

  bool _near(Offset a, Offset b, double radius) => (a - b).distance <= radius;
}
