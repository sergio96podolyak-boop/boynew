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
import 'ui/theme/po_system.dart';
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
          theme: _poTheme(colorScheme),
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
                  scale: Tween<double>(begin: 0.985, end: 1).animate(animation),
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

/// Global Material theme.
///
/// The game draws its own controls for anything the player touches during a
/// shift, but the management screens still use Material buttons, snack bars and
/// dialogs in ~70 places. Theming them here means those all inherit the design
/// system instead of each screen restyling one button at a time.
ThemeData _poTheme(ColorScheme colorScheme) {
  final base = ThemeData.light(useMaterial3: true);
  return ThemeData(
    colorScheme: colorScheme.copyWith(
      primary: PoColor.primaryDeep,
      secondary: PoColor.secondaryDeep,
      surface: PoColor.surface,
      error: PoColor.danger,
    ),
    scaffoldBackgroundColor: PoColor.canvas,
    useMaterial3: true,
    fontFamilyFallback: const ['Arial', 'Helvetica'],
    textTheme: base.textTheme
        .apply(bodyColor: PoColor.ink, displayColor: PoColor.ink)
        .copyWith(
          headlineSmall: PoText.h1,
          titleLarge: PoText.h2,
          titleMedium: PoText.h3,
          titleSmall: PoText.title,
          bodyMedium: PoText.body,
          bodySmall: PoText.bodySm,
          labelLarge: PoText.button,
          labelMedium: PoText.label,
          labelSmall: PoText.caption,
        ),
    splashFactory: InkSparkle.splashFactory,
    appBarTheme: const AppBarTheme(
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: PoColor.surface,
      foregroundColor: PoColor.ink,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: PoText.h1,
    ),
    dividerTheme: const DividerThemeData(
      color: PoColor.hairline,
      thickness: 1,
      space: PoSpace.lg,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: PoColor.ink,
      elevation: 10,
      insetPadding: const EdgeInsets.all(PoSpace.md),
      actionTextColor: PoColor.primaryFace,
      contentTextStyle: PoText.title.copyWith(color: Colors.white),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(PoRadius.md),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: PoColor.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 24,
      shadowColor: PoColor.ink.withValues(alpha: 0.4),
      insetPadding: const EdgeInsets.symmetric(
        horizontal: PoSpace.lg,
        vertical: PoSpace.xl,
      ),
      titleTextStyle: PoText.h1,
      contentTextStyle: PoText.body,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(PoRadius.xl),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: PoColor.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 24,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(PoRadius.xl)),
      ),
      dragHandleColor: PoColor.hairlineStrong,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: PoColor.primaryFace,
      linearTrackColor: Color(0xFFDCE6E0),
      linearMinHeight: 8,
      borderRadius: BorderRadius.all(Radius.circular(PoRadius.pill)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: PoColor.surfaceSunken,
      hintStyle: PoText.body.copyWith(color: PoColor.textTertiary),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: PoSpace.md,
        vertical: PoSpace.md,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(PoRadius.sm),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(PoRadius.sm),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(PoRadius.sm),
        borderSide: const BorderSide(color: PoColor.primaryFace, width: 2),
      ),
    ),
    // Primary Material action: saturated brand face, dark ink, generous radius
    // and a real elevation so it reads as the thing to press.
    filledButtonTheme: FilledButtonThemeData(
      style:
          FilledButton.styleFrom(
            minimumSize: const Size(48, 48),
            backgroundColor: PoColor.primaryDeep,
            foregroundColor: Colors.white,
            disabledBackgroundColor: PoColor.surfaceMuted,
            disabledForegroundColor: PoColor.textDisabled,
            elevation: 3,
            shadowColor: PoColor.ink.withValues(alpha: 0.30),
            padding: const EdgeInsets.symmetric(horizontal: PoSpace.lg),
            textStyle: PoText.button,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(PoRadius.md),
            ),
          ).copyWith(
            // Pressing collapses the elevation, which is the flat-UI equivalent of
            // the extruded controls used on the board.
            elevation: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.pressed) ? 0 : 3,
            ),
          ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        foregroundColor: PoColor.inkSoft,
        backgroundColor: PoColor.surface,
        disabledForegroundColor: PoColor.textDisabled,
        side: const BorderSide(color: PoColor.hairlineStrong, width: 1.4),
        padding: const EdgeInsets.symmetric(horizontal: PoSpace.lg),
        textStyle: PoText.button,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PoRadius.md),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 48),
        foregroundColor: PoColor.primaryDeep,
        textStyle: PoText.button,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PoRadius.sm),
        ),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: const Size(48, 48),
        foregroundColor: PoColor.inkSoft,
        tapTargetSize: MaterialTapTargetSize.padded,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PoRadius.sm),
        ),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? Colors.white
            : const Color(0xFFF6F9F7),
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? PoColor.primaryFace
            : const Color(0xFFD5DFD9),
      ),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    sliderTheme: const SliderThemeData(
      activeTrackColor: PoColor.primaryFace,
      inactiveTrackColor: Color(0xFFD5DFD9),
      thumbColor: Colors.white,
      trackHeight: 6,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: PoColor.ink,
        borderRadius: BorderRadius.circular(PoRadius.xs),
      ),
      textStyle: PoText.caption.copyWith(color: Colors.white),
    ),
  );
}
