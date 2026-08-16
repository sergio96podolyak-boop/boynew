import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('finalize phase 2 modular integration metadata', () {
    final assetsFile = File('lib/ui/market_art_assets.dart');
    var assets = assetsFile.readAsStringSync();
    assets = assets.replaceFirst(
      '  /// Modular assets are bundled and registered, but intentionally excluded\n  /// from activeRuntimePaths until the Main World integration phase.\n',
      '  /// V3 architecture remains active while the modular fixture kit supplies\n  /// the retail aisles, refrigerated bank, endcaps, and checkout registers.\n',
    );
    assetsFile.writeAsStringSync(assets);

    final modularTest = File('test/main_world_modular_assets_test.dart');
    var source = modularTest.readAsStringSync();
    source = source.replaceFirst("import 'dart:typed_data';\n", '');
    source = source.replaceFirst(
      "test('phase 1 modular assets are clean 1024 square transparent PNGs'",
      "test('phase 2 modular assets remain clean 1024 square transparent PNGs'",
    );
    modularTest.writeAsStringSync(source);
  });
}
