import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomarket/ui/market_art_assets.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('active fixture manifest points only to cache-busted clean production PNGs', () async {
    const root = 'assets/generated/main_world_v3_clean';
    final expected = <String>[
      '$root/fixture_merchandising_shelf.png',
      '$root/fixture_checkout.png',
      '$root/fixture_bakery_counter.png',
      '$root/fixture_storage_bay.png',
      '$root/fixture_storefront_entrance.png',
      '$root/prop_cart_baskets.png',
      '$root/fixture_promotional_endcap.png',
      '$root/fixture_refrigerated_cooler.png',
    ];

    expect(MarketArtAssets.mainWorldV2Root, root);
    expect(MarketArtAssets.mainWorldV2Paths, expected);
    for (final path in expected) {
      expect(MarketArtAssets.activeRuntimePaths, contains(path));
      expect((await rootBundle.load(path)).lengthInBytes, greaterThan(1000));
    }
    for (final path in MarketArtAssets.activeRuntimePaths) {
      expect(path, isNot(startsWith('assets/generated/main_world_v2/')));
      expect(path, isNot(startsWith('assets/assets/assets/generated/phase_b5/phase_c_')));
    }
    for (final path in MarketArtAssets.fixturePaths) {
      expect(MarketArtAssets.activeRuntimePaths, isNot(contains(path)));
    }
  });
}
