import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomarket/game/game_controller.dart';
import 'package:pomarket/game/game_models.dart';
import 'package:pomarket/main.dart';
import 'package:pomarket/services/app_settings.dart';
import 'package:pomarket/services/game_storage.dart';
import 'package:pomarket/services/monetization_service.dart';
import 'package:pomarket/ui/iso/iso_market_painter.dart';
import 'package:pomarket/ui/vertical_slice_world_painter.dart';
import 'package:pomarket/ui/world_motion.dart';

void main() {
  test('reduced motion preserves customer payment state without motion', () {
    final customer = MarketCustomer(
      id: 1,
      position: const Offset(.4, .4),
      color: Colors.blue,
    )..phase = CustomerPhase.paying;
    final profile = WorldMotion.customer(
      customer: customer,
      time: 1,
      reducedMotion: true,
      target: const Offset(.8, .4),
    );
    expect(profile.activity, WorldMotionActivity.paying);
    expect(profile.hasMotion, isFalse);
  });

  testWidgets('reduced-motion board-local world renders without exceptions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final game = GameController(
      storage: MemoryGameStorage(),
      monetization: PreviewMonetizationService(),
    );
    await game.initialize();
    game.completeOnboarding();
    game.acknowledgeDailyBonus();

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: PoMarketApp(
          controller: game,
          settings: AppSettings(),
          showSplash: false,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(VerticalSliceRenderSettings.reducedMotion, isTrue);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is CustomPaint && widget.painter is IsoMarketPainter,
      ),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('world-art-polish-layer')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
