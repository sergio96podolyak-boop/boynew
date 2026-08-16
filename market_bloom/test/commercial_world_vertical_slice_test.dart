import 'package:flutter_test/flutter_test.dart';
import 'package:pomarket/ui/vertical_slice_world_painter.dart';

void main() {
  test('compact commercial world reduces secondary density', () {
    expect(
      VerticalSliceComposition.densityFor(320),
      lessThan(VerticalSliceComposition.densityFor(560)),
    );
  });
}
