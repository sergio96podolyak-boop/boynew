import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomarket/game/game_controller.dart';
import 'package:pomarket/game/game_models.dart';
import 'package:pomarket/services/game_storage.dart';
import 'package:pomarket/services/monetization_service.dart';

void main() {
  test('cashier takes over an in-progress player payment without a stall', () async {
    final game = GameController(
      storage: MemoryGameStorage(),
      monetization: PreviewMonetizationService(),
      random: Random(11),
    );
    await game.initialize();
    game.debugSetProgress(sales: 16);
    game.coins = 1000;
    expect(game.hireStaff(StaffRole.cashier), isTrue);

    final customer = MarketCustomer(
      id: 1100,
      position: GameController.checkoutZone + const Offset(-0.03, 0.10),
      color: Colors.blue,
    )
      ..phase = CustomerPhase.checkout
      ..hasProduct = true;
    game.customers
      ..clear()
      ..add(customer);
    game.debugSetPlayerPosition(GameController.checkoutZone);
    _advance(game, 0.2);
    expect(customer.checkoutOperator, CheckoutOperator.player);

    game.debugSetPlayerPosition(const Offset(0.5, 0.72));
    _advance(game, game.cashierCheckoutSeconds + 0.2);

    expect(customer.phase, CustomerPhase.leaving);
    expect(game.totalSales, 17);
  });
}

void _advance(GameController game, double seconds) {
  final frames = (seconds / 0.05).ceil();
  for (var frame = 0; frame < frames; frame++) {
    game.tick(0.05);
  }
}
