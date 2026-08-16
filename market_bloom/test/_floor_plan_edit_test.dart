import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomarket/ui/market_painter.dart';

void main() {
  test('main world floor plan is connected and has deliberate openings', () {
    for (final size in const <Size>[
      Size(320, 568),
      Size(390, 844),
      Size(768, 700),
      Size(1024, 768),
    ]) {
      final layout = MarketWorldLayout.forSize(size);

      expect(layout.wall.bottom, layout.storage.top);
      expect(layout.wall.bottom, layout.bakery.top);
      expect(layout.storage.bottom, layout.retail.top);
      expect(layout.bakery.bottom, layout.checkout.top);
      expect(layout.retail.right, layout.checkout.left);
      expect(layout.retail.bottom, layout.welcome.top);
      expect(layout.checkout.bottom, layout.welcome.top);
      expect(layout.storage.right, layout.bakery.left);
      expect(layout.mainAisle.overlaps(layout.crossAisle), isTrue);
      expect(layout.mainAisle.overlaps(layout.retail), isTrue);
      expect(layout.mainAisle.overlaps(layout.welcome), isTrue);
      expect(layout.crossAisle.overlaps(layout.retail), isTrue);
      expect(layout.crossAisle.overlaps(layout.checkout), isTrue);

      expect(layout.welcome.overlaps(layout.entranceOpening), isTrue);
      expect(layout.checkoutOpening.left, lessThan(layout.checkout.left));
      expect(layout.checkoutOpening.right, greaterThan(layout.checkout.left));
      expect(layout.storageOpening.top, lessThan(layout.storage.bottom));
      expect(layout.storageOpening.bottom, greaterThan(layout.storage.bottom));
      expect(layout.bakeryOpening.top, lessThan(layout.bakery.bottom));
      expect(layout.bakeryOpening.bottom, greaterThan(layout.bakery.bottom));
      expect(layout.storageOpening.width, greaterThan(0));
      expect(layout.bakeryOpening.width, greaterThan(layout.storageOpening.width));
    }
  });

  test('floor-plan rebuild retains the single active renderer', () {
    expect(activeMarketWorldRenderer, 'MarketPainter');
  });
}
