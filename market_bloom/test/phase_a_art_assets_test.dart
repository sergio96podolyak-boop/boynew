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

  test('active production loader decodes each runtime sprite', () async {
    await MarketArtAssets.load();
    for (final path in MarketArtAssets.activeRuntimePaths) {
      final image = MarketArtAssets.image(path);
      final source = MarketArtAssets.sourceRect(path);
      expect(image, isNotNull, reason: path);
      expect(source, isNotNull, reason: path);
      expect(source!.size, Size(image!.width.toDouble(), image.height.toDouble()));
    }
  });

  test('active production sprites contain visible alpha', () async {
    await MarketArtAssets.load();
    for (final path in MarketArtAssets.activeRuntimePaths) {
      final image = MarketArtAssets.image(path)!;
      final rgba = await _rgba(image);
      var opaque = 0;
      var transparent = 0;
      for (var pixel = 0; pixel < image.width * image.height; pixel++) {
        if (rgba[pixel * 4 + 3] > 24) {
          opaque++;
        } else {
          transparent++;
        }
      }
      expect(opaque, greaterThan(20), reason: '$path has no visible sprite');
      expect(transparent, greaterThan(0), reason: '$path has no true alpha');
    }
  });

  test('character production sprites retain white clothing and highlights', () async {
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

Future<List<int>> _rgba(ui.Image image) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  expect(data, isNotNull);
  return data!.buffer.asUint8List();
}
