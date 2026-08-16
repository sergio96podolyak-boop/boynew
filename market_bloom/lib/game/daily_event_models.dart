import 'game_models.dart';

/// Immutable modifiers for one calendar-day market event.
class DailyEventModifiers {
  const DailyEventModifiers({
    this.customerSpawnIntervalMultiplier = 1,
    this.salePriceMultiplier = 1,
    this.bakeryProductionMultiplier = 1,
    this.deliveryDelayMultiplier = 1,
    this.stockOrderCostMultiplier = 1,
  });

  final double customerSpawnIntervalMultiplier;
  final double salePriceMultiplier;
  final double bakeryProductionMultiplier;
  final double deliveryDelayMultiplier;
  final double stockOrderCostMultiplier;
}

class DailyEventDefinition {
  const DailyEventDefinition({
    required this.id,
    required this.type,
    required this.title,
    required this.description,
    required this.effectSummary,
    required this.modifiers,
  });

  final String id;
  final MarketEventType type;
  final String title;
  final String description;
  final String effectSummary;
  final DailyEventModifiers modifiers;
}

/// Deterministic calendar rotation. The same local calendar day always maps to
/// the same event, including after reinstalling or restoring an older save.
abstract final class DailyEventCatalog {
  static const List<DailyEventDefinition> all = <DailyEventDefinition>[
    DailyEventDefinition(
      id: 'rainy_day',
      type: MarketEventType.rainyDay,
      title: 'Rainy Day Rush',
      description: 'More neighbors stop by while deliveries move quickly.',
      effectSummary: 'Customers arrive 12% faster · deliveries 15% faster',
      modifiers: DailyEventModifiers(
        customerSpawnIntervalMultiplier: .88,
        deliveryDelayMultiplier: .85,
      ),
    ),
    DailyEventDefinition(
      id: 'flash_sale',
      type: MarketEventType.flashSale,
      title: 'Flash Sale',
      description: 'Promoted products sell for more during today’s rush.',
      effectSummary: 'Sale value +20% · customers arrive 8% faster',
      modifiers: DailyEventModifiers(
        customerSpawnIntervalMultiplier: .92,
        salePriceMultiplier: 1.20,
      ),
    ),
    DailyEventDefinition(
      id: 'inspector_visit',
      type: MarketEventType.inspectorVisit,
      title: 'Inspector Visit',
      description: 'Suppliers support a well-prepared and efficient market.',
      effectSummary: 'Stock orders cost 15% less · Bakery works 10% faster',
      modifiers: DailyEventModifiers(
        stockOrderCostMultiplier: .85,
        bakeryProductionMultiplier: .90,
      ),
    ),
    DailyEventDefinition(
      id: 'heatwave',
      type: MarketEventType.heatwave,
      title: 'Heatwave',
      description: 'Foot traffic eases and fresh Bakery production takes longer.',
      effectSummary: 'Customers arrive 10% slower · Bakery takes 20% longer',
      modifiers: DailyEventModifiers(
        customerSpawnIntervalMultiplier: 1.10,
        bakeryProductionMultiplier: 1.20,
      ),
    ),
  ];

  static DailyEventDefinition forDate(DateTime value) {
    final date = DateTime(value.year, value.month, value.day);
    final epoch = DateTime(2024);
    final dayIndex = date.difference(epoch).inDays;
    return all[dayIndex % all.length];
  }

  static String dateKey(DateTime value) {
    final date = DateTime(value.year, value.month, value.day);
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }
}
