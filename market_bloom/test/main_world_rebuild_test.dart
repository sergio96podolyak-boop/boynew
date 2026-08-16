import 'package:flutter_test/flutter_test.dart';
import 'package:pomarket/ui/vertical_slice_world_painter.dart';

void main() {
  test('vertical slice depth order remains coherent', () {
    expect(VerticalSliceComposition.validDepthOrder, isTrue);
    expect(VerticalSliceComposition.layers, hasLength(9));
  });
}
