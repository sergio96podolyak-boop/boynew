import 'dart:async';
import 'dart:collection';
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
    final loaded = <MapEntry<String, ui.Image>>[];
    for (final path in activeRuntimePaths) {
      loaded.add(MapEntry<String, ui.Image>(path, await _decode(path)));
    }
    _images.addEntries(loaded);
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
    if (!mainWorldModularPaths.contains(path)) return image;
    final cleaned = await _removeEdgeConnectedWhiteMatte(image);
    image.dispose();
    return cleaned;
  }

  /// Removes only near-white pixels connected to the image border. This keeps
  /// light fixture details intact while turning the exported rectangular matte
  /// into real transparent runtime pixels.
  static Future<ui.Image> _removeEdgeConnectedWhiteMatte(ui.Image image) async {
    final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (byteData == null) return image.clone();
    final width = image.width;
    final height = image.height;
    final pixels = Uint8List.fromList(byteData.buffer.asUint8List());
    final visited = Uint8List(width * height);
    final queue = Queue<int>();

    bool isMatte(int pixelIndex) {
      final offset = pixelIndex * 4;
      final red = pixels[offset];
      final green = pixels[offset + 1];
      final blue = pixels[offset + 2];
      final alpha = pixels[offset + 3];
      final minimum = red < green
          ? (red < blue ? red : blue)
          : (green < blue ? green : blue);
      final maximum = red > green
          ? (red > blue ? red : blue)
          : (green > blue ? green : blue);
      return alpha > 0 && minimum >= 232 && maximum - minimum <= 18;
    }

    void enqueue(int pixelIndex) {
      if (visited[pixelIndex] != 0 || !isMatte(pixelIndex)) return;
      visited[pixelIndex] = 1;
      queue.add(pixelIndex);
    }

    for (var x = 0; x < width; x++) {
      enqueue(x);
      enqueue((height - 1) * width + x);
    }
    for (var y = 0; y < height; y++) {
      enqueue(y * width);
      enqueue(y * width + width - 1);
    }

    while (queue.isNotEmpty) {
      final pixelIndex = queue.removeFirst();
      final offset = pixelIndex * 4;
      pixels[offset + 3] = 0;
      final x = pixelIndex % width;
      final y = pixelIndex ~/ width;
      if (x > 0) enqueue(pixelIndex - 1);
      if (x + 1 < width) enqueue(pixelIndex + 1);
      if (y > 0) enqueue(pixelIndex - width);
      if (y + 1 < height) enqueue(pixelIndex + width);
    }

    final buffer = await ui.ImmutableBuffer.fromUint8List(pixels);
    final descriptor = ui.ImageDescriptor.raw(
      buffer,
      width: width,
      height: height,
      pixelFormat: ui.PixelFormat.rgba8888,
    );
    final cleanedCodec = await descriptor.instantiateCodec();
    try {
      return (await cleanedCodec.getNextFrame()).image;
    } finally {
      cleanedCodec.dispose();
      descriptor.dispose();
      buffer.dispose();
    }
  }
}
