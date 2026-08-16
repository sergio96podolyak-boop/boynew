import 'package:flutter_test/flutter_test.dart';
import 'package:pomarket/game/game_controller.dart';
import 'package:pomarket/game/game_models.dart';
import 'package:pomarket/services/game_storage.dart';
import 'package:pomarket/services/monetization_service.dart';

void main() {
  group('ShiftLedger model', () {
    test('zero ledger has safe defaults', () {
      final ledger = ShiftLedger();
      expect(ledger.grossRevenue, 0);
      expect(ledger.stockOrderCosts, 0);
      expect(ledger.payroll, 0);
      expect(ledger.departmentOperatingCosts, 0);
      expect(ledger.bonuses, 0);
      expect(ledger.missedSalesEstimate, 0);
      expect(ledger.netProfit, 0);
    });

    test('records sales, stock costs, bonuses and missed sales', () {
      final ledger = ShiftLedger()
        ..recordSale(80)
        ..recordSale(20)
        ..recordStockOrderCost(35)
        ..recordBonus(12)
        ..recordMissedSaleEstimate(18);
      expect(ledger.grossRevenue, 100);
      expect(ledger.stockOrderCosts, 35);
      expect(ledger.bonuses, 12);
      expect(ledger.missedSalesEstimate, 18);
      expect(ledger.netProfit, 77);
    });

    test('operating costs distinguish payroll from department costs', () {
      final ledger = ShiftLedger(grossRevenue: 150, bonuses: 10)
        ..recordOperatingCost(40, type: ShiftOperatingCostType.payroll)
        ..recordOperatingCost(25);
      expect(ledger.payroll, 40);
      expect(ledger.departmentOperatingCosts, 25);
      expect(ledger.netProfit, 95);
    });

    test('missed sales estimate is informational, not a cash expense', () {
      final ledger = ShiftLedger(grossRevenue: 50)
        ..recordMissedSaleEstimate(200);
      expect(ledger.missedSalesEstimate, 200);
      expect(ledger.netProfit, 50);
    });

    test('invalid and negative persisted amounts restore safely', () {
      final ledger = ShiftLedger.fromJson(<String, Object?>{
        'grossRevenue': -20,
        'stockOrderCosts': '12',
        'payroll': 'invalid',
        'departmentOperatingCosts': 3.6,
        'bonuses': 5,
        'missedSalesEstimate': -1,
      });
      expect(ledger.grossRevenue, 0);
      expect(ledger.stockOrderCosts, 12);
      expect(ledger.payroll, 0);
      expect(ledger.departmentOperatingCosts, 4);
      expect(ledger.bonuses, 5);
      expect(ledger.missedSalesEstimate, 0);
      expect(ledger.netProfit, -11);
    });
  });

  group('GameController shift ledger integration', () {
    test('recording accounting events never changes cash balance', () async {
      final game = await _game(MemoryGameStorage());
      game.coins = 100;
      game.recordSale(40);
      game.recordStockOrderCost(15);
      game.recordBonus(7);
      game.recordMissedSaleEstimate(9);
      game.recordOperatingCost(4);
      game.recordOperatingCost(6, type: ShiftOperatingCostType.payroll);
      expect(game.coins, 100);
      expect(game.shiftLedger.netProfit, 22);
    });

    test('inventory order charges cash once and records accounting cost', () async {
      final game = await _game(MemoryGameStorage());
      game.coins = 100;
      final delivery = game.placeInventoryOrder('General', 2, cost: 20);
      expect(delivery, isNotNull);
      expect(game.coins, 80);
      expect(game.shiftLedger.stockOrderCosts, 20);
      expect(game.shiftLedger.netProfit, -20);
    });

    test('ledger is copied into the completed shift summary', () async {
      final game = await _game(MemoryGameStorage());
      game.recordSale(70);
      game.recordStockOrderCost(25);
      game.recordBonus(5);
      game.shiftElapsedSeconds = GameController.shiftDurationSeconds - 0.01;
      game.tick(0.05);
      expect(game.pendingShiftSummary, isNotNull);
      expect(game.pendingShiftSummary!.ledger.grossRevenue, 70);
      expect(game.pendingShiftSummary!.ledger.stockOrderCosts, 25);
      expect(game.pendingShiftSummary!.ledger.bonuses, 5);
      expect(game.pendingShiftSummary!.ledger.netProfit, 50);
    });

    test('current ledger round-trips through save and load', () async {
      final storage = MemoryGameStorage();
      final game = await _game(storage);
      game.coins = 100;
      game.recordSale(90);
      game.recordStockOrderCost(30);
      game.recordBonus(8);
      game.recordMissedSaleEstimate(11);
      game.recordOperatingCost(7);
      game.recordOperatingCost(13, type: ShiftOperatingCostType.payroll);
      await game.save();

      final restored = await _game(storage);
      expect(restored.shiftLedger.grossRevenue, 90);
      expect(restored.shiftLedger.stockOrderCosts, 30);
      expect(restored.shiftLedger.bonuses, 8);
      expect(restored.shiftLedger.missedSalesEstimate, 11);
      expect(restored.shiftLedger.departmentOperatingCosts, 7);
      expect(restored.shiftLedger.payroll, 13);
      expect(restored.shiftLedger.netProfit, 48);
    });

    test('legacy saves without a ledger load with zero defaults', () async {
      final storage = MemoryGameStorage()
        ..data = <String, dynamic>{
          'version': 7,
          'coins': 77,
          'shiftNumber': 3,
          'shiftRevenue': 42,
        };
      final restored = await _game(storage);
      expect(restored.coins, greaterThanOrEqualTo(77));
      expect(restored.shiftNumber, 3);
      expect(restored.shiftRevenue, 42);
      expect(restored.shiftLedger.netProfit, 0);
      expect(
        restored.shiftLedger.toJson().values.every((value) => value == 0),
        isTrue,
      );
    });

    test('starting the next shift resets only the accounting ledger', () async {
      final game = await _game(MemoryGameStorage());
      game.recordSale(40);
      game.recordBonus(5);
      game.pendingShiftSummary = ShiftSummary(
        shiftNumber: game.shiftNumber,
        sales: 0,
        revenue: 0,
        missedSales: 0,
        satisfaction: 1,
        xp: 0,
        stockRemaining: 0,
        ledger: game.shiftLedger,
      );
      game.paused = true;
      game.startNextShift();
      expect(game.shiftLedger.netProfit, 0);
      expect(game.shiftNumber, 2);
      expect(game.paused, isFalse);
    });
  });
}

Future<GameController> _game(MemoryGameStorage storage) async {
  final game = GameController(
    storage: storage,
    monetization: PreviewMonetizationService(),
  );
  await game.initialize();
  return game;
}
