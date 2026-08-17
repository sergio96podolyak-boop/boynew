// Temporary design-review harness: renders every UI surface to a PNG so the
// redesign can be inspected without driving a browser. Not a behavioural test.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomarket/game/game_controller.dart';
import 'package:pomarket/main.dart';
import 'package:pomarket/services/app_settings.dart';
import 'package:pomarket/services/game_storage.dart';
import 'package:pomarket/services/monetization_service.dart';
import 'package:pomarket/ui/widgets/game_dock.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _outDir = 'build/design_shots';

final _boundaryKey = GlobalKey();

Future<void> _shoot(WidgetTester tester, String name) async {
  final boundary =
      _boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await tester.binding.runAsync(
    () => boundary.toImage(pixelRatio: 2),
  );
  final data = await tester.binding.runAsync(
    () => image!.toByteData(format: ui.ImageByteFormat.png),
  );
  Directory(_outDir).createSync(recursive: true);
  File(
    '$_outDir/$name.png',
  ).writeAsBytesSync(data!.buffer.asUint8List(), flush: true);
}

Future<GameController> _game({int coins = 4200}) async {
  final controller = GameController(
    storage: MemoryGameStorage(),
    monetization: PreviewMonetizationService(),
  );
  await controller.initialize();
  controller.completeOnboarding();
  controller.acknowledgeDailyBonus();
  controller.coins = coins;
  controller.gems = 38;
  return controller;
}

Future<void> _open(WidgetTester tester, String label) async {
  // Progress snack bars float over the dock and would swallow the tap.
  if (find.byType(SnackBar).evaluate().isNotEmpty) {
    await tester.pump(const Duration(seconds: 5));
  }
  final dock = find.byType(GameDock);
  var target = find.descendant(of: dock, matching: find.text(label));
  if (target.evaluate().isEmpty) {
    await tester.tap(find.descendant(of: dock, matching: find.text('More')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));
    target = find.descendant(of: dock, matching: find.text(label));
  }
  await tester.tap(target);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 340));
  // Navigation plays SFX, and the audioplayers plugin has no test
  // implementation for its per-player event channels. Drain those so the
  // capture run is not aborted by an unrelated platform-channel error.
  tester.takeException();
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(const <String, Object>{});

  setUpAll(() {
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

  testWidgets('capture every surface for design review', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = await _game();
    await tester.pumpWidget(
      RepaintBoundary(
        key: _boundaryKey,
        child: PoMarketApp(
          controller: controller,
          settings: AppSettings(),
          showSplash: false,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    tester.takeException();

    await _shoot(tester, '01-market');
    for (final (label, name) in const [
      ('Upgrades', '02-upgrades'),
      ('Staff', '03-staff'),
      ('Shop', '04-shop'),
      ('Departments', '05-departments'),
      ('Inventory', '06-inventory'),
      ('Quests', '07-quests'),
      ('Achievements', '08-achievements'),
      ('Settings', '09-settings'),
    ]) {
      await _open(tester, label);
      await _shoot(tester, name);
    }

    // Overflow tray open, so the secondary navigation can be reviewed too.
    await tester.tap(
      find.descendant(of: find.byType(GameDock), matching: find.text('More')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 340));
    tester.takeException();
    await _shoot(tester, '10-dock-tray');
  });

  testWidgets('capture tablet and desktop widths', (tester) async {
    for (final (size, name) in const [
      (Size(834, 1112), '11-tablet-upgrades'),
      (Size(1440, 900), '12-desktop-upgrades'),
    ]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      final controller = await _game();
      await tester.pumpWidget(
        RepaintBoundary(
          key: _boundaryKey,
          child: PoMarketApp(
            controller: controller,
            settings: AppSettings(),
            showSplash: false,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      tester.takeException();
      await _open(tester, 'Upgrades');
      await _shoot(tester, name);
    }
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
