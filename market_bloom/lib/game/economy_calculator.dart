import 'dart:math' as math;

import 'game_models.dart';

/// Small integer helper kept public so management screens can share stock
/// thresholds without importing another calculation library.
int max(int left, int right) => math.max(left, right);

/// Pure economy calculations shared by gameplay presentation and tests.
abstract final class EconomyCalculator {
  static int grossRevenueForOrder(
    DepartmentDefinition definition, {
    required int sellingPrice,
  }) {
    return sellingPrice * definition.orderQuantity;
  }

  static int grossProfitForOrder(
    DepartmentDefinition definition, {
    required int sellingPrice,
  }) {
    return grossRevenueForOrder(definition, sellingPrice: sellingPrice) -
        definition.orderCost;
  }

  /// Exact supply cost allocated to one item in the batch.
  static double unitCost(DepartmentDefinition definition) {
    if (definition.orderQuantity <= 0) return 0;
    return definition.orderCost / definition.orderQuantity;
  }

  /// Conservative whole-coin profit shown by the management UI.
  /// Losses deliberately remain negative and visible.
  static int estimatedProfitPerItem(
    DepartmentDefinition definition, {
    required int sellingPrice,
  }) {
    final quantity = definition.orderQuantity;
    if (quantity <= 0) return sellingPrice;
    final totalProfit = grossProfitForOrder(
      definition,
      sellingPrice: sellingPrice,
    );
    if (totalProfit >= 0) return totalProfit ~/ quantity;
    return -((-totalProfit + quantity - 1) ~/ quantity);
  }

  /// Gross margin for the actual order and current selling price.
  /// Negative values are retained so loss-making products stay obvious.
  static double grossMargin(
    DepartmentDefinition definition, {
    required int sellingPrice,
  }) {
    final revenue = grossRevenueForOrder(
      definition,
      sellingPrice: sellingPrice,
    );
    if (revenue <= 0) return 0;
    return grossProfitForOrder(definition, sellingPrice: sellingPrice) /
        revenue;
  }
}
