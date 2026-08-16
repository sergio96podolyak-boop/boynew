import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomarket/game/game_controller.dart';
import 'package:pomarket/main.dart';
import 'package:pomarket/services/app_settings.dart';
import 'package:pomarket/services/game_storage.dart';
import 'package:pomarket/services/monetization_service.dart';
import 'package:pomarket/ui/iso/iso_market_painter.dart';
import 'package:pomarket/ui/vertical_slice_world_painter.dart';
import 'package:pomarket/ui/widgets/main_game_phase_two.dart';

void main() {
  testWidgets('main world has exactly one board-local world painter', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = GameController(
      storage: MemoryGameStorage(),
      monetization: PreviewMonetizationService(),
    );
    await controller.initialize();
    controller.completeOnboarding();
    controller.acknowledgeDailyBonus();

    await tester.pumpWidget(
      PoMarketApp(
        controller: controller,
        settings: AppSettings(),
        showSplash: false,
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    final worldPaint = find.byWidgetPredicate(
      (widget) => widget is CustomPaint && widget.painter is IsoMarketPainter,
    );
    expect(worldPaint, findsOneWidget);
    expect(find.byKey(const ValueKey('world-art-polish-layer')), findsNothing);
    expect(
      find.ancestor(
        of: worldPaint,
        matching: find.byKey(const ValueKey('market-board')),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('single board-local world fits target viewport classes', (
    tester,
  ) async {
    const sizes = <Size>[
      Size(1280, 800),
      Size(1024, 768),
      Size(768, 700),
      Size(390, 844),
      Size(320, 568),
    ];

    for (final size in sizes) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      final controller = GameController(
        storage: MemoryGameStorage(),
        monetization: PreviewMonetizationService(),
      );
      await controller.initialize();
      controller.completeOnboarding();
      controller.acknowledgeDailyBonus();

      await tester.pumpWidget(
        PoMarketApp(
          controller: controller,
          settings: AppSettings(),
          showSplash: false,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 220));

      expect(find.byType(MainGamePhaseTwo), findsOneWidget);
      expect(find.byKey(const ValueKey('market-board')), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) => widget is CustomPaint && widget.painter is IsoMarketPainter,
        ),
        findsOneWidget,
      );
      expect(
        tester.takeException(),
        isNull,
        reason: 'Board-local world layout at $size',
      );
    }

    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  testWidgets('world renderer honors platform reduced motion without overlay', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = GameController(
      storage: MemoryGameStorage(),
      monetization: PreviewMonetizationService(),
    );
    await controller.initialize();

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: MainGamePhaseTwo(
          game: controller,
          settings: AppSettings(),
          child: const ColoredBox(color: Colors.white),
        ),
      ),
    );
    await tester.pump();

    expect(VerticalSliceRenderSettings.reducedMotion, isTrue);
    expect(find.byKey(const ValueKey('world-art-polish-layer')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
