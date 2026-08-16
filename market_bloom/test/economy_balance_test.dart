import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomarket/game/economy_calculator.dart';
import 'package:pomarket/game/game_models.dart';

void main() {
  group('department supply economy', () {
    const baseItemPrice = 6;

    test('every stock order is profitable at its unlock baseline', () {
      for (final definition in DepartmentCatalog.all) {
        expect(
          definition.grossProfitForBasePrice(baseItemPrice),
          greaterThan(0),
          reason: definition.name,
        );
      }
    });

    test('stock orders retain a sustainable gross margin', () {
      for (final definition in DepartmentCatalog.all) {
        expect(
          definition.grossMarginForBasePrice(baseItemPrice),
          inInclusiveRange(0.28, 0.45),
          reason: definition.name,
        );
      }
    });

    test('higher-tier departments create larger batch profit', () {
      final profits = <DepartmentType, int>{
        for (final definition in DepartmentCatalog.all)
          definition.type:
              definition.grossProfitForBasePrice(baseItemPrice),
      };

      expect(
        profits[DepartmentType.refrigerated]!,
        greaterThan(profits[DepartmentType.produce]!),
      );
      expect(
        profits[DepartmentType.electronics]!,
        greaterThanOrEqualTo(profits[DepartmentType.refrigerated]!),
      );
      expect(profits[DepartmentType.beauty]!, greaterThan(0));
    });

    test('estimated per-item profit uses the real batch order cost', () {
      final general = DepartmentCatalog.find(DepartmentType.generalGoods)!;
      final electronics = DepartmentCatalog.find(DepartmentType.electronics)!;

      expect(
        EconomyCalculator.estimatedProfitPerItem(general, sellingPrice: 6),
        2,
      );
      expect(
        EconomyCalculator.estimatedProfitPerItem(
          electronics,
          sellingPrice: 18,
        ),
        6,
      );
    });

    test('losses remain visible instead of being clamped to a fake profit', () {
      const lossMaking = DepartmentDefinition(
        type: DepartmentType.generalGoods,
        name: 'Test',
        description: 'Test',
        unlockLevel: 1,
        unlockCost: 0,
        icon: Icons.store,
        color: Color(0xFF000000),
        category: 'Test',
        emoji: 'T',
        displayZone: Offset.zero,
        baseShelfCapacity: 1,
        starterShelfStock: 0,
        starterStorageStock: 0,
        orderQuantity: 3,
        orderCost: 10,
        priceBonus: 0,
      );

      expect(
        EconomyCalculator.estimatedProfitPerItem(
          lossMaking,
          sellingPrice: 2,
        ),
        -2,
      );
    });
  });
}
