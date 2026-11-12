import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class _ArtRepaintNotifier extends ChangeNotifier {
  void refresh() => notifyListeners();
}

abstract final class MarketArtAssets {
  static const String productionRoot = 'assets/assets/generated/phase_b5';
  static const String commercialRoot = 'assets/assets/assets/generated/phase_b5';
  static const String mainWorldV2Root = 'assets/generated/main_world_v3_clean';
  static const String mainWorldModularRoot =
      'assets/generated/main_world_modular';

  static const String playerIdlePath = '$productionRoot/player_idle.png';
  static const String playerWalkAPath = '$productionRoot/player_walk_a.png';
  static const String playerWalkBPath = '$productionRoot/player_walk_b.png';
  static const String playerCarryingPath = '$productionRoot/player_carrying.png';
  static const List<String> playerPaths = <String>[
    playerIdlePath,
    playerWalkAPath,
    playerWalkBPath,
    playerCarryingPath,
  ];

  static const List<String> staffPaths = <String>[
    '$productionRoot/staff_cashier.png',
    '$productionRoot/staff_stocker.png',
    '$productionRoot/staff_cleaner.png',
    '$productionRoot/staff_baker.png',
    '$productionRoot/staff_manager.png',
    '$productionRoot/staff_courier.png',
    '$productionRoot/staff_promoter.png',
  ];

  static const List<String> customerPaths = <String>[
    '$productionRoot/customer_1.png',
    '$productionRoot/customer_2.png',
    '$productionRoot/customer_3.png',
    '$productionRoot/customer_4.png',
  ];

  static const String mainShelfPath = '$productionRoot/fixture_main_shelf.png';
  static const String checkoutPath = '$productionRoot/fixture_checkout.png';
  static const String storagePath = '$productionRoot/fixture_storage.png';
  static const String bakeryPath = '$productionRoot/fixture_bakery.png';
  static const List<String> fixturePaths = <String>[
    mainShelfPath,
    checkoutPath,
    storagePath,
    bakeryPath,
  ];

  static const String entrancePath = '$productionRoot/environment_entrance.png';
  static const String shoppingCartPath =
      '$productionRoot/environment_shopping_cart.png';
  static const String basketStackPath =
      '$productionRoot/environment_basket_stack.png';
  static const String promoStandPath =
      '$productionRoot/environment_promo_stand.png';
  static const String coolerPath = '$productionRoot/environment_cooler.png';
  static const String cleaningCartPath =
      '$productionRoot/environment_cleaning_cart.png';
  static const String deliveryBoxesPath =
      '$productionRoot/environment_delivery_boxes.png';
  static const String bakeryTrayPath =
      '$productionRoot/environment_bakery_tray.png';
  static const List<String> environmentPaths = <String>[
    entrancePath,
    shoppingCartPath,
    basketStackPath,
    promoStandPath,
    coolerPath,
    cleaningCartPath,
    deliveryBoxesPath,
    bakeryTrayPath,
  ];

  static const String v2ShelfPath =
      '$mainWorldV2Root/fixture_merchandising_shelf.png';
  static const String v2CheckoutPath =
      '$mainWorldV2Root/fixture_checkout.png';
  static const String v2BakeryPath =
      '$mainWorldV2Root/fixture_bakery_counter.png';
  static const String v2StoragePath =
      '$mainWorldV2Root/fixture_storage_bay.png';
  static const String v2EntrancePath =
      '$mainWorldV2Root/fixture_storefront_entrance.png';
  static const String v2CartBasketsPath =
      '$mainWorldV2Root/prop_cart_baskets.png';
  static const String v2PromoEndcapPath =
      '$mainWorldV2Root/fixture_promotional_endcap.png';
  static const String v2CoolerPath =
      '$mainWorldV2Root/fixture_refrigerated_cooler.png';
  static const List<String> mainWorldV2Paths = <String>[
    v2ShelfPath,
    v2CheckoutPath,
    v2BakeryPath,
    v2StoragePath,
    v2EntrancePath,
    v2CartBasketsPath,
    v2PromoEndcapPath,
    v2CoolerPath,
  ];

