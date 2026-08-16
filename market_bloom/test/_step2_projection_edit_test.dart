import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomarket/ui/market_painter.dart';

void main() {
  test('character scale stays normalized across responsive board sizes', () {
    for (final size in const <Size>[
      Size(320, 568),
      Size(390, 844),
      Size(768, 700),
      Size(1024, 768),
      Size(1280, 800),
    ]) {
      final layout = MarketWorldLayout.forSize(size);
      final player = MarketCharacterScale.heightFor(
        MarketCharacterKind.player,
        layout,
      );
      final customer = MarketCharacterScale.heightFor(
        MarketCharacterKind.customer,
        layout,
      );
      final staff = MarketCharacterScale.heightFor(
        MarketCharacterKind.staff,
        layout,
      );
      expect(player, greaterThanOrEqualTo(staff));
      expect(staff, greaterThanOrEqualTo(customer));
      expect(player / customer, lessThan(1.16));
      expect(customer, greaterThan(0));
    }
  });
}
