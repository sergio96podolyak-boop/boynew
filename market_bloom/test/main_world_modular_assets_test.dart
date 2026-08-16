import 'dart:collection';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomarket/ui/market_art_assets.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('phase 2 modular Main World kit is bundled and active', () async {
    expect(MarketArtAssets.mainWorldModularPaths, hasLength(5));
    expect(MarketArtAssets.mainWorldModularPaths.toSet(), hasLength(5));
    for (final path in MarketArtAssets.mainWorldModularPaths) {
      expect(MarketArtAssets.activeRuntimePaths, contains(path));
      final data = await rootBundle.load(path);
      expect(data.lengthInBytes, greaterThan(100000), reason: path);
      final bytes = data.buffer.asUint8List();
      expect(
        bytes.take(8),
        orderedEquals(const <int>[137, 80, 78, 71, 13, 10, 26, 10]),
        reason: path,
      );
    }
  });

  test('phase 2 modular assets remain clean 1024 square transparent PNGs', () async {
    for (final path in MarketArtAssets.mainWorldModularPaths) {
      final data = await rootBundle.load(path);
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final image = (await codec.getNextFrame()).image;
      codec.dispose();
      expect(image.width, 1024, reason: path);
      expect(image.height, 1024, reason: path);
      final rgba = await _rgba(image);
      image.dispose();

      for (final pixel in <int>[
        0,
        1023,
        1023 * 1024,
        1024 * 1024 - 1,
      ]) {
        expect(rgba[pixel * 4 + 3], lessThanOrEqualTo(8), reason: path);
      }
      expect(_transparentCount(rgba), greaterThan(1024 * 1024 * .12), reason: path);
      expect(_visibleCount(rgba), greaterThan(1024 * 1024 * .03), reason: path);
      expect(_opaqueBorderRatio(rgba, 1024, 1024), lessThan(.08), reason: path);
      expect(
        _borderNeutralComponentRatio(rgba, 1024, 1024),
        lessThan(.005),
        reason: '$path contains a rectangular neutral matte',
      );
    }
  });
}

Future<Uint8List> _rgba(ui.Image image) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  expect(data, isNotNull);
  return data!.buffer.asUint8List();
}

int _transparentCount(Uint8List rgba) {
  var count = 0;
  for (var offset = 3; offset < rgba.length; offset += 4) {
    if (rgba[offset] <= 8) count++;
  }
  return count;
}

int _visibleCount(Uint8List rgba) {
  var count = 0;
  for (var offset = 3; offset < rgba.length; offset += 4) {
    if (rgba[offset] > 24) count++;
  }
  return count;
}

double _opaqueBorderRatio(Uint8List rgba, int width, int height) {
  var opaque = 0;
  var total = 0;
  void sample(int pixel) {
    total++;
    if (rgba[pixel * 4 + 3] > 24) opaque++;
  }

  for (var x = 0; x < width; x++) {
    sample(x);
    sample((height - 1) * width + x);
  }
  for (var y = 1; y + 1 < height; y++) {
    sample(y * width);
    sample(y * width + width - 1);
  }
  return opaque / total;
}

double _borderNeutralComponentRatio(Uint8List rgba, int width, int height) {
  final total = width * height;
  final visited = Uint8List(total);
  final queue = ListQueue<int>();

  bool neutral(int pixel) {
    final offset = pixel * 4;
    if (rgba[offset + 3] <= 8) return false;
    final red = rgba[offset];
    final green = rgba[offset + 1];
    final blue = rgba[offset + 2];
    final high = max(red, max(green, blue));
    final low = min(red, min(green, blue));
    return low >= 145 && high - low <= 42;
  }

  void seed(int pixel) {
    if (visited[pixel] != 0 || !neutral(pixel)) return;
    visited[pixel] = 1;
    queue.add(pixel);
  }

  for (var x = 0; x < width; x++) {
    seed(x);
    seed((height - 1) * width + x);
  }
  for (var y = 0; y < height; y++) {
    seed(y * width);
    seed(y * width + width - 1);
  }

  var count = 0;
  while (queue.isNotEmpty) {
    final pixel = queue.removeFirst();
    count++;
    final x = pixel % width;
    final y = pixel ~/ width;
    if (x > 0) seed(pixel - 1);
    if (x + 1 < width) seed(pixel + 1);
    if (y > 0) seed(pixel - width);
    if (y + 1 < height) seed(pixel + width);
  }
  return count / total;
}