  static const String modularShortShelfPath =
      '$mainWorldModularRoot/fixture_shelf_short_double_sided.png';
  static const String modularLongShelfPath =
      '$mainWorldModularRoot/fixture_shelf_long_double_sided.png';
  static const String modularAlternateEndcapPath =
      '$mainWorldModularRoot/fixture_endcap_alternate_mirrored.png';
  static const String modularCoolerBankPath =
      '$mainWorldModularRoot/fixture_cooler_bank_multidoor.png';
  static const String modularCheckoutRegisterPath =
      '$mainWorldModularRoot/fixture_checkout_register_module.png';
  static const List<String> mainWorldModularPaths = <String>[
    modularShortShelfPath,
    modularLongShelfPath,
    modularAlternateEndcapPath,
    modularCoolerBankPath,
    modularCheckoutRegisterPath,
  ];

  static const List<String> commercialFixturePaths = <String>[
    '$commercialRoot/phase_c_shelf.png',
    '$commercialRoot/phase_c_checkout.png',
    '$commercialRoot/phase_c_storage.png',
    '$commercialRoot/phase_c_bakery.png',
    '$commercialRoot/phase_c_entrance.png',
    '$commercialRoot/phase_c_cart_baskets.png',
    '$commercialRoot/phase_c_endcap.png',
    '$commercialRoot/phase_c_cooler.png',
  ];

  static const List<String> allProductionPaths = <String>[
    ...playerPaths,
    ...staffPaths,
    ...customerPaths,
    ...fixturePaths,
    ...environmentPaths,
  ];

  static const List<String> retainedEnvironmentPaths = <String>[
    cleaningCartPath,
    deliveryBoxesPath,
  ];

  static const List<String> activeRuntimePaths = <String>[
    ...playerPaths,
    ...staffPaths,
    ...customerPaths,
    ...retainedEnvironmentPaths,
    ...mainWorldV2Paths,
    ...mainWorldModularPaths,
  ];

  static final _ArtRepaintNotifier _repaintNotifier = _ArtRepaintNotifier();
  static final Map<String, ui.Image> _images = <String, ui.Image>{};
  static Future<void>? _loadFuture;

  static Listenable get repaintNotifier => _repaintNotifier;
  static ui.Image? image(String path) => _images[path];
  static ui.Rect? sourceRect(String path) {
    final image = _images[path];
    if (image == null) return null;
    return ui.Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
  }

  static ui.Offset pivot(String path) => const ui.Offset(.5, 1);
  static Future<void> load() => _loadFuture ??= _loadAll();

  static Future<void> _loadAll() async {
    // Decode in parallel: the world stays empty until every sprite is ready,
    // so sequential decoding made first launch show a bare floor for seconds.
    final images = await Future.wait<ui.Image>(
      activeRuntimePaths.map(_decode),
    );
    _images.addEntries(<MapEntry<String, ui.Image>>[
      for (var i = 0; i < activeRuntimePaths.length; i++)
        MapEntry<String, ui.Image>(activeRuntimePaths[i], images[i]),
    ]);
    _repaintNotifier.refresh();
  }

  static Future<ui.Image> decodeBundledAsset(String path) => _decode(path);

  static Future<ui.Image> _decode(String path) async {
    final data = await rootBundle.load(path);
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    late final ui.Image image;
    try {
      image = (await codec.getNextFrame()).image;
    } finally {
      codec.dispose();
    }
    // The modular fixtures ship with transparent backgrounds, so the old
    // runtime matte pass changed no pixels while reading back ~5 MP of RGBA
    // on the UI thread. test/main_world_modular_assets_test.dart checks the
    // bundled files stay transparent instead.
    return image;
  }
}
