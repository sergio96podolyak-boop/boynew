import 'dart:collection';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:pomarket/ui/market_art_assets.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('actual V2 PNG files have real alpha and no baked preview background', () async {
    for (final path in MarketArtAssets.mainWorldV2Paths) {
      final bytes = await File(path).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final image = (await codec.getNextFrame()).image;
      codec.dispose();
      final rgba = await _rgba(image);
      final width = image.width;
      final height = image.height;
      image.dispose();

      final corners = <int>[
        0,
        width - 1,
        (height - 1) * width,
        width * height - 1,
      ];
      for (final pixel in corners) {
        expect(rgba[pixel * 4 + 3], lessThanOrEqualTo(8), reason: path);
      }
      expect(_transparentCount(rgba), greaterThan(width * height * .12), reason: path);
      expect(_visibleCount(rgba), greaterThan(width * height * .03), reason: path);
      expect(_opaqueBorderRatio(rgba, width, height), lessThan(.08), reason: path);
      expect(
        _borderNeutralComponentRatio(rgba, width, height),
        lessThan(.005),
        reason: '$path contains a checkerboard or neutral rectangular matte',
      );
      expect(_preservedWhiteDetailCount(rgba), greaterThan(20), reason: path);
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

int _preservedWhiteDetailCount(Uint8List rgba) {
  var count = 0;
  for (var offset = 0; offset < rgba.length; offset += 4) {
    if (rgba[offset + 3] <= 24) continue;
    final high = max(rgba[offset], max(rgba[offset + 1], rgba[offset + 2]));
    final low = min(rgba[offset], min(rgba[offset + 1], rgba[offset + 2]));
    if (low >= 210 && high - low <= 35) count++;
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
  return total == 0 ? 0 : opaque / total;
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
  return total == 0 ? 0 : count / total;
}
