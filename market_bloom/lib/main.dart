import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'game/game_controller.dart';
import 'services/game_storage.dart';
import 'services/monetization_service.dart';
import 'ui/game_screen.dart';
import 'ui/splash_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  unawaited(
    SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]),
  );
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
      systemNavigationBarColor: Color(0xFF063D2C),
      systemNavigationBarIconBrightness: Brightness.light,
      systemNavigationBarDividerColor: Color(0xFF063D2C),
    ),
  );

  final monetization = createMonetizationService();
  final controller = GameController(
    storage: SharedPreferencesGameStorage(),
    monetization: monetization,
  );
  final readiness = _prepareGame(controller, monetization);

  runApp(PoMarketApp(controller: controller, readiness: readiness));
}

Future<void> _prepareGame(
  GameController controller,
  MonetizationService monetization,
) async {
  await Future.wait<void>([
    controller.initialize(),
    _initializeMonetization(monetization),
  ]);
}

Future<void> _initializeMonetization(MonetizationService monetization) async {
  try {
    await monetization.initialize().timeout(const Duration(seconds: 4));
  } catch (error, stackTrace) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'PoMarket startup',
        context: ErrorDescription('while initializing optional store services'),
      ),
    );
  }
}

class PoMarketApp extends StatefulWidget {
  const PoMarketApp({
    super.key,
    required this.controller,
    this.showSplash = true,
    this.splashDuration = const Duration(milliseconds: 2400),
    this.readiness,
  });

  final GameController controller;
  final bool showSplash;
  final Duration splashDuration;
  final Future<void>? readiness;

  @override
  State<PoMarketApp> createState() => _PoMarketAppState();
}

class _PoMarketAppState extends State<PoMarketApp> {
  late bool _showSplash;

  @override
  void initState() {
    super.initState();
    _showSplash = widget.showSplash;
  }

  void _openMarket() {
    if (!mounted || !_showSplash) {
      return;
    }
    setState(() => _showSplash = false);
  }

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF38B879);

    return MaterialApp(
      title: 'PoMarket',
      debugShowCheckedModeBanner: false,
      locale: const Locale('en'),
      supportedLocales: const [Locale('en')],
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF5F1E8),
        useMaterial3: true,
        fontFamilyFallback: const ['Arial', 'Helvetica'],
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size(48, 48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(48, 48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            minimumSize: const Size(48, 48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
        iconButtonTheme: const IconButtonThemeData(
          style: ButtonStyle(
            minimumSize: WidgetStatePropertyAll(Size(48, 48)),
            tapTargetSize: MaterialTapTargetSize.padded,
          ),
        ),
      ),
      home: Directionality(
        textDirection: TextDirection.ltr,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 520),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) {
            return FadeTransition(
              opacity: animation,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.985, end: 1).animate(animation),
                child: child,
              ),
            );
          },
          child: _showSplash
              ? PoMarketSplash(
                  key: const ValueKey('pomarket-splash'),
                  minimumDuration: widget.splashDuration,
                  readiness: widget.readiness,
                  onComplete: _openMarket,
                )
              : GameScreen(
                  key: const ValueKey('pomarket-game'),
                  controller: widget.controller,
                ),
        ),
      ),
    );
  }
}
