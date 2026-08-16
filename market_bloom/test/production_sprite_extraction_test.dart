import 'dart:collection';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomarket/ui/market_art_assets.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('all archived production sprites remain bundled PNG files', () async {
    expect(MarketArtAssets.allProductionPaths, hasLength(27));
    for (final path in MarketArtAssets.allProductionPaths) {
      final data = await rootBundle.load(path);
      final bytes = data.buffer.asUint8List();
      expect(data.lengthInBytes, greaterThan(200), reason: path);
      expect(
        bytes.take(8),
        orderedEquals(const <int>[137, 80, 78, 71, 13, 10, 26, 10]),
        reason: path,
      );
    }
  });

  test('runtime loader decodes only active world assets', () async {
    await MarketArtAssets.load();
    for (final path in MarketArtAssets.activeRuntimePaths) {
      final image = MarketArtAssets.image(path);
      final source = MarketArtAssets.sourceRect(path);
      expect(image, isNotNull, reason: path);
      expect(source, isNotNull, reason: path);
      expect(source!.size, Size(image!.width.toDouble(), image.height.toDouble()));
    }
    for (final path in <String>[
      ...MarketArtAssets.fixturePaths,
      MarketArtAssets.entrancePath,
      MarketArtAssets.shoppingCartPath,
      MarketArtAssets.basketStackPath,
      MarketArtAssets.promoStandPath,
      MarketArtAssets.coolerPath,
      MarketArtAssets.bakeryTrayPath,
    ]) {
      expect(MarketArtAssets.image(path), isNull, reason: path);
    }
  });

  test('V2 runtime RGBA has transparent corners and no baked preview field', () async {
    await MarketArtAssets.load();
    for (final path in MarketArtAssets.mainWorldV2Paths) {
      final sourceImage = await _decodeSource(path);
      final sourceRgba = await _rgba(sourceImage);
      final sourceBackdrop = _borderNeutralComponentRatio(
        sourceRgba,
        sourceImage.width,
        sourceImage.height,
      );
      // Kept intentionally visible in validation output so affected source
      // artwork can be reported without weakening runtime assertions.
      // ignore: avoid_print
      print('V2_SOURCE_BACKDROP $path ${sourceBackdrop.toStringAsFixed(4)}');
      sourceImage.dispose();

      final image = MarketArtAssets.image(path)!;
      final rgba = await _rgba(image);
      final width = image.width;
      final height = image.height;
      final corners = <int>[
        0,
        width - 1,
        (height - 1) * width,
        width * height - 1,
      ];
      for (final pixel in corners) {
        expect(rgba[pixel * 4 + 3], lessThanOrEqualTo(8), reason: path);
      }

      final borderBackdrop = _borderNeutralComponentRatio(rgba, width, height);
      expect(
        borderBackdrop,
        lessThan(.005),
        reason: '$path retained checkerboard or neutral matte pixels',
      );
      expect(
        _opaqueBorderRatio(rgba, width, height),
        lessThan(.08),
        reason: '$path retained a rectangular preview background',
      );
      expect(_visiblePixelCount(rgba), greaterThan(20), reason: path);
      expect(_transparentPixelCount(rgba), greaterThan(20), reason: path);
    }
  });

  test('character sprites retain white clothing and highlights', () async {
    await MarketArtAssets.load();
    for (final paths in <List<String>>[
      MarketArtAssets.playerPaths,
      MarketArtAssets.staffPaths,
      MarketArtAssets.customerPaths,
    ]) {
      var neutralOpaque = 0;
      for (final path in paths) {
        final image = MarketArtAssets.image(path)!;
        final rgba = await _rgba(image);
        for (var pixel = 0; pixel < image.width * image.height; pixel++) {
          final offset = pixel * 4;
          if (rgba[offset + 3] <= 24) continue;
          final high = max(rgba[offset], max(rgba[offset + 1], rgba[offset + 2]));
          final low = min(rgba[offset], min(rgba[offset + 1], rgba[offset + 2]));
          if (low >= 192 && high - low <= 58) neutralOpaque++;
        }
      }
      expect(neutralOpaque, greaterThan(10), reason: paths.first);
    }
  });
}

Future<ui.Image> _decodeSource(String path) async {
  final data = await rootBundle.load(path);
  final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
  try {
    return (await codec.getNextFrame()).image;
  } finally {
    codec.dispose();
  }
}

Future<Uint8List> _rgba(ui.Image image) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  expect(data, isNotNull);
  return data!.buffer.asUint8List();
}

int _visiblePixelCount(Uint8List rgba) {
  var count = 0;
  for (var offset = 3; offset < rgba.length; offset += 4) {
    if (rgba[offset] > 24) count++;
  }
  return count;
}

int _transparentPixelCount(Uint8List rgba) {
  var count = 0;
  for (var offset = 3; offset < rgba.length; offset += 4) {
    if (rgba[offset] <= 8) count++;
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
