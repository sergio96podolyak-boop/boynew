import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomarket/game/game_controller.dart';
import 'package:pomarket/game/game_models.dart';
import 'package:pomarket/services/game_storage.dart';
import 'package:pomarket/services/monetization_service.dart';
import 'package:pomarket/ui/widgets/celebration_overlay.dart';

void main() {
  testWidgets('CelebrationOverlay honors the platform animation setting', (
    tester,
  ) async {
    final controller = CelebrationController();
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: CelebrationOverlay(
          controller: controller,
          child: const Text('market'),
        ),
      ),
    );

    controller.celebrate();
    await tester.pump();

    expect(controller.sequence, 1);
    expect(find.text('market'), findsOneWidget);
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('CelebrationOverlay honors the in-app reduced motion setting', (
    tester,
  ) async {
    final controller = CelebrationController();
    await tester.pumpWidget(
      MaterialApp(
        home: CelebrationOverlay(
          controller: controller,
          reducedMotion: true,
          child: const Text('market'),
        ),
      ),
    );

    controller.celebrate();
    await tester.pump();

    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('enabling reduced motion stops an active celebration', (
    tester,
  ) async {
    final controller = CelebrationController();

    Widget buildOverlay(bool reducedMotion) => MaterialApp(
      home: CelebrationOverlay(
        controller: controller,
        reducedMotion: reducedMotion,
        child: const Text('market'),
      ),
    );

    await tester.pumpWidget(buildOverlay(false));
    controller.celebrate();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.binding.hasScheduledFrame, isTrue);

    await tester.pumpWidget(buildOverlay(true));
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('platform reduced motion stops an active celebration', (
    tester,
  ) async {
    final controller = CelebrationController();

    Widget buildOverlay(bool disableAnimations) => MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(disableAnimations: disableAnimations),
        child: child!,
      ),
      home: CelebrationOverlay(
        controller: controller,
        child: const Text('market'),
      ),
    );

    await tester.pumpWidget(buildOverlay(false));
    controller.celebrate();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.binding.hasScheduledFrame, isTrue);

    await tester.pumpWidget(buildOverlay(true));
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('CelebrationOverlay animates and disposes without errors', (
    tester,
  ) async {
    final controller = CelebrationController();
    await tester.pumpWidget(
      MaterialApp(
        home: CelebrationOverlay(
          controller: controller,
          child: const Text('market'),
        ),
      ),
    );

    controller.celebrate();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(CustomPaint), findsWidgets);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    expect(tester.takeException(), isNull);
  });

  test('FloatingTextEffect follows position, opacity, and expiry lifecycle', () {
    final effect = FloatingTextEffect(
      text: '+10',
      position: const Offset(0.4, 0.5),
      color: Colors.green,
      lifetime: 2,
    );

    expect(effect.progress, 0);
    expect(effect.opacity, 1);
    expect(effect.currentPosition, effect.position);
    expect(effect.isExpired, isFalse);

    effect.elapsed = 1;
    expect(effect.progress, 0.5);
    expect(effect.opacity, 0.5);
    expect(effect.currentPosition, const Offset(0.4, 0.47));

    effect.elapsed = 2;
    expect(effect.progress, 1);
    expect(effect.opacity, 0);
    expect(effect.currentPosition, const Offset(0.4, 0.44));
    expect(effect.isExpired, isTrue);

    effect.elapsed = 3;
    expect(effect.progress, 1);
    expect(effect.opacity, 0);
    expect(effect.currentPosition, const Offset(0.4, 0.44));
  });

  test('zero-lifetime floating text is immediately complete and finite', () {
    final effect = FloatingTextEffect(
      text: 'done',
      position: const Offset(0.2, 0.3),
      color: Colors.white,
      lifetime: 0,
    );

    expect(effect.progress, 1);
    expect(effect.opacity, 0);
    expect(effect.isExpired, isTrue);
    expect(effect.currentPosition.dx.isFinite, isTrue);
    expect(effect.currentPosition.dy.isFinite, isTrue);
  });

  test('game simulation expires floating text and caps retained effects', () async {
    final game = GameController(
      storage: MemoryGameStorage(),
      monetization: PreviewMonetizationService(),
      random: Random(2),
    );
    await game.initialize();

    for (var index = 0; index < 35; index++) {
      game.spawnFloatingText('$index', Offset.zero, Colors.green);
    }
    expect(game.floatingEffects, hasLength(30));
    expect(game.floatingEffects.first.text, '5');

    for (var frame = 0; frame < 25; frame++) {
      game.tick(0.05);
    }
    expect(game.floatingEffects, isEmpty);
  });
}
