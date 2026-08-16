import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomarket/game/game_controller.dart';
import 'package:pomarket/game/game_models.dart';
import 'package:pomarket/services/game_storage.dart';
import 'package:pomarket/services/monetization_service.dart';

void main() {
  late MemoryGameStorage storage;
  late GameController game;

  setUp(() async {
    storage = MemoryGameStorage();
    game = GameController(
      storage: storage,
      monetization: PreviewMonetizationService(),
      random: Random(9),
    );
    await game.initialize();
  });

  test('checkout upgrades unlock active stations and primary stays active', () {
    expect(game.checkoutStations.first.active, isTrue);
    expect(
      game.setCheckoutStationActive(
        GameController.primaryCheckoutStationId,
        false,
      ),
      isFalse,
    );
    _unlockSecondCheckout(game);
    expect(game.checkoutStations[1].unlocked, isTrue);
    expect(game.checkoutStations[1].active, isTrue);
  });

  test('customers only join staffed active registers when one is available', () {
    _unlockSecondCheckout(game);
    game.debugSetPlayerPosition(const Offset(0.5, 0.72));
    final customers = List<MarketCustomer>.generate(
      4,
      (index) => _customer(900 + index),
    );
    game.customers
      ..clear()
      ..addAll(customers);
    game.tick(0.05);

    expect(
      game.checkoutQueueFor('checkout-1').map((customer) => customer.id),
      <int>[900, 901, 902, 903],
    );
    expect(game.checkoutQueueFor('checkout-2'), isEmpty);
    expect(game.checkoutStationIsOperational('checkout-1'), isTrue);
    expect(game.checkoutStationIsOperational('checkout-2'), isFalse);
  });

  test('two available registers receive stable independent FIFO queues', () {
    _unlockSecondCheckout(game);
    game.debugSetPlayerPosition(GameController.checkout2Zone);
    final customers = List<MarketCustomer>.generate(
      4,
      (index) => _customer(920 + index),
    );
    game.customers
      ..clear()
      ..addAll(customers);
    game.tick(0.05);

    expect(
      game.checkoutQueueFor('checkout-1').map((customer) => customer.id),
      <int>[920, 922],
    );
    expect(
      game.checkoutQueueFor('checkout-2').map((customer) => customer.id),
      <int>[921, 923],
    );
    expect(game.checkoutStationIsOperational('checkout-2'), isTrue);
  });

  test('deactivating a station moves its queue and persists', () async {
    _unlockSecondCheckout(game);
    final customer = _customer(950, stationId: 'checkout-2');
    game.customers
      ..clear()
      ..add(customer);
    game.tick(0.05);

    expect(game.setCheckoutStationActive('checkout-2', false), isTrue);
    expect(customer.checkoutStationId, 'checkout-1');
    expect(game.checkoutQueueFor('checkout-2'), isEmpty);
    expect(
      game.floatingEffects.any((effect) => effect.text == '↪ Queue moved'),
      isTrue,
    );

    await game.save();
    final restored = GameController(
      storage: storage,
      monetization: PreviewMonetizationService(),
    );
    await restored.initialize();
    expect(restored.checkoutStations[1].unlocked, isTrue);
    expect(restored.checkoutStations[1].active, isFalse);
  });

  test('unstaffed queue moves to staffed checkout without resetting wait', () {
    _unlockSecondCheckout(game);
    game.debugSetPlayerPosition(const Offset(0.5, 0.72));
    final customer = _customer(960, stationId: 'checkout-2');
    game.customers
      ..clear()
      ..add(customer);
    _advance(game, GameController.checkoutRebalanceSeconds + 0.2);

    expect(game.checkoutStationHasCashier('checkout-1'), isTrue);
    expect(game.checkoutStationHasCashier('checkout-2'), isFalse);
    expect(customer.checkoutStationId, 'checkout-1');
    expect(
      customer.checkoutWaitTime,
      greaterThanOrEqualTo(GameController.checkoutRebalanceSeconds),
    );
  });

  test('checkout waiting affects satisfaction and warns before abandonment', () {
    final waiting = _customer(970, patience: 3.8);
    game.customers
      ..clear()
      ..add(waiting);
    game.debugSetPlayerPosition(const Offset(0.5, 0.72));
    final initialSatisfaction = waiting.satisfaction;
    _advance(game, GameController.checkoutQueueGraceSeconds + 0.8);

    expect(waiting.patience, lessThan(3.8));
    expect(waiting.satisfaction, lessThan(initialSatisfaction));
    expect(waiting.emotion, 'worried');
    expect(
      game.floatingEffects.any((effect) => effect.text == 'Getting impatient'),
      isTrue,
    );

    final leaving = _customer(980, patience: 0.1);
    game.customers
      ..clear()
      ..add(leaving);
    final missedBefore = game.shiftMissedSales;
    _advance(game, 0.5);

    expect(leaving.phase, CustomerPhase.leaving);
    expect(leaving.emotion, 'sad');
    expect(game.shiftMissedSales, missedBefore + 1);
    expect(
      game.floatingEffects.any((effect) => effect.text == 'Customer left'),
      isTrue,
    );
  });

  test('legacy checkout levels restore all earned stations', () async {
    final legacyStorage = MemoryGameStorage()
      ..data = <String, dynamic>{
        'checkoutLevel': GameController.checkout3UnlockLevel,
      };
    final restored = GameController(
      storage: legacyStorage,
      monetization: PreviewMonetizationService(),
    );
    await restored.initialize();

    expect(
      restored.checkoutStations.every((station) => station.unlocked),
      isTrue,
    );
    expect(
      restored.checkoutStations.every((station) => station.active),
      isTrue,
    );
  });
}

void _unlockSecondCheckout(GameController game) {
  game.debugSetProgress(sales: 16);
  game.coins = 2000;
  expect(game.hireStaff(StaffRole.cashier), isTrue);
  expect(game.buyUpgrade(UpgradeType.checkout), isTrue);
}

MarketCustomer _customer(
  int id, {
  String? stationId,
  double patience = 8,
}) {
  final zone = stationId == 'checkout-2'
      ? GameController.checkout2Zone
      : GameController.checkoutZone;
  return MarketCustomer(
    id: id,
    position: zone + const Offset(-0.03, 0.10),
    color: Colors.blue,
    checkoutStationId: stationId,
    patience: patience,
  )
    ..phase = CustomerPhase.checkout
    ..hasProduct = true;
}

void _advance(GameController game, double seconds) {
  final frames = (seconds / 0.05).ceil();
  for (var frame = 0; frame < frames; frame++) {
    game.tick(0.05);
  }
}
