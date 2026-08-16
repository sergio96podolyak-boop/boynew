import 'package:flutter_test/flutter_test.dart';
import 'package:pomarket/ui/market_painter.dart';

void main() {
  test('shelf relationship tolerates normalized floating point boundaries', () {
    final row = MarketDepthModel.shelfRows[1];
    final front = Offset(.30, row + MarketDepthModel.shelfFrontLaneOffset);
    expect(
      MarketDepthModel.shelfRelationship(front),
      ShelfVisualRelationship.front,
    );
  });
}
