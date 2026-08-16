import 'package:flutter_test/flutter_test.dart';
import 'package:pomarket/ui/market_painter.dart';

void main() {
  test('shelf front lane remains between its lip and the next shelf row', () {
    for (var index = 0; index < MarketDepthModel.shelfRows.length - 1; index++) {
      final row = MarketDepthModel.shelfRows[index];
      final nextRow = MarketDepthModel.shelfRows[index + 1];
      final front = row + MarketDepthModel.shelfFrontLaneOffset;
      expect(front, greaterThan(row + MarketDepthModel.shelfForegroundOffset));
      expect(front, lessThan((row + nextRow) / 2));
      expect(
        MarketDepthModel.shelfRelationship(Offset(.30, front)),
        ShelfVisualRelationship.front,
      );
    }
  });
}
