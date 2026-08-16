import 'package:flutter_test/flutter_test.dart';
import 'package:pomarket/game/economy_calculator.dart';
import 'package:pomarket/game/game_controller.dart';
import 'package:pomarket/game/game_models.dart';
import 'package:pomarket/game/operating_cost_policy.dart';
import 'package:pomarket/services/game_storage.dart';
import 'package:pomarket/services/monetization_service.dart';

void main() {
  group('payroll policy', () {
    test('defines a payroll value for every staff role', () {
      final expectedLevelOne = <StaffRole, int>{
        StaffRole.cashier: 5,
        StaffRole.stocker: 5,
        StaffRole.cleaner: 4,
        StaffRole.baker: 6,
        StaffRole.manager: 135,
        StaffRole.courier: 6,
        StaffRole.promoter: 8,
      };

      for (final entry in expectedLevelOne.entries) {
        expect(
          OperatingCostPolicy.payrollForRole(
            entry.key,
            level: 1,
            workerCount: 1,
          ),
          entry.value,
          reason: entry.key.name,
        );
      }
    });

    test('payroll increases predictably with employee level', () {
      expect(
        OperatingCostPolicy.payrollForRole(
          StaffRole.cashier,
          level: 1,
          workerCount: 1,
        ),
        5,
      );
      expect(
        OperatingCostPolicy.payrollForRole(
          StaffRole.cashier,
          level: 5,
          workerCount: 1,
        ),
        13,
      );
      expect(
        OperatingCostPolicy.payrollForRole(
          StaffRole.promoter,
          level: 5,
          workerCount: 1,
        ),
        20,
      );
    });

    test('worker count scales payroll linearly without hidden multipliers', () {
      final oneWorker = OperatingCostPolicy.payrollForRole(
        StaffRole.stocker,
        level: 4,
        workerCount: 1,
      );
      final threeWorkers = OperatingCostPolicy.payrollForRole(
        StaffRole.stocker,
        level: 4,
        workerCount: 3,
      );

      expect(oneWorker, 11);
      expect(threeWorkers, oneWorker * 3);
    });

    test('manager payroll offsets most passive manager income', () {
      for (final level in <int>[1, 5, 10]) {
        final payroll = OperatingCostPolicy.payrollForRole(
          StaffRole.manager,
          level: level,
          workerCount: 1,
        );
        final estimatedShiftIncome = 75 * 2 * level;
        expect(payroll, greaterThanOrEqualTo(estimatedShiftIncome * 0.8));
        expect(payroll, lessThan(estimatedShiftIncome));
      }
    });
  });

  group('department operating cost policy', () {
    test('starter General Goods remains free at level one', () {
      expect(
        OperatingCostPolicy.departmentOperatingCost(
          DepartmentType.generalGoods,
          level: 1,
        ),
        0,
      );
      expect(
        OperatingCostPolicy.departmentOperatingCost(
          DepartmentType.generalGoods,
          level: 10,
        ),
        3,
      );
    });

    test('advanced department costs rise by tier and level', () {
      expect(
        OperatingCostPolicy.departmentOperatingCost(
          DepartmentType.bakery,
          level: 1,
        ),
        2,
      );
      expect(
        OperatingCostPolicy.departmentOperatingCost(
          DepartmentType.refrigerated,
          level: 5,
        ),
        13,
      );
      expect(
        OperatingCostPolicy.departmentOperatingCost(
          DepartmentType.electronics,
          level: 10,
        ),
        36,
      );
    });

    test('locked and inactive departments are never charged', () {
      final departments = <DepartmentState>[
        DepartmentState(
          type: DepartmentType.generalGoods,
          level: 1,
          unlocked: true,
          activated: true,
        ),
        DepartmentState(
          type: DepartmentType.electronics,
          level: 10,
          unlocked: false,
          activated: false,
        ),
        DepartmentState(
          type: DepartmentType.beauty,
          level: 5,
          unlocked: true,
          activated: false,
        ),
      ];

      expect(
        OperatingCostPolicy.totalDepartmentOperatingCosts(departments),
        0,
      );
    });
  });

  group('shift settlement', () {
    test('charges payroll and active department costs once at shift end', () async {
      final game = await _game(MemoryGameStorage());
      game.debugSetProgress(sales: 16);
      game.coins = 1000;
      expect(game.hireStaff(StaffRole.cashier), isTrue);
      final beforeSettlement = game.coins;

      _finishShift(game);

      expect(game.shiftLedger.payroll, 5);
      expect(game.shiftLedger.departmentOperatingCosts, 2);
      expect(game.coins, beforeSettlement - 7);
      expect(game.shiftOperatingCostsApplied, isTrue);
      expect(game.pendingShiftSummary!.ledger.payroll, 5);
      expect(game.pendingShiftSummary!.ledger.departmentOperatingCosts, 2);
    });

    test('repeated ticks cannot double charge a completed shift', () async {
      final game = await _game(MemoryGameStorage());
      game.debugSetProgress(sales: 16);
      game.coins = 1000;
      expect(game.hireStaff(StaffRole.cashier), isTrue);
      _finishShift(game);
      final settledCoins = game.coins;
      final settledPayroll = game.shiftLedger.payroll;

      for (var index = 0; index < 10; index++) {
        game.tick(0.05);
      }

      expect(game.coins, settledCoins);
      expect(game.shiftLedger.payroll, settledPayroll);
    });

    test('save and load preserve settlement and prevent another charge', () async {
      final storage = MemoryGameStorage();
      final game = await _game(storage);
      game.debugSetProgress(sales: 16);
      game.coins = 1000;
      expect(game.hireStaff(StaffRole.cashier), isTrue);
      _finishShift(game);
      final settledCoins = game.coins;
      await game.save();

      final restored = await _game(storage);
      restored.paused = false;
      restored.tick(0.05);

      expect(restored.shiftOperatingCostsApplied, isTrue);
      expect(restored.coins, settledCoins);
      expect(restored.shiftLedger.payroll, 5);
      expect(restored.shiftLedger.departmentOperatingCosts, 2);
    });

    test('a new shift receives a clean unsettled ledger', () async {
      final game = await _game(MemoryGameStorage());
      game.debugSetProgress(sales: 16);
      game.coins = 1000;
      expect(game.hireStaff(StaffRole.cashier), isTrue);
      _finishShift(game);

      game.startNextShift();

      expect(game.shiftLedger.payroll, 0);
      expect(game.shiftLedger.departmentOperatingCosts, 0);
      expect(game.shiftOperatingCostsApplied, isFalse);
    });

    test('costs can produce an honest negative net profit', () async {
      final game = await _game(MemoryGameStorage());
      game.debugSetProgress(sales: 16);
      game.coins = 1000;
      expect(game.hireStaff(StaffRole.cashier), isTrue);
      game.recordSale(3);

      _finishShift(game);

      expect(game.pendingShiftSummary!.ledger.netProfit, -4);
      expect(game.pendingShiftSummary!.ledger.payroll, 5);
      expect(game.pendingShiftSummary!.ledger.departmentOperatingCosts, 2);
    });

    test('legacy saves load safely and settle only at the next shift end', () async {
      final storage = MemoryGameStorage()
        ..data = <String, dynamic>{
          'version': 7,
          'coins': 100,
          'shiftElapsedSeconds': 20,
        };
      final game = await _game(storage);

      expect(game.shiftOperatingCostsApplied, isFalse);
      expect(game.shiftLedger.payroll, 0);
      expect(game.shiftLedger.departmentOperatingCosts, 0);
    });
  });

  group('balancing scenarios', () {
    test('early General Goods batch remains profitable', () {
      final general = DepartmentCatalog.find(DepartmentType.generalGoods)!;
      final gross = EconomyCalculator.grossRevenueForOrder(
        general,
        sellingPrice: 6,
      );
      final net =
          gross -
          general.orderCost -
          OperatingCostPolicy.departmentOperatingCost(
            DepartmentType.generalGoods,
            level: 1,
          );

      expect(gross, 36);
      expect(net, 16);
      expect(net, greaterThan(0));
    });

    test('Bakery plus one baker can remain profitable on one batch', () {
      final bakery = DepartmentCatalog.find(DepartmentType.bakery)!;
      final gross = EconomyCalculator.grossRevenueForOrder(
        bakery,
        sellingPrice: 8,
      );
      final net =
          gross -
          bakery.orderCost -
          OperatingCostPolicy.departmentOperatingCost(
            DepartmentType.bakery,
            level: 1,
          ) -
          OperatingCostPolicy.payrollForRole(
            StaffRole.baker,
            level: 1,
            workerCount: 1,
          );

      expect(net, 2);
      expect(net, greaterThan(0));
    });

    test('two registers and three early workers remain sustainable', () {
      final payroll =
          OperatingCostPolicy.payrollForRole(
            StaffRole.cashier,
            level: 1,
            workerCount: 2,
          ) +
          OperatingCostPolicy.payrollForRole(
            StaffRole.stocker,
            level: 1,
            workerCount: 1,
          ) +
          OperatingCostPolicy.payrollForRole(
            StaffRole.baker,
            level: 1,
            workerCount: 1,
          );
      const twoGeneralBatchProfit = 32;

      expect(payroll, 21);
      expect(twoGeneralBatchProfit - payroll, greaterThan(0));
    });

    test('multiple departments retain profit before optional staffing', () {
      const basePrice = 6;
      var batchProfit = 0;
      var operatingCosts = 0;
      for (final definition in DepartmentCatalog.all) {
        batchProfit += EconomyCalculator.grossProfitForOrder(
          definition,
          sellingPrice: basePrice + definition.priceBonus,
        );
        operatingCosts += OperatingCostPolicy.departmentOperatingCost(
          definition.type,
          level: 1,
        );
      }

      expect(operatingCosts, 26);
      expect(batchProfit - operatingCosts, greaterThan(80));
    });

    test('late-game costs are meaningful but below matching output capacity', () {
      final nonManagerPayroll = <StaffRole>[
        StaffRole.cashier,
        StaffRole.stocker,
        StaffRole.cleaner,
        StaffRole.baker,
        StaffRole.courier,
        StaffRole.promoter,
      ].fold<int>(
        0,
        (total, role) =>
            total +
            OperatingCostPolicy.payrollForRole(
              role,
              level: 10,
              workerCount: 3,
            ),
      );
      final managerPayroll = OperatingCostPolicy.payrollForRole(
        StaffRole.manager,
        level: 10,
        workerCount: 3,
      );
      final managerOutput = 75 * 2 * 10 * 3;
      final departmentCosts = DepartmentType.values.fold<int>(
        0,
        (total, type) =>
            total +
            OperatingCostPolicy.departmentOperatingCost(type, level: 10),
      );

      expect(nonManagerPayroll, 480);
      expect(managerPayroll, 3645);
      expect(managerPayroll, lessThan(managerOutput));
      expect(managerPayroll, greaterThan(managerOutput * 0.8));
      expect(departmentCosts, 110);
    });
  });
}

Future<GameController> _game(MemoryGameStorage storage) async {
  final game = GameController(
    storage: storage,
    monetization: PreviewMonetizationService(),
  );
  await game.initialize();
  game.acknowledgeDailyBonus();
  return game;
}

void _finishShift(GameController game) {
  game.shiftElapsedSeconds = GameController.shiftDurationSeconds - 0.01;
  game.paused = false;
  game.tick(0.05);
  expect(game.pendingShiftSummary, isNotNull);
}
