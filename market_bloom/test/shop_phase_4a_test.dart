import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomarket/game/game_controller.dart';
import 'package:pomarket/services/app_localizations.dart';
import 'package:pomarket/services/app_localizations_delegate.dart';
import 'package:pomarket/services/game_storage.dart';
import 'package:pomarket/services/monetization_service.dart';
import 'package:pomarket/ui/screens/shop_screen.dart';

void main() {
  testWidgets('Phase 4A shop exposes clear categories and 44px controls', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = await _controller(PreviewMonetizationService());

    await tester.pumpWidget(_app(controller));
    await tester.pump();

    for (final category in <String>[
      'all',
      'rewards',
      'benefits',
      'offers',
      'currency',
      'supplies',
    ]) {
      final chip = find.byKey(ValueKey('shop-category-$category'));
      expect(chip, findsOneWidget);
      expect(tester.getSize(chip).height, greaterThanOrEqualTo(44));
    }

    final buy = find.byKey(const ValueKey('shop-buy-noAds'));
    expect(buy, findsOneWidget);
    expect(tester.getSize(buy).height, greaterThanOrEqualTo(44));
    expect(find.text('Locked'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Phase 4A shop reports payment or insufficient-funds failure', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = await _controller(_FailingStore());

    await tester.pumpWidget(_app(controller));
    await tester.pump();

    final buy = find.byKey(const ValueKey('shop-buy-noAds'));
    final verticalScroll = find
        .descendant(
          of: find.byType(ShopScreen),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(buy, 400, scrollable: verticalScroll);
    await tester.tap(buy);
    await tester.pump();

    // The failed product keeps its local state while the stable feedback
    // overlay repeats the actionable message at the bottom of the viewport.
    expect(find.text('Payment issue'), findsWidgets);
    expect(find.textContaining('available funds'), findsWidgets);
    expect(find.byKey(const ValueKey('shop-feedback-error')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Phase 4A shop controls participate in keyboard focus', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = await _controller(_FailingStore());

    await tester.pumpWidget(_app(controller));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();

    expect(FocusManager.instance.primaryFocus, isNotNull);
    expect(tester.takeException(), isNull);
  });
}

Future<GameController> _controller(MonetizationService monetization) async {
  final controller = GameController(
    storage: MemoryGameStorage(),
    monetization: monetization,
  );
  await controller.initialize();
  return controller;
}

Widget _app(GameController controller) {
  return MaterialApp(
    locale: const Locale('en'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
      AppLocalizationsDelegate(),
    ],
    home: ShopScreen(controller: controller),
  );
}

class _FailingStore implements MonetizationService {
  @override
  bool get interstitialAdsAvailable => false;
  @override
  bool get isPreview => false;
  @override
  bool get rewardedAdsAvailable => false;
  @override
  bool get storeAvailable => true;
  @override
  void dispose() {}
  @override
  Future<void> initialize() async {}
  @override
  String? priceFor(StoreProduct product) => switch (product) {
    StoreProduct.noAds => r'$2.99',
    StoreProduct.coinPack => r'$1.99',
    StoreProduct.gemPack => r'$2.99',
    StoreProduct.emergencySupply => r'$0.99',
    StoreProduct.starterPack => r'$4.99',
  };
  @override
  Future<StorePurchaseResult> purchase(StoreProduct product) async =>
      StorePurchaseResult.failed(product);
  @override
  Future<List<StorePurchaseResult>> restorePurchases() async =>
      const <StorePurchaseResult>[];
  @override
  Future<bool> showInterstitial(InterstitialPlacement placement) async => false;
  @override
  Future<bool> showRewardedAd(RewardPlacement placement) async => false;
}
