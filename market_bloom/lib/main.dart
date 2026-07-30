import 'package:flutter_localizations/flutter_localizations.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'game/game_controller.dart';
import 'services/app_localizations.dart';
import 'services/app_settings.dart';
import 'services/game_storage.dart';
import 'services/monetization_service.dart';
import 'services/app_localizations_delegate.dart';
import 'ui/app_shell.dart';
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

  final settings = AppSettings();
  final monetization = createMonetizationService();
  final controller = GameController(
    storage: SharedPreferencesGameStorage(),
    monetization: monetization,
  );
  final readiness = _prepareGame(controller, monetization, settings);

  runApp(
    PoMarketApp(
      controller: controller,
      settings: settings,
      readiness: readiness,
    ),
  );
}

Future<void> _prepareGame(
  GameController controller,
  MonetizationService monetization,
  AppSettings settings,
) async {
  await Future.wait<void>([
    controller.initialize(),
    settings.load(),
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

class PoMarketApp extends StatelessWidget {
  const PoMarketApp({
    super.key,
    required this.controller,
    required this.settings,
    this.showSplash = true,
    this.splashDuration = const Duration(milliseconds: 2400),
    this.readiness,
  });

  final GameController controller;
  final AppSettings settings;
  final bool showSplash;
  final Duration splashDuration;
  final Future<void>? readiness;

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF38B879);

    return AnimatedBuilder(
      animation: settings,
      builder: (context, _) {
        final locale = settings.isLoaded
            ? settings.language
            : const Locale('en');

        return MaterialApp(
          title: 'PoMarket',
          debugShowCheckedModeBanner: false,
          locale: locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: <LocalizationsDelegate<dynamic>>[
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            AppLocalizationsDelegate(),
          ],
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
          home: _AppHome(
            controller: controller,
            settings: settings,
            showSplash: showSplash,
            splashDuration: splashDuration,
            readiness: readiness,
          ),
        );
      },
    );
  }
}

class _AppHome extends StatefulWidget {
  const _AppHome({
    required this.controller,
    required this.settings,
    required this.showSplash,
    required this.splashDuration,
    required this.readiness,
  });

  final GameController controller;
  final AppSettings settings;
  final bool showSplash;
  final Duration splashDuration;
  final Future<void>? readiness;

  @override
  State<_AppHome> createState() => _AppHomeState();
}

class _AppHomeState extends State<_AppHome> {
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
    final localizations = AppLocalizations.of(context);
    return Directionality(
      textDirection: localizations.isRtl
          ? TextDirection.rtl
          : TextDirection.ltr,
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
            : AppShell(
                key: const ValueKey('pomarket-app-shell'),
                controller: widget.controller,
                settings: widget.settings,
              ),
      ),
    );
  }
}
