import 'package:flutter_test/flutter_test.dart';
import 'package:pomarket/game/economy_calculator.dart';
import 'package:pomarket/game/game_controller.dart';
import 'package:pomarket/game/game_models.dart';
import 'package:pomarket/game/operating_cost_policy.dart';
import 'package:pomarket/services/game_storage.dart';
import 'package:pomarket/services/monetization_service.dart';

void main() {
  const expectedLevelOne = <DepartmentType, int>{
    DepartmentType.generalGoods: 0,
    DepartmentType.bakery: 2,
    DepartmentType.produce: 3,
    DepartmentType.refrigerated: 5,
    DepartmentType.beauty: 7,
    DepartmentType.electronics: 9,
  };
  const expectedLevelTen = <DepartmentType, int>{
    DepartmentType.generalGoods: 3,
    DepartmentType.bakery: 11,
    DepartmentType.produce: 12,
    DepartmentType.refrigerated: 23,
    DepartmentType.beauty: 25,
    DepartmentType.electronics: 36,
  };

  DepartmentState activeDepartment(DepartmentType type, {int level = 1}) {
    return DepartmentState(
      type: type,
      level: level,
      unlocked: true,
      activated: true,
    );
  }

  group('OperatingCostPolicy department values', () {
    for (final type in DepartmentType.values) {
      test('${type.name} has audited level-one and level-ten costs', () {
        final department = activeDepartment(type);

        final levelOne = OperatingCostPolicy.operatingCostPerShift(
          department,
          1,
        );
        final levelTen = OperatingCostPolicy.operatingCostPerShift(
          department,
          10,
        );

        expect(levelOne, expectedLevelOne[type]);
        expect(levelTen, expectedLevelTen[type]);
        expect(levelTen, greaterThan(levelOne));
      });
    }
  });

  test('locked and inactive departments cost zero', () {
    for (final type in DepartmentType.values) {
      final locked = DepartmentState(
        type: type,
        level: 10,
        unlocked: false,
        activated: false,
      );
      final inactive = DepartmentState(
        type: type,
        level: 10,
        unlocked: true,
        activated: false,
      );

      expect(
        OperatingCostPolicy.operatingCostPerShift(locked, 10),
        0,
        reason: '${type.name} locked',
      );
      expect(
        OperatingCostPolicy.operatingCostPerShift(inactive, 10),
        0,
        reason: '${type.name} inactive',
      );
    }
  });

  test('non-positive levels safely normalize to level one', () {
    for (final type in DepartmentType.values) {
      final department = activeDepartment(type);
      final levelOne = OperatingCostPolicy.operatingCostPerShift(
        department,
        1,
      );

      expect(
        OperatingCostPolicy.operatingCostPerShift(department, 0),
        levelOne,
        reason: '${type.name} level zero',
      );
      expect(
        OperatingCostPolicy.operatingCostPerShift(department, -8),
        levelOne,
        reason: '${type.name} negative level',
      );
    }
  });

  test('cost scaling is monotonic across levels one through ten', () {
    for (final type in DepartmentType.values) {
      final department = activeDepartment(type);
      var previous = OperatingCostPolicy.operatingCostPerShift(department, 1);

      for (var level = 2; level <= 10; level++) {
        final current = OperatingCostPolicy.operatingCostPerShift(
          department,
          level,
        );
        expect(
          current,
          greaterThanOrEqualTo(previous),
          reason: '${type.name} level $level',
        );
        previous = current;
      }
    }
  });

  test('advanced departments cost more than basic departments', () {
    for (final level in <int>[1, 5, 10]) {
      final costs = <DepartmentType, int>{
        for (final type in DepartmentType.values)
          type: OperatingCostPolicy.operatingCostPerShift(
            activeDepartment(type),
            level,
          ),
      };

      expect(
        costs[DepartmentType.bakery]!,
        greaterThan(costs[DepartmentType.generalGoods]!),
      );
      expect(
        costs[DepartmentType.produce]!,
        greaterThan(costs[DepartmentType.bakery]!),
      );
      expect(
        costs[DepartmentType.refrigerated]!,
        greaterThan(costs[DepartmentType.produce]!),
      );
      expect(
        costs[DepartmentType.beauty]!,
        greaterThan(costs[DepartmentType.refrigerated]!),
      );
      expect(
        costs[DepartmentType.electronics]!,
        greaterThan(costs[DepartmentType.beauty]!),
      );
    }
  });

  test('the same department and level always produce the same result', () {
    for (final type in DepartmentType.values) {
      final department = activeDepartment(type, level: 7);
      final expected = OperatingCostPolicy.operatingCostPerShift(
        department,
        7,
      );

      for (var iteration = 0; iteration < 25; iteration++) {
        expect(
          OperatingCostPolicy.operatingCostPerShift(department, 7),
          expected,
          reason: '${type.name}, iteration $iteration',
        );
      }
    }
  });

  test('level-one departments remain profitable after one shift cost', () {
    const baseItemPrice = 6;

    for (final definition in DepartmentCatalog.all) {
      final sellingPrice = baseItemPrice + definition.priceBonus;
      final grossProfit = EconomyCalculator.grossProfitForOrder(
        definition,
        sellingPrice: sellingPrice,
      );
      final operatingCost = OperatingCostPolicy.operatingCostPerShift(
        activeDepartment(definition.type),
        1,
      );

      expect(
        grossProfit - operatingCost,
        greaterThan(0),
        reason: definition.name,
      );
    }
  });

  test('policy calculation does not mutate department state', () {
    final department = activeDepartment(DepartmentType.beauty, level: 4);
    final beforeType = department.type;
    final beforeLevel = department.level;
    final beforeUnlocked = department.unlocked;
    final beforeActivated = department.activated;

    final result = OperatingCostPolicy.operatingCostPerShift(department, 9);

    expect(result, 23);
    expect(department.type, beforeType);
    expect(department.level, beforeLevel);
    expect(department.unlocked, beforeUnlocked);
    expect(department.activated, beforeActivated);
  });

  test('projecting operating costs does not mutate coins or game state', () async {
    final controller = GameController(
      storage: MemoryGameStorage(),
      monetization: PreviewMonetizationService(),
    );
    await controller.initialize();

    final coinsBefore = controller.coins;
    final departmentsBefore = <
      ({DepartmentType type, int level, bool unlocked, bool activated})
    >[
      for (final department in controller.departments)
        (
          type: department.type,
          level: department.level,
          unlocked: department.unlocked,
          activated: department.activated,
        ),
    ];

    final first = controller.projectedDepartmentOperatingCosts;
    final second = controller.projectedDepartmentOperatingCosts;

    expect(second, first);
    expect(controller.coins, coinsBefore);
    expect(
      <({DepartmentType type, int level, bool unlocked, bool activated})>[
        for (final department in controller.departments)
          (
            type: department.type,
            level: department.level,
            unlocked: department.unlocked,
            activated: department.activated,
          ),
      ],
      departmentsBefore,
    );
  });

  test('total cost includes only unlocked active departments', () {
    final departments = <DepartmentState>[
      activeDepartment(DepartmentType.generalGoods, level: 3),
      activeDepartment(DepartmentType.bakery, level: 2),
      DepartmentState(
        type: DepartmentType.electronics,
        level: 10,
        unlocked: false,
        activated: false,
      ),
    ];

    expect(
      OperatingCostPolicy.totalDepartmentOperatingCosts(departments),
      3,
    );
  });
}
