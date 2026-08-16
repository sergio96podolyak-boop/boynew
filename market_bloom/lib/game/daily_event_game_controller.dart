import 'dart:math';

import 'daily_event_models.dart';
import 'game_controller.dart';
import 'game_models.dart';

/// Production controller extension for the roadmap's recurring Daily Events.
///
/// Existing GameController behavior remains the source of truth. This class
/// only overrides public calculation seams already used by the simulation.
class DailyEventGameController extends GameController {
  // The local clock is retained here as well as passed to GameController so a
  // calendar rollover can refresh the event without touching base internals.
  // ignore: use_super_parameters
  DailyEventGameController({
    required super.storage,
    required super.monetization,
    super.random,
    DateTime Function()? now,
    DailyEventDefinition? forcedEvent,
  }) : _eventNow = now ?? DateTime.now,
       _forcedEvent = forcedEvent,
       _event = forcedEvent ?? DailyEventCatalog.forDate((now ?? DateTime.now)()),
       _eventDateKey = DailyEventCatalog.dateKey((now ?? DateTime.now)()),
       super(now: now);

  final DateTime Function() _eventNow;
  final DailyEventDefinition? _forcedEvent;
  DailyEventDefinition _event;
  String _eventDateKey;

  DailyEventDefinition get dailyEvent => _event;
  String get dailyEventDateKey => _eventDateKey;

  bool refreshDailyEvent() {
    if (_forcedEvent != null) return false;
    final now = _eventNow();
    final nextKey = DailyEventCatalog.dateKey(now);
    if (nextKey == _eventDateKey) return false;
    _eventDateKey = nextKey;
    _event = DailyEventCatalog.forDate(now);
    notifyListeners();
    return true;
  }

  @override
  void tick(double dt) {
    refreshDailyEvent();
    super.tick(dt);
  }

  @override
  MarketEventType get activeMarketEvent {
    final shiftEvent = super.activeMarketEvent;
    return shiftEvent == MarketEventType.none ? dailyEvent.type : shiftEvent;
  }

  @override
  double get customerSpawnInterval => max(
    .65,
    super.customerSpawnInterval *
        dailyEvent.modifiers.customerSpawnIntervalMultiplier,
  );

  @override
  int get itemPrice => max(
    1,
    (super.itemPrice * dailyEvent.modifiers.salePriceMultiplier).round(),
  );

  @override
  double get bakeryProductionSeconds => max(
    2.5,
    super.bakeryProductionSeconds *
        dailyEvent.modifiers.bakeryProductionMultiplier,
  );

  @override
  Duration get effectiveInventoryOrderDelay => Duration(
    milliseconds: max(
      1000,
      (super.effectiveInventoryOrderDelay.inMilliseconds *
              dailyEvent.modifiers.deliveryDelayMultiplier)
          .round(),
    ),
  );

  int adjustedDepartmentOrderCost(DepartmentType type) {
    final definition = DepartmentCatalog.find(type);
    if (definition == null) return 0;
    return max(
      0,
      (definition.orderCost * dailyEvent.modifiers.stockOrderCostMultiplier)
          .round(),
    );
  }

  @override
  bool canOrderDepartmentStock(DepartmentType type) {
    final definition = DepartmentCatalog.find(type);
    if (definition == null ||
        !isDepartmentUnlocked(type) ||
        hasPendingDepartmentDelivery(type) ||
        coins < adjustedDepartmentOrderCost(type)) {
      return false;
    }
    final pendingQuantity = pendingDeliveries.fold<int>(
      0,
      (sum, delivery) => sum + delivery.quantity,
    );
    return totalStoredInventory + pendingQuantity + definition.orderQuantity <=
        storageCapacity;
  }

  @override
  InventoryDelivery? placeDepartmentOrder(DepartmentType type) {
    final definition = DepartmentCatalog.find(type);
    if (definition == null || !canOrderDepartmentStock(type)) return null;
    return placeInventoryOrder(
      definition.category,
      definition.orderQuantity,
      cost: adjustedDepartmentOrderCost(type),
    );
  }
}
