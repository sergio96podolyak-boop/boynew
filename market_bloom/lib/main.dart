import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'game/daily_event_game_controller.dart';
import 'game/game_controller.dart';
import 'services/analytics/analytics_factory.dart';
import 'services/analytics/analytics_monetization_service.dart';
import 'services/analytics/analytics_service.dart';
import 'services/analytics/game_analytics_tracker.dart';
import 'services/app_localizations.dart';
import 'services/app_localizations_delegate.dart';
import 'services/app_settings.dart';
import 'services/cloud_save/cloud_save_factory.dart';
import 'services/crash_reporting/crash_reporter_factory.dart';
import 'services/crash_reporting/error_reporting_coordinator.dart';
import 'services/monetization_service.dart';
import 'services/privacy/privacy_runtime_coordinator.dart';
import 'ui/app_shell.dart';
import 'ui/splash_screen.dart';
import 'ui/widgets/cloud_save_status_layer.dart';
import 'ui/widgets/daily_event_banner.dart';
import 'ui/widgets/premium_ui.dart';
import 'ui/widgets/privacy_consent_layer.dart';

GameAnalyticsTracker? analyticsTracker;
ErrorReportingCoordinator? errorReportingCoordinator;
PrivacyRuntimeCoordinator? privacyRuntimeCoordinator;

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
  final analytics = createAnalyticsService(settings);
  final crashReporter = createCrashReporter(settings);
  errorReportingCoordinator = ErrorReportingCoordinator(
    analytics: analytics,
    crashReporter: crashReporter,
  )..install();
  final monetization = AnalyticsMonetizationService(
    delegate: createMonetizationService(settings: settings),
    analytics: analytics,
  );
  privacyRuntimeCoordinator = PrivacyRuntimeCoordinator(
    settings: settings,
    crashReporter: crashReporter,
    monetization: monetization,
  );
  final controller = DailyEventGameController(
    storage: createCloudGameStorage(),
    monetization: monetization,
  );
  final readiness = _prepareGame(controller, settings, analytics);

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
  AppSettings settings,
  AnalyticsService analytics,
) async {
  await Future.wait<void>([controller.initialize(), settings.load()]);
  privacyRuntimeCoordinator?.start();
  analyticsTracker = GameAnalyticsTracker(
    game: controller,
    analytics: analytics,
  )..start();
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
        final colorScheme = ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.light,
        );
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
            colorScheme: colorScheme,
            scaffoldBackgroundColor: PoMarketPalette.canvas,
            useMaterial3: true,
            fontFamilyFallback: const ['Arial', 'Helvetica'],
            textTheme: ThemeData.light(useMaterial3: true).textTheme.apply(
              bodyColor: PoMarketPalette.ink,
              displayColor: PoMarketPalette.ink,
            ),
            appBarTheme: const AppBarTheme(
              elevation: 0,
              scrolledUnderElevation: 0,
              backgroundColor: PoMarketPalette.canvas,
              foregroundColor: PoMarketPalette.ink,
              surfaceTintColor: Colors.transparent,
              titleTextStyle: TextStyle(
                color: PoMarketPalette.ink,
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
            snackBarTheme: SnackBarThemeData(
              behavior: SnackBarBehavior.floating,
              backgroundColor: PoMarketPalette.forest,
              contentTextStyle: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: PoMarketPalette.cream,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: PoMarketPalette.line),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: PoMarketPalette.line),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(
                  color: PoMarketPalette.mint,
                  width: 2,
                ),
              ),
            ),
            filledButtonTheme: FilledButtonThemeData(
              style: FilledButton.styleFrom(
                minimumSize: const Size(48, 48),
                backgroundColor: PoMarketPalette.forest,
                foregroundColor: Colors.white,
                disabledBackgroundColor: PoMarketPalette.muted.withValues(
                  alpha: 0.22,
                ),
                disabledForegroundColor: PoMarketPalette.muted,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
            outlinedButtonTheme: OutlinedButtonThemeData(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(48, 48),
                foregroundColor: PoMarketPalette.forest,
                side: const BorderSide(color: PoMarketPalette.line),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                minimumSize: const Size(48, 48),
                foregroundColor: PoMarketPalette.forest,
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
    if (!mounted || !_showSplash) return;
    setState(() => _showSplash = false);
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final reducedMotion =
        widget.settings.reducedMotion ||
        MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.accessibleNavigationOf(context);
    return Directionality(
      textDirection: localizations.isRtl
          ? TextDirection.rtl
          : TextDirection.ltr,
      child: AnimatedSwitcher(
        duration: reducedMotion
            ? Duration.zero
            : const Duration(milliseconds: 520),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: reducedMotion
            ? (child, animation) => child
            : (child, animation) => FadeTransition(
                opacity: animation,
                child: ScaleTransition(
                  scale: Tween<double>(
                    begin: 0.985,
                    end: 1,
                  ).animate(animation),
                  child: child,
                ),
              ),
        child: _showSplash
            ? PoMarketSplash(
                key: const ValueKey('pomarket-splash'),
                minimumDuration: widget.splashDuration,
                readiness: widget.readiness,
                onComplete: _openMarket,
              )
            : PrivacyConsentLayer(
                key: const ValueKey('pomarket-privacy-consent-layer'),
                settings: widget.settings,
                child: CloudSaveStatusLayer(
                  key: const ValueKey('pomarket-cloud-save-layer'),
                  game: widget.controller,
                  settings: widget.settings,
                  child: DailyEventBannerLayer(
                    key: const ValueKey('pomarket-daily-event-layer'),
                    game: widget.controller,
                    settings: widget.settings,
                    child: AppShell(
                      key: const ValueKey('pomarket-app-shell'),
                      controller: widget.controller,
                      settings: widget.settings,
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}
