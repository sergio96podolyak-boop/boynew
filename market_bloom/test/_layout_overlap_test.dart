// Layout guard for the market screen.
//
// Every persistent chrome layer now lives in one column, so overlap should be
// structurally impossible. This measures the real painted bounds at a range of
// viewports and fails if any two layers intersect — checking the property
// rather than trusting that the column stayed a column.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomarket/game/daily_event_game_controller.dart';
import 'package:pomarket/game/daily_event_models.dart';
import 'package:pomarket/game/game_models.dart';
import 'package:pomarket/main.dart';
import 'package:pomarket/services/app_settings.dart';
import 'package:pomarket/services/game_storage.dart';
import 'package:pomarket/services/monetization_service.dart';
import 'package:pomarket/ui/widgets/global_hud.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _event = DailyEventDefinition(
  id: 'layout-event',
  type: MarketEventType.flashSale,
  title: 'Flash Sale',
  description: 'Featured products are worth more today.',
  effectSummary: 'Sale value +20%',
  modifiers: DailyEventModifiers(),
);

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    for (final name in const [
      'xyz.luan/audioplayers',
      'xyz.luan/audioplayers.global',
    ]) {
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        MethodChannel(name),
        (call) async => null,
      );
    }
  });

  testWidgets('market chrome layers never overlap at any viewport', (
    tester,
  ) async {
    const sizes = <Size>[
      Size(320, 568),
      Size(360, 640),
      Size(390, 844),
      Size(430, 932),
      Size(768, 1024),
      Size(1280, 800),
    ];

    for (final size in sizes) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = DailyEventGameController(
        storage: MemoryGameStorage(),
        monetization: PreviewMonetizationService(),
        forcedEvent: _event,
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
      await tester.pump(const Duration(milliseconds: 260));

      // Each persistent layer, in the order it should stack down the screen.
      final layers = <String, Finder>{
        'hud': find.byType(GlobalHud),
        'mission': find.byKey(const ValueKey('objective-strip')),
        'actions': find.byKey(const ValueKey('world-context-actions')),
        'event': find.byKey(const ValueKey('daily-event-banner')),
        'dock': find.byKey(const ValueKey('mobile-game-navigation')),
      };

      final bounds = <String, Rect>{};
      for (final entry in layers.entries) {
        if (entry.value.evaluate().isEmpty) continue;
        bounds[entry.key] = tester.getRect(entry.value);
      }

      final names = bounds.keys.toList();
      for (var i = 0; i < names.length; i++) {
        for (var j = i + 1; j < names.length; j++) {
          final a = bounds[names[i]]!;
          final b = bounds[names[j]]!;
          expect(
            a.overlaps(b),
            isFalse,
            reason:
                '${names[i]} $a overlaps ${names[j]} $b at $size',
          );
        }
      }

      // Nothing may be pushed off the bottom of the screen either.
      final viewport = tester.getRect(
        find.byKey(const ValueKey('pomarket-app-shell')),
      );
      for (final entry in bounds.entries) {
        expect(
          entry.value.bottom,
          lessThanOrEqualTo(viewport.bottom + 0.5),
          reason: '${entry.key} runs past the viewport bottom at $size',
        );
        expect(
          entry.value.top,
          greaterThanOrEqualTo(viewport.top - 0.5),
          reason: '${entry.key} runs past the viewport top at $size',
        );
      }

      expect(tester.takeException(), isNull, reason: 'at $size');
    }
  });
}
