import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomarket/game/game_controller.dart';
import 'package:pomarket/services/app_localizations.dart';
import 'package:pomarket/services/app_localizations_delegate.dart';
import 'package:pomarket/services/app_settings.dart';
import 'package:pomarket/services/game_storage.dart';
import 'package:pomarket/services/monetization_service.dart';
import 'package:pomarket/ui/widgets/touch_movement.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
    'touch coordinate conversion round-trips through the painted market',
    () {
      const size = Size(320, 480);
      const world = Offset(0.43, 0.47);

      final local = TouchMovement.worldToLocal(world, size);
      final restored = TouchMovement.localToWorld(local, size);

      expect(restored.dx, closeTo(world.dx, 0.0001));
      expect(restored.dy, closeTo(world.dy, 0.0001));
    },
  );

  test('touch targets clamp to walkable bounds and snap to stations', () {
    expect(
      TouchMovement.clampWorldTarget(const Offset(-4, 8)),
      const Offset(0.06, 0.94),
    );
    expect(
      TouchMovement.snapToInteractionPoint(const Offset(0.44, 0.48)),
      GameController.shelfZone,
    );
  });

  testWidgets('tap moves smoothly while drag guidance starts near the player', (
    tester,
  ) async {
    final game = await _game();
    await tester.pumpWidget(_touchHarness(game));
    await tester.pump();

    final touchFinder = find.byType(TouchMovement);
    final touchSize = tester.getSize(touchFinder);
    final farTarget = TouchMovement.worldToLocal(
      const Offset(0.82, 0.58),
      touchSize,
    );

    await tester.tapAt(tester.getTopLeft(touchFinder) + farTarget);
    await tester.pump();
    expect(game.movementTarget, isNotNull);
    expect(game.playerPosition, isNot(equals(game.movementTarget)));

    game.clearMovementTarget();
    final playerLocal = TouchMovement.worldToLocal(
      game.playerPosition,
      touchSize,
    );
    final gesture = await tester.startGesture(
      tester.getTopLeft(touchFinder) + playerLocal,
    );
    await gesture.moveBy(const Offset(36, -24));
    await tester.pump();
    expect(game.movementTarget, isNotNull);
    await gesture.up();
    await tester.pump();
    expect(game.movementTarget, isNull);

    await tester.dragFrom(
      tester.getTopLeft(touchFinder) + const Offset(12, 12),
      const Offset(80, 40),
    );
    await tester.pump();
    expect(game.movementTarget, isNull);
  });

  testWidgets('overlay controls consume taps without moving the player', (
    tester,
  ) async {
    final game = await _game();
    var presses = 0;
    await tester.pumpWidget(
      _localizedApp(
        Stack(
          children: [
            TouchMovement(game: game, onTap: () {}),
            Align(
              alignment: Alignment.topCenter,
              child: FilledButton(
                onPressed: () => presses++,
                child: const Text('UI action'),
              ),
            ),
          ],
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('UI action'));
    await tester.pump();

    expect(presses, 1);
    expect(game.movementTarget, isNull);
  });

  testWidgets('joystick fallback is rendered only for joystick modes', (
    tester,
  ) async {
    final game = await _game();
    await tester.pumpWidget(
      _touchHarness(game, controlMode: ControlMode.joystick),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('movement-joystick')), findsOneWidget);

    await tester.pumpWidget(
      _touchHarness(game, controlMode: ControlMode.directTouch),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('movement-joystick')), findsNothing);
  });

  test('control setting persists across AppSettings instances', () async {
    final preferences = _MemoryPreferences();
    final first = AppSettings(preferences: preferences);
    await first.load();
    await first.setControlMode(ControlMode.leftJoystick);

    final restored = AppSettings(preferences: preferences);
    await restored.load();

    expect(restored.controlMode, ControlMode.leftJoystick);
  });
}

Future<GameController> _game() async {
  final game = GameController(
    storage: MemoryGameStorage(),
    monetization: PreviewMonetizationService(),
  );
  await game.initialize();
  return game;
}

Widget _touchHarness(
  GameController game, {
  ControlMode controlMode = ControlMode.directTouch,
}) {
  return _localizedApp(
    SizedBox(
      width: 320,
      height: 480,
      child: TouchMovement(game: game, onTap: () {}, controlMode: controlMode),
    ),
  );
}

Widget _localizedApp(Widget child) {
  return MaterialApp(
    locale: const Locale('en'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
      AppLocalizationsDelegate(),
    ],
    home: Scaffold(body: child),
  );
}

class _MemoryPreferences implements SharedPreferencesAsync {
  final Map<String, Object> _values = <String, Object>{};

  @override
  Future<void> clear({Set<String>? allowList}) async {
    if (allowList == null) {
      _values.clear();
      return;
    }
    _values.removeWhere((key, _) => allowList.contains(key));
  }

  @override
  Future<bool> containsKey(String key) async => _values.containsKey(key);

  @override
  Future<Map<String, Object?>> getAll({Set<String>? allowList}) async {
    return <String, Object?>{
      for (final entry in _values.entries)
        if (allowList == null || allowList.contains(entry.key))
          entry.key: entry.value,
    };
  }

  @override
  Future<bool?> getBool(String key) async => _values[key] as bool?;

  @override
  Future<double?> getDouble(String key) async => _values[key] as double?;

  @override
  Future<int?> getInt(String key) async => _values[key] as int?;

  @override
  Future<Set<String>> getKeys({Set<String>? allowList}) async {
    return _values.keys
        .where((key) => allowList == null || allowList.contains(key))
        .toSet();
  }

  @override
  Future<String?> getString(String key) async => _values[key] as String?;

  @override
  Future<List<String>?> getStringList(String key) async {
    return _values[key] as List<String>?;
  }

  @override
  Future<void> remove(String key) async {
    _values.remove(key);
  }

  @override
  Future<void> setBool(String key, bool value) async {
    _values[key] = value;
  }

  @override
  Future<void> setDouble(String key, double value) async {
    _values[key] = value;
  }

  @override
  Future<void> setInt(String key, int value) async {
    _values[key] = value;
  }

  @override
  Future<void> setString(String key, String value) async {
    _values[key] = value;
  }

  @override
  Future<void> setStringList(String key, List<String> value) async {
    _values[key] = List<String>.from(value);
  }
}
