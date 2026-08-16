import 'package:flutter_test/flutter_test.dart';
import 'package:pomarket/game/game_controller.dart';
import 'package:pomarket/game/game_models.dart';
import 'package:pomarket/services/game_storage.dart';
import 'package:pomarket/services/monetization_service.dart';

void main() {
  group('Phase 6D-C shift settlement', () {
    test('records payroll and active department costs at shift end', () async {
      final game = await _game(MemoryGameStorage());
      game.debugSetProgress(sales: 16);
      game.coins = 1000;
      expect(game.hireStaff(StaffRole.cashier), isTrue);

      _finishShift(game);

      expect(game.shiftLedger.payroll, 5);
      expect(game.shiftLedger.departmentOperatingCosts, 2);
      expect(game.pendingShiftSummary!.ledger.payroll, 5);
      expect(game.pendingShiftSummary!.ledger.departmentOperatingCosts, 2);
    });

    test('charges the exact settlement total once', () async {
      final game = await _game(MemoryGameStorage());
      game.debugSetProgress(sales: 16);
      game.coins = 1000;
      expect(game.hireStaff(StaffRole.cashier), isTrue);
      final beforeSettlement = game.coins;

      _finishShift(game);

      expect(game.coins, beforeSettlement - 7);
      expect(game.shiftOperatingCostsApplied, isTrue);

      game
        ..paused = false
        ..pendingShiftSummary = null
        ..shiftElapsedSeconds = GameController.shiftDurationSeconds - 0.01;
      game.tick(0.05);

      expect(game.coins, beforeSettlement - 7);
      expect(game.shiftLedger.payroll, 5);
      expect(game.shiftLedger.departmentOperatingCosts, 2);
    });

    test('reload of an already-settled shift cannot charge again', () async {
      final storage = MemoryGameStorage();
      final game = await _game(storage);
      game.debugSetProgress(sales: 16);
      game.coins = 1000;
      expect(game.hireStaff(StaffRole.cashier), isTrue);
      _finishShift(game);
      final settledCoins = game.coins;
      await game.save();

      final restored = await _game(storage);
      restored
        ..paused = false
        ..pendingShiftSummary = null
        ..shiftElapsedSeconds = GameController.shiftDurationSeconds - 0.01;
      restored.tick(0.05);

      expect(restored.shiftOperatingCostsApplied, isTrue);
      expect(restored.coins, settledCoins);
      expect(restored.shiftLedger.payroll, 5);
      expect(restored.shiftLedger.departmentOperatingCosts, 2);
    });

    test('zero-cost settlement leaves coins and ledger costs unchanged', () async {
      final game = await _game(MemoryGameStorage());
      game.coins = 125;

      _finishShift(game);

      expect(game.coins, 125);
      expect(game.shiftLedger.payroll, 0);
      expect(game.shiftLedger.departmentOperatingCosts, 0);
      expect(game.shiftOperatingCostsApplied, isTrue);
    });

    test('insufficient funds follow the existing full-cost coin policy', () async {
      final game = await _game(MemoryGameStorage());
      game.debugSetProgress(sales: 16);
      game.coins = 1000;
      expect(game.hireStaff(StaffRole.cashier), isTrue);
      game.coins = 3;

      _finishShift(game);

      // Shift settlement already permits a negative cash balance so the full
      // actual cost is charged. This test locks that existing behavior rather
      // than introducing a separate debt or partial-payment system.
      expect(game.shiftLedger.payroll, 5);
      expect(game.shiftLedger.departmentOperatingCosts, 2);
      expect(game.coins, -4);
      expect(game.shiftOperatingCostsApplied, isTrue);
    });

    test('final net profit includes stock, payroll and department costs once', () async {
      final game = await _game(MemoryGameStorage());
      game.debugSetProgress(sales: 16);
      game.coins = 1000;
      expect(game.hireStaff(StaffRole.cashier), isTrue);
      game.recordSale(30);
      game.recordStockOrderCost(10);
      game.recordBonus(4);

      _finishShift(game);

      expect(game.pendingShiftSummary!.ledger.grossRevenue, 30);
      expect(game.pendingShiftSummary!.ledger.stockOrderCosts, 10);
      expect(game.pendingShiftSummary!.ledger.payroll, 5);
      expect(game.pendingShiftSummary!.ledger.departmentOperatingCosts, 2);
      expect(game.pendingShiftSummary!.ledger.bonuses, 4);
      expect(game.pendingShiftSummary!.ledger.netProfit, 17);
    });

    test('an interrupted pre-settlement shift has no partial charge', () async {
      final storage = MemoryGameStorage();
      final game = await _game(storage);
      game.debugSetProgress(sales: 16);
      game.coins = 1000;
      expect(game.hireStaff(StaffRole.cashier), isTrue);
      final beforeSettlement = game.coins;
      game.shiftElapsedSeconds = GameController.shiftDurationSeconds - 1;
      await game.save();

      expect(game.shiftOperatingCostsApplied, isFalse);
      expect(game.shiftLedger.payroll, 0);
      expect(game.shiftLedger.departmentOperatingCosts, 0);
      expect(game.coins, beforeSettlement);

      final restored = await _game(storage);
      restored.shiftElapsedSeconds = GameController.shiftDurationSeconds - 0.01;
      restored.paused = false;
      restored.tick(0.05);

      expect(restored.coins, beforeSettlement - 7);
      expect(restored.shiftLedger.payroll, 5);
      expect(restored.shiftLedger.departmentOperatingCosts, 2);
    });

    test('legacy save without settlement metadata loads and settles once', () async {
      final storage = MemoryGameStorage()
        ..data = <String, dynamic>{
          'version': 7,
          'coins': 140,
          'shiftElapsedSeconds': 30,
        };
      final game = await _game(storage);

      expect(game.shiftOperatingCostsApplied, isFalse);
      expect(game.shiftLedger.payroll, 0);
      expect(game.shiftLedger.departmentOperatingCosts, 0);

      game.shiftElapsedSeconds = GameController.shiftDurationSeconds - 0.01;
      game.paused = false;
      game.tick(0.05);

      expect(game.shiftOperatingCostsApplied, isTrue);
      expect(game.shiftLedger.payroll, 0);
      expect(game.shiftLedger.departmentOperatingCosts, 0);
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
