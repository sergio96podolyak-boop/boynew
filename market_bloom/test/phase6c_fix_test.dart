import 'package:flutter_test/flutter_test.dart';
import 'package:pomarket/game/game_controller.dart';
import 'package:pomarket/game/game_models.dart';
import 'package:pomarket/services/game_storage.dart';
import 'package:pomarket/services/monetization_service.dart';

void main() {
  test('Phase 6C cost policy remains inactive until real costs are recorded', () async {
    final controller = GameController(
      storage: MemoryGameStorage(),
      monetization: PreviewMonetizationService(),
    );
    await controller.initialize();
    controller.coins = 200;

    expect(controller.shiftLedger.payroll, 0);
    expect(controller.shiftLedger.departmentOperatingCosts, 0);
    expect(controller.coins, 200);

    controller.recordOperatingCost(
      12,
      type: ShiftOperatingCostType.payroll,
    );

    expect(controller.shiftLedger.payroll, 12);
    expect(controller.coins, 200);
  });
}
