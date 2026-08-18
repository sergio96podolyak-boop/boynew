import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../game/game_controller.dart';
import '../game/game_models.dart';
import '../game/meta_models.dart';
import '../services/app_localizations.dart';
import '../services/app_settings.dart';
import '../services/monetization_service.dart';
import '../services/sfx/sfx_backend.dart';
import '../services/sfx/sfx_manager.dart';
import 'iso/iso_market_painter.dart';
import 'iso/iso_projection.dart';
import 'market_painter.dart';
import 'theme/po_system.dart';
import 'theme/pomarket_design.dart';
import 'widgets/celebration_overlay.dart';
import 'widgets/onboarding_dialog.dart';
import 'widgets/pressable_scale.dart';
import 'widgets/shift_pnl_summary.dart';
import 'widgets/touch_movement.dart';

/// Board outline used by the lighting overlay.
///
/// Derived from the same layout [MarketPainter] paints with, so the grade lands
/// exactly on the room instead of bleeding past its rounded corners. Kept
/// top-level so the function identity is stable across rebuilds and the
/// overlay's `shouldRepaint` stays cheap.
RRect boardClipFor(Size size) {
  final layout = MarketWorldLayout.forSize(size);
  return RRect.fromRectAndRadius(
    layout.market,
    Radius.circular(22 * layout.scale),
  );
}

class GameScreen extends StatefulWidget {
  const GameScreen({
    super.key,
    required this.controller,
    required this.settings,
    this.onOpenStaff,
    this.onOpenInventory,
    this.onOpenDepartments,
    this.topChrome,
    this.bottomChrome,
  });

  final GameController controller;
  final AppSettings settings;
  final VoidCallback? onOpenStaff;
  final VoidCallback? onOpenInventory;
  final VoidCallback? onOpenDepartments;

  /// Persistent chrome the shell owns, placed in this screen's layout column.
  ///
  /// The HUD and the dock used to be positioned separately by the shell while
  /// this screen positioned its own pods with hardcoded offsets, so nothing
  /// knew how tall anything else was and the layers collided. Handing them in
  /// means one column owns every persistent layer and overlap is structurally
  /// impossible rather than tuned out by hand.
  final Widget? topChrome;
  final Widget? bottomChrome;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final Ticker _ticker;
  Duration _previousElapsed = Duration.zero;
  bool _offlineSheetShown = false;
  bool _startupFlowStarted = false;
  bool _onboardingDialogOpen = false;
  AchievementDefinition? _achievementToast;
  Timer? _achievementToastTimer;
  final CelebrationController _celebration = CelebrationController();

  GameController get game => widget.controller;
  AppSettings get settings => widget.settings;
  ShiftPhase? _lastAmbientPhase;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ticker = createTicker(_onTick)..start();
    game.addListener(_onGameChanged);
    unawaited(SfxManager.instance.setMuted(game.muted, playFeedback: false));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_runStartupFlow());
      _onGameChanged();
    });
  }

  void _onTick(Duration elapsed) {
    final dt = (elapsed - _previousElapsed).inMicroseconds / 1000000;
    _previousElapsed = elapsed;
    game.tick(dt);
    _syncAmbientMusic();
  }

  void _syncAmbientMusic() {
    final phase = game.shiftPhase;
    if (phase == _lastAmbientPhase) {
      return;
    }
    _lastAmbientPhase = phase;
    final musicPhase = switch (phase) {
      ShiftPhase.preparation => MusicPhase.preparation,
      ShiftPhase.open => MusicPhase.open,
      ShiftPhase.rush => MusicPhase.rush,
      ShiftPhase.closing => MusicPhase.closing,
      ShiftPhase.summary => MusicPhase.silent,
    };
    unawaited(SfxManager.instance.playAmbient(musicPhase));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      game.clearMovementTarget();
      unawaited(game.save());
    }
  }

  Future<void> _runStartupFlow() async {
    if (_startupFlowStarted || !mounted) {
      return;
    }
    _startupFlowStarted = true;

    if (!game.onboardingComplete) {
      await _showOnboarding();
    }
    if (!mounted) {
      return;
    }
    if (game.pendingDailyBonus case final bonus?) {
      await _showDailyBonus(bonus);
    }
    if (!mounted) {
      return;
    }
    if (game.offlineEarnings > 0 && !_offlineSheetShown) {
      _offlineSheetShown = true;
      await _showOfflineEarnings();
    }
  }

  Future<void> _showOnboarding() async {
    if (_onboardingDialogOpen || !mounted) {
      return;
    }
    _onboardingDialogOpen = true;
    final completed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PoMarketOnboardingDialog(),
    );
    _onboardingDialogOpen = false;
    if (completed == true) {
      game.completeOnboarding();
      unawaited(SfxManager.instance.success());
    }
  }

  void _onGameChanged() {
    if (!mounted) {
      return;
    }
    if (game.takeTutorialReplayRequest()) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(_showOnboarding());
        }
      });
    }
    final department = game.takeDepartmentUnlock();
    if (department != null) {
      if (!settings.reducedMotion && !MediaQuery.disableAnimationsOf(context)) {
        _celebration.celebrate();
      }
      unawaited(SfxManager.instance.milestone());
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        final loc = AppLocalizations.of(context);
        final title = department == DepartmentType.bakery
            ? loc.bakeryUnlocked
            : loc.unlocked;
        final message = department == DepartmentType.bakery
            ? loc.bakeryUnlockedMessage
            : loc.departmentsTitle;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$title $message'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      });
    }
    if (_achievementToast != null) {
      return;
    }
    final achievement = game.takeAchievementUnlock();
    if (achievement == null) {
      return;
    }
    setState(() => _achievementToast = achievement);
    _celebration.celebrate();
    unawaited(SfxManager.instance.milestone());
    _achievementToastTimer?.cancel();
    _achievementToastTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) {
        return;
      }
      setState(() => _achievementToast = null);
      _onGameChanged();
    });
  }

  void _claimQuest() {
    if (!game.quest.completed) {
      return;
    }
    unawaited(SfxManager.instance.success());
    game.claimQuest();
  }

  @override
  void dispose() {
    unawaited(game.save());
    unawaited(SfxManager.instance.stopAmbient());
    game.removeListener(_onGameChanged);
    _achievementToastTimer?.cancel();
    _celebration.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CelebrationOverlay(
      controller: _celebration,
      child: DecoratedBox(
        // Deep stage behind the board so the lit market and the cream cards
        // read as foreground. A pale backdrop flattened both.
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              PoDepthColors.forest,
              PoDepthColors.canopy,
              PoDepthColors.deepSea,
            ],
            stops: [0, 0.5, 1],
          ),
        ),
        child: SafeArea(
          top: false,
          // Structural change: the board used to be a letterboxed square under
          // a column of chrome bars, capped at 560px, so the world was the
          // smallest thing on screen. It now fills the whole stage and every
          // other element floats over it — the world is the subject, the UI is
          // an overlay on it.
          child: Stack(
            key: const ValueKey('market-page-viewport'),
            fit: StackFit.expand,
            children: [
              AnimatedBuilder(
                animation: game,
                builder: (context, _) => Stack(
                  fit: StackFit.expand,
                  children: [
                    Positioned.fill(
                      key: const ValueKey('market-board'),
                      child: Stack(
                        children: [
                                        Positioned.fill(
                                          child: RepaintBoundary(
                                            child: CustomPaint(
                                              painter: IsoMarketPainter(
                                                game: game,
                                                storageLabel:
                                                    AppLocalizations.of(
                                                      context,
                                                    ).storage.toUpperCase(),
                                                bakeryLabel:
                                                    AppLocalizations.of(context)
                                                        .departmentBakery
                                                        .toUpperCase(),
                                                checkoutLabel:
                                                    AppLocalizations.of(context)
                                                        .assignmentCheckout
                                                        .toUpperCase(),
                                                shelfLabel: AppLocalizations.of(
                                                  context,
                                                ).shelfStock.toUpperCase(),
                                                textDirection:
                                                    Directionality.of(context),
                                              ),
                                            ),
                                          ),
                                        ),
                                        // The isometric painter does its own
                                        // lighting and vignette, so the old
                                        // flat-board grade overlay is dropped
                                        // here to avoid double-darkening.
                                        Positioned.fill(
                                          child: TouchMovement(
                                            game: game,
                                            onTap: () {},
                                            controlMode: settings.controlMode,
                                            // Map taps through the same iso
                                            // projection the board is drawn
                                            // with so the player walks to
                                            // where the finger lands.
                                            screenToWorld: (local, size) =>
                                                IsoProjection.fit(
                                                  size,
                                                ).unproject(local),
                                            worldToScreen: (world, size) =>
                                                IsoProjection.fit(
                                                  size,
                                                ).projectOffset(world),
                                          ),
                                        ),
                                        if (game.pendingShiftSummary != null)
                                          Positioned.fill(
                                            child: Padding(
                                              padding: const EdgeInsets.all(8),
                                              child: ShiftPnlSummary(
                                                summary:
                                                    game.pendingShiftSummary!,
                                                cashBalance: game.coins,
                                                onContinue: game.startNextShift,
                                              ),
                                            ),
                                          ),
                                        if (game.comboCount > 1)
                                          Positioned(
                                            top: 14,
                                            right: 14,
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 12,
                                                    vertical: 6,
                                                  ),
                                              decoration: BoxDecoration(
                                                gradient: const LinearGradient(
                                                  colors: [
                                                    Color(0xFFFFA726),
                                                    Color(0xFFEE4664),
                                                  ],
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(20),
                                                boxShadow: const [
                                                  BoxShadow(
                                                    color: Color(0x66EE4664),
                                                    blurRadius: 8,
                                                    offset: Offset(0, 3),
                                                  ),
                                                ],
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  const Icon(
                                                    Icons
                                                        .local_fire_department_rounded,
                                                    color: Colors.white,
                                                    size: 20,
                                                  ),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    '${game.comboCount}x COMBO!',
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontWeight:
                                                          FontWeight.w900,
                                                      fontSize: 14,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
                  // Every persistent layer lives in one column: top chrome,
                  // one upper contextual element, the world's breathing room,
                  // one lower contextual element, then bottom chrome. A column
                  // cannot overlap itself, so the ordering is the guarantee —
                  // no offsets to keep in sync as content changes.
                  Positioned.fill(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        // Short viewports drop the optional layers rather than
                        // letting them collide. Less UI beats overlapping UI.
                        final height = constraints.maxHeight;
                        final showActions = height >= 560;
                        final showMission = height >= 460;
                        return Column(
                          children: [
                            ?widget.topChrome,
                            if (showMission)
                              Padding(
                                padding: const EdgeInsetsDirectional.fromSTEB(
                                  10,
                                  8,
                                  10,
                                  0,
                                ),
                                child: AnimatedBuilder(
                                  animation: game,
                                  builder: (context, _) =>
                                      game.fastCheckoutActive
                                      ? _FastCheckoutBanner(
                                          claimed: game.fastCheckoutClaimed,
                                          onClaim: () {
                                            if (game
                                                .claimFastCheckoutBonus()) {
                                              ScaffoldMessenger.of(
                                                context,
                                              ).showSnackBar(
                                                SnackBar(
                                                  content: Text(
                                                    AppLocalizations.of(
                                                      context,
                                                    ).fastCheckoutBonus,
                                                  ),
                                                ),
                                              );
                                            }
                                          },
                                        )
                                      : Align(
                                          alignment:
                                              AlignmentDirectional.centerStart,
                                          child: _MissionPod(
                                      key: const ValueKey('objective-strip'),
                                      quest: game.quest,
                                      title: AppLocalizations.of(
                                        context,
                                      ).questTitle(
                                        game.questStage,
                                        game.quest.target,
                                      ),
                                      onClaim: _claimQuest,
                                      reducedMotion:
                                          settings.reducedMotion ||
                                          MediaQuery.disableAnimationsOf(
                                            context,
                                          ),
                                    ),
                                  ),
                                ),
                              ),
                            // Transient, but still in the column so it can
                            // never land on the pod above or the world below.
                            AnimatedSize(
                              duration: const Duration(milliseconds: 220),
                              curve: Curves.easeOutCubic,
                              child: _achievementToast == null
                                  ? const SizedBox(width: double.infinity)
                                  : Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        12,
                                        8,
                                        12,
                                        0,
                                      ),
                                      child: _AchievementToast(
                                        achievement: _achievementToast!,
                                        title: AppLocalizations.of(
                                          context,
                                        ).achievementTitle(
                                          _achievementToast!.id,
                                        ),
                                        description: AppLocalizations.of(
                                          context,
                                        ).achievementDescription(
                                          _achievementToast!.id,
                                        ),
                                      ),
                                    ),
                            ),
                            // The world's share of the screen. Nothing is
                            // painted here, so taps fall through to the board.
                            const Expanded(child: SizedBox.expand()),
                            if (showActions)
                              Padding(
                                padding: const EdgeInsetsDirectional.fromSTEB(
                                  10,
                                  0,
                                  10,
                                  8,
                                ),
                                child: _WorldContextActions(
                                  game: game,
                                  onOpenStaff: widget.onOpenStaff,
                                  onOpenInventory: widget.onOpenInventory,
                                  onOpenDepartments: widget.onOpenDepartments,
                                ),
                              ),
                            ?widget.bottomChrome,
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
        ),
      ),
    );
  }

  Future<void> _claimAdReward() async {
    await _claimRewardPlacement(RewardPlacement.instantCoins);
  }

  Future<bool> _claimRewardPlacement(RewardPlacement placement) async {
    unawaited(SfxManager.instance.click());
    final reward = placement == RewardPlacement.doubleOfflineEarnings
        ? game.offlineEarnings * 2
        : game.instantAdReward;
    final completed = switch (placement) {
      RewardPlacement.instantCoins => await game.claimInstantAdReward(),
      RewardPlacement.doubleOfflineEarnings => await game.claimOfflineReward(
        doubled: true,
      ),
      _ => false,
    };
    if (!mounted || !completed) {
      if (mounted) {
        unawaited(SfxManager.instance.error());
      }
      return false;
    }
    unawaited(SfxManager.instance.success());
    final loc = AppLocalizations.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(loc.coinsEarned.replaceFirst('{value}', '$reward')),
        behavior: SnackBarBehavior.floating,
      ),
    );
    return true;
  }

  // Retained for compatibility with legacy deep links.
  // ignore: unused_element
  // Retained for compatibility with legacy deep links.
  // ignore: unused_element
  // Retained for compatibility with legacy deep links.
  // ignore: unused_element
  // Retained for compatibility with legacy deep links.
  // ignore: unused_element
  // Retained for compatibility with legacy deep links.
  // ignore: unused_element
  // Retained for compatibility with legacy deep links.
  // ignore: unused_element
  // Retained for compatibility with legacy deep links.
  // ignore: unused_element
  // Retained for compatibility with legacy deep links.
  // ignore: unused_element
  // Retained for compatibility with legacy deep links.
  // ignore: unused_element
  // Retained for compatibility with legacy deep links.
  // ignore: unused_element
  // Retained for compatibility with legacy deep links.
  // ignore: unused_element
  // Retained for compatibility with legacy deep links.
  // ignore: unused_element
  // Retained for compatibility with legacy deep links.
  // ignore: unused_element
  // Retained for compatibility with legacy deep links.
  // ignore: unused_element
  // Retained for compatibility with legacy deep links.
  // ignore: unused_element
  // Retained for compatibility with legacy deep links.
  // ignore: unused_element
  // Retained for compatibility with legacy deep links.
  // ignore: unused_element
  // Retained for compatibility with legacy deep links.
  // ignore: unused_element
  // Retained for compatibility with legacy deep links.
  // ignore: unused_element
  // Retained for compatibility with legacy deep links.
  // ignore: unused_element
  // Retained for compatibility with legacy deep links.
  // ignore: unused_element
  // Retained for compatibility with legacy deep links.
  // ignore: unused_element
  Future<void> _showRewardCenter() {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => FractionallySizedBox(
        heightFactor: 0.88,
        child: _RewardCenter(game: game, onReward: _claimRewardPlacement),
      ),
    );
  }

  // Retained for compatibility with legacy deep links.
  // ignore: unused_element
  // Retained for compatibility with legacy deep links.
  // ignore: unused_element
  // Retained for compatibility with legacy deep links.
  // ignore: unused_element
  // Retained for compatibility with legacy deep links.
  // ignore: unused_element
  // Retained for compatibility with legacy deep links.
  // ignore: unused_element
  // Retained for compatibility with legacy deep links.
  // ignore: unused_element
  // Retained for compatibility with legacy deep links.
  // ignore: unused_element
  // Retained for compatibility with legacy deep links.
  // ignore: unused_element
  // Retained for compatibility with legacy deep links.
  // ignore: unused_element
  // Retained for compatibility with legacy deep links.
  // ignore: unused_element
  // Retained for compatibility with legacy deep links.
  // ignore: unused_element
  // Retained for compatibility with legacy deep links.
  // ignore: unused_element
  // Retained for compatibility with legacy deep links.
  // ignore: unused_element
  // Retained for compatibility with legacy deep links.
  // ignore: unused_element
  // Retained for compatibility with legacy deep links.
  // ignore: unused_element
  // Retained for compatibility with legacy deep links.
  // ignore: unused_element
  // Retained for compatibility with legacy deep links.
  // ignore: unused_element
  // Retained for compatibility with legacy deep links.
  // ignore: unused_element
  // Retained for compatibility with legacy deep links.
  // ignore: unused_element
  // Retained for compatibility with legacy deep links.
  // ignore: unused_element
  // Retained for compatibility with legacy deep links.
  // ignore: unused_element
  // Retained for compatibility with legacy deep links.
  // ignore: unused_element
  Future<void> _showUpgrades() {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _UpgradeSheet(
        game: game,
        onPurchased: () => unawaited(SfxManager.instance.success()),
        onInsufficientCoins: () {
          unawaited(SfxManager.instance.error());
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context).notEnoughCoins),
              behavior: SnackBarBehavior.floating,
            ),
          );
        },
      ),
    );
  }

  // Retained for compatibility with legacy deep links.
  // ignore: unused_element
  // Retained for compatibility with legacy deep links.
  // ignore: unused_element
  // Retained for compatibility with legacy deep links.
  // ignore: unused_element
  // Retained for compatibility with legacy deep links.
  // ignore: unused_element
  // Retained for compatibility with legacy deep links.
  // ignore: unused_element
  // Retained for compatibility with legacy deep links.
  // ignore: unused_element
  // Retained for compatibility with legacy deep links.
  // ignore: unused_element
  // Retained for compatibility with legacy deep links.
  // ignore: unused_element
  // Retained for compatibility with legacy deep links.
  // ignore: unused_element
  // Retained for compatibility with legacy deep links.
  // ignore: unused_element
  // Retained for compatibility with legacy deep links.
  // ignore: unused_element
  // Retained for compatibility with legacy deep links.
  // ignore: unused_element
  // Retained for compatibility with legacy deep links.
  // ignore: unused_element
  // Retained for compatibility with legacy deep links.
  // ignore: unused_element
  // Retained for compatibility with legacy deep links.
  // ignore: unused_element
  // Retained for compatibility with legacy deep links.
  // ignore: unused_element
  // Retained for compatibility with legacy deep links.
  // ignore: unused_element
  // Retained for compatibility with legacy deep links.
  // ignore: unused_element
  // Retained for compatibility with legacy deep links.
  // ignore: unused_element
  // Retained for compatibility with legacy deep links.
  // ignore: unused_element
  // Retained for compatibility with legacy deep links.
  // ignore: unused_element
  // Retained for compatibility with legacy deep links.
  // ignore: unused_element
  Future<void> _showMoneyShop() {
    unawaited(SfxManager.instance.click());
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _MoneyShopSheet(
        game: game,
        onReward: () async {
          Navigator.of(sheetContext).pop();
          await _claimAdReward();
        },
        onPurchase: (product) async {
          final purchased = await game.purchaseStoreProduct(product);
          if (!mounted) {
            return;
          }
          unawaited(
            purchased
                ? SfxManager.instance.success()
                : SfxManager.instance.error(),
          );
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                purchased
                    ? AppLocalizations.of(context).purchaseComplete
                    : game.lastPurchaseState == PurchaseState.cancelled
                    ? AppLocalizations.of(context).purchaseCancelled
                    : AppLocalizations.of(context).purchaseFailed,
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
        },
      ),
    );
  }

  Future<void> _showOfflineEarnings() {
    return showModalBottomSheet<void>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _OfflineEarningsSheet(
        game: game,
        onCollect: (doubled) async {
          final collected = await game.claimOfflineReward(doubled: doubled);
          if (sheetContext.mounted && collected) {
            unawaited(SfxManager.instance.success());
            Navigator.of(sheetContext).pop();
          }
        },
      ),
    );
  }

  Future<void> _showDailyBonus(DailyBonusResult bonus) async {
    final loc = AppLocalizations.of(context);
    _celebration.celebrate();
    unawaited(
      bonus.isMilestone
          ? SfxManager.instance.milestone()
          : SfxManager.instance.success(),
    );
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 22),
        backgroundColor: Colors.transparent,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Container(
            padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFFFF),
              borderRadius: BorderRadius.circular(28),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x440B3B2C),
                  blurRadius: 28,
                  offset: Offset(0, 13),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 92,
                  height: 92,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFFD874), Color(0xFFD98505)],
                    ),
                    shape: BoxShape.circle,
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x44FFCB45),
                        blurRadius: 22,
                        offset: Offset(0, 10),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.local_fire_department_rounded,
                    size: 53,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 15),
                Text(
                  loc.dailyBonus,
                  style: const TextStyle(
                    color: Color(0xFFD98505),
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                  ),
                ),
                Text(
                  loc.dayStreak.replaceFirst('{streak}', '${bonus.streak}'),
                  style: const TextStyle(
                    color: Color(0xFF1C3A32),
                    fontSize: 27,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  loc.comeBackTomorrow,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFF4A6E63)),
                ),
                const SizedBox(height: 17),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _BonusPill(
                      icon: Icons.monetization_on_rounded,
                      value: '+${bonus.coinsAwarded}',
                      color: const Color(0xFFFFCB45),
                    ),
                    if (bonus.gemsAwarded > 0) ...[
                      const SizedBox(width: 9),
                      _BonusPill(
                        icon: Icons.diamond_rounded,
                        value: '+${bonus.gemsAwarded}',
                        color: const Color(0xFF6234E0),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 19),
                FilledButton.icon(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    backgroundColor: const Color(0xFF2FD98F),
                  ),
                  icon: const Icon(Icons.card_giftcard_rounded),
                  label: Text(loc.collectReward),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    game.acknowledgeDailyBonus();
  }
}

class _RewardCenter extends StatelessWidget {
  const _RewardCenter({required this.game, required this.onReward});

  final GameController game;
  final Future<bool> Function(RewardPlacement placement) onReward;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return Material(
      color: const Color(0xFFFFFFFF),
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: AnimatedBuilder(
        animation: game,
        builder: (context, _) {
          final choices = <_RewardChoice>[
            _RewardChoice(
              placement: RewardPlacement.instantCoins,
              icon: Icons.monetization_on_rounded,
              color: const Color(0xFFFFCB45),
              title: loc.rewardCoinsTitle,
              benefit: loc.rewardCoinsBenefit.replaceFirst(
                '{value}',
                '${game.instantAdReward}',
              ),
            ),
            if (game.offlineEarnings > 0)
              _RewardChoice(
                placement: RewardPlacement.doubleOfflineEarnings,
                icon: Icons.bolt_rounded,
                color: const Color(0xFF2FD98F),
                title: loc.rewardOfflineTitle,
                benefit: loc.rewardOfflineBenefit
                    .replaceFirst('{value}', '${game.offlineEarnings * 2}')
                    .replaceFirst('{base}', '${game.offlineEarnings}'),
              ),
          ];
          return Column(
            children: [
              const _SheetHandle(),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
                child: Row(
                  children: [
                    const Icon(
                      Icons.ondemand_video_rounded,
                      color: Color(0xFF1C3A32),
                      size: 25,
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        loc.rewardCenterTitle,
                        style: const TextStyle(
                          color: Color(0xFF1C3A32),
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      tooltip: MaterialLocalizations.of(
                        context,
                      ).closeButtonTooltip,
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(13),
                      decoration: BoxDecoration(
                        color: const Color(0x140B3B2C),
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Text(
                        loc.optionalAdDescription,
                        style: const TextStyle(
                          color: Color(0xFF1C3A32),
                          fontSize: 12,
                          height: 1.35,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 9),
                    if (game.isMonetizationPreview)
                      _RewardPreviewNotice(loc: loc),
                    if (game.isMonetizationPreview) const SizedBox(height: 9),
                    Text(
                      '${loc.rewardClaimsToday}: ${game.rewardClaimsToday}/${game.rewardDailyLimit}',
                      style: const TextStyle(
                        color: Color(0xFF4A6E63),
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (final choice in choices) ...[
                      _RewardChoiceCard(
                        choice: choice,
                        game: game,
                        loc: loc,
                        onReward: onReward,
                      ),
                      const SizedBox(height: 10),
                    ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _RewardChoice {
  const _RewardChoice({
    required this.placement,
    required this.icon,
    required this.color,
    required this.title,
    required this.benefit,
  });

  final RewardPlacement placement;
  final IconData icon;
  final Color color;
  final String title;
  final String benefit;
}

class _RewardChoiceCard extends StatelessWidget {
  const _RewardChoiceCard({
    required this.choice,
    required this.game,
    required this.loc,
    required this.onReward,
  });

  final _RewardChoice choice;
  final GameController game;
  final AppLocalizations loc;
  final Future<bool> Function(RewardPlacement placement) onReward;

  @override
  Widget build(BuildContext context) {
    final cooldown = game.rewardCooldownRemaining(choice.placement);
    final available =
        game.rewardedAdsAvailable &&
        !game.rewardInProgress &&
        game.canClaimReward(choice.placement);
    final status = game.isMonetizationPreview
        ? loc.rewardUnavailable
        : game.rewardInProgress
        ? loc.loading
        : cooldown > Duration.zero
        ? loc.rewardCooldown.replaceFirst(
            '{time}',
            _formatRewardDuration(cooldown),
          )
        : game.rewardClaimsToday >= game.rewardDailyLimit
        ? loc.dailyLimitReached
        : loc.watchAndReceive;
    return Semantics(
      container: true,
      label: '${choice.title}. ${choice.benefit}. $status',
      child: Card(
        margin: EdgeInsets.zero,
        color: choice.color.withValues(alpha: 0.08),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(17),
          side: BorderSide(color: choice.color.withValues(alpha: 0.24)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(13),
          child: Row(
            children: [
              CircleAvatar(
                radius: 21,
                backgroundColor: choice.color,
                child: Icon(choice.icon, color: Colors.white, size: 21),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      choice.title,
                      style: const TextStyle(
                        color: Color(0xFF1C3A32),
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      choice.benefit,
                      style: const TextStyle(
                        color: Color(0xFF4A6E63),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      status,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: available
                            ? const Color(0xFF0A8B59)
                            : const Color(0xFF7D998F),
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: available
                    ? () async {
                        await onReward(choice.placement);
                      }
                    : null,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 42),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  backgroundColor: const Color(0xFF1C3A32),
                ),
                child: Text(
                  available ? loc.watchAndReceive : loc.rewardUnavailable,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 11),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RewardPreviewNotice extends StatelessWidget {
  const _RewardPreviewNotice({required this.loc});

  final AppLocalizations loc;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF6E3),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: const Color(0x33D98505)),
      ),
      child: Row(
        children: [
          const Icon(Icons.phone_android_rounded, color: Color(0xFFD98505)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${loc.mobileFeaturePreview}: ${loc.rewardPreviewUnavailable}',
              style: const TextStyle(
                color: Color(0xFF7A4E06),
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _formatRewardDuration(Duration duration) {
  final totalSeconds = duration.inSeconds.clamp(0, 599999);
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

class _FastCheckoutBanner extends StatelessWidget {
  const _FastCheckoutBanner({required this.claimed, required this.onClaim});

  final bool claimed;
  final VoidCallback onClaim;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return Card(
      margin: EdgeInsets.zero,
      color: const Color(0xFFFFF6E3),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            const Icon(Icons.bolt_rounded, color: Color(0xFFD98505)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${loc.fastCheckout} · ${loc.fastCheckoutBonus}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            TextButton(
              onPressed: claimed ? null : onClaim,
              child: Text(claimed ? loc.claimed : loc.claimBonus),
            ),
          ],
        ),
      ),
    );
  }
}

class _CurrencyPill extends StatelessWidget {
  const _CurrencyPill({
    required this.icon,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17, color: color),
          const SizedBox(width: 4),
          Text('$value', style: const TextStyle(fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}

/// Collapsible objective pod anchored over the world.
///
/// Replaces the full-width objective strip that used to sit above the board.
/// Collapsed it is a compact badge with a ring showing progress; tapping it
/// expands the detail — progressive disclosure, so the objective is always
/// visible but only occupies the screen when the player asks for it.
class _MissionPod extends StatefulWidget {
  const _MissionPod({
    super.key,
    required this.quest,
    required this.title,
    required this.onClaim,
    required this.reducedMotion,
  });

  final Quest quest;
  final String title;
  final VoidCallback onClaim;
  final bool reducedMotion;

  @override
  State<_MissionPod> createState() => _MissionPodState();
}

class _MissionPodState extends State<_MissionPod> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final quest = widget.quest;
    final ratio = quest.target == 0
        ? 0.0
        : (quest.progress / quest.target).clamp(0.0, 1.0);
    final ready = quest.completed;
    final face = ready ? PoColor.goldFace : PoColor.primaryFace;
    final duration = widget.reducedMotion
        ? Duration.zero
        : const Duration(milliseconds: 260);

    return AnimatedSize(
      duration: duration,
      curve: PoMotion.curve,
      alignment: AlignmentDirectional.topStart,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: _open
              ? (MediaQuery.sizeOf(context).width - 96).clamp(200.0, 320.0)
              : 232,
        ),
        child: PoPressable(
          onTap: () => setState(() => _open = !_open),
          radius: PoRadius.lg,
          semanticLabel: widget.title,
          child: Container(
            padding: const EdgeInsetsDirectional.fromSTEB(8, 8, 12, 8),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: AlignmentDirectional.topStart,
                end: AlignmentDirectional.bottomEnd,
                colors: [Color(0xF217402F), Color(0xF20D2A21)],
              ),
              borderRadius: BorderRadius.circular(PoRadius.lg),
              border: Border.all(
                color: Colors.white.withValues(alpha: ready ? 0.34 : 0.16),
                width: 1.4,
              ),
              boxShadow: [
                BoxShadow(
                  color: PoColor.chromeDeep.withValues(alpha: 0.5),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
                if (ready) ...PoElevate.glow(PoColor.goldFace, strength: 0.7),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _MissionRing(ratio: ratio, face: face, ready: ready),
                    const SizedBox(width: 9),
                    Flexible(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            AppLocalizations.of(context).quests.toUpperCase(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: PoText.overline.copyWith(
                              color: PoColor.lighten(face, 0.24),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.title,
                            maxLines: _open ? 3 : 1,
                            overflow: TextOverflow.ellipsis,
                            style: PoText.title.copyWith(
                              color: PoColor.onChrome,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      _open
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      size: 18,
                      color: PoColor.onChromeMuted,
                    ),
                  ],
                ),
                if (_open) ...[
                  const SizedBox(height: 10),
                  PoGauge(
                    value: ratio,
                    face: face,
                    height: 11,
                    segments: quest.target.clamp(2, 12),
                    onChrome: true,
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(
                        Icons.card_giftcard_rounded,
                        size: 15,
                        color: PoColor.goldFace,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '+${quest.reward} ${AppLocalizations.of(context).coinsShort}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: PoText.caption.copyWith(
                            color: PoColor.onChromeMuted,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (ready) ...[
                    const SizedBox(height: 10),
                    PoBtn(
                      key: const ValueKey('mission-claim-action'),
                      onPressed: widget.onClaim,
                      expand: true,
                      dense: true,
                      face: PoColor.goldFace,
                      icon: Icons.card_giftcard_rounded,
                      label: AppLocalizations.of(context).claimReward,
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Progress ring plus count, used as the mission pod's collapsed state.
class _MissionRing extends StatelessWidget {
  const _MissionRing({
    required this.ratio,
    required this.face,
    required this.ready,
  });

  final double ratio;
  final Color face;
  final bool ready;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 34,
    height: 34,
    child: CustomPaint(
      painter: _MissionRingPainter(ratio: ratio, face: face),
      child: Center(
        child: Icon(
          ready ? Icons.card_giftcard_rounded : Icons.flag_rounded,
          size: 15,
          color: ready ? PoColor.goldFace : PoColor.onChrome,
        ),
      ),
    ),
  );
}

class _MissionRingPainter extends CustomPainter {
  const _MissionRingPainter({required this.ratio, required this.face});

  final double ratio;
  final Color face;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    final stroke = size.shortestSide * 0.14;
    final radius = (size.shortestSide - stroke) / 2;
    canvas.drawCircle(
      centre,
      radius,
      Paint()..color = Colors.white.withValues(alpha: 0.08),
    );
    canvas.drawCircle(
      centre,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = Colors.black.withValues(alpha: 0.35),
    );
    if (ratio <= 0) return;
    canvas.drawArc(
      Rect.fromCircle(center: centre, radius: radius),
      -math.pi / 2,
      math.pi * 2 * ratio,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = face,
    );
  }

  @override
  bool shouldRepaint(covariant _MissionRingPainter old) =>
      old.ratio != ratio || old.face != face;
}

class _WorldContextActions extends StatelessWidget {
  const _WorldContextActions({
    required this.game,
    required this.onOpenStaff,
    required this.onOpenInventory,
    required this.onOpenDepartments,
  });

  final GameController game;
  final VoidCallback? onOpenStaff;
  final VoidCallback? onOpenInventory;
  final VoidCallback? onOpenDepartments;

  @override
  Widget build(BuildContext context) {
    final contextType = _contextFor(game);
    if (contextType == null || game.pendingShiftSummary != null) {
      return const SizedBox.shrink();
    }
    final labels = _contextLabels(context);
    final actions = switch (contextType) {
      _WorldActionContext.shelf => <_WorldAction>[
        _WorldAction(
          label: labels.stock,
          icon: Icons.inventory_2_rounded,
          onPressed: onOpenInventory,
        ),
        _WorldAction(
          label: labels.inspect,
          icon: Icons.search_rounded,
          onPressed: onOpenDepartments,
        ),
      ],
      _WorldActionContext.checkout => <_WorldAction>[
        _WorldAction(
          label: labels.checkout,
          icon: Icons.point_of_sale_rounded,
          onPressed: () {
            game.clearMovementTarget();
            _showContextHint(context, game.interactionHint);
          },
        ),
        _WorldAction(
          label: labels.queue,
          icon: Icons.groups_rounded,
          onPressed: onOpenStaff,
        ),
      ],
      _WorldActionContext.bakery => <_WorldAction>[
        _WorldAction(
          label: labels.bakery,
          icon: Icons.bakery_dining_rounded,
          onPressed: onOpenDepartments,
        ),
        _WorldAction(
          label: labels.stock,
          icon: Icons.inventory_2_rounded,
          onPressed: onOpenInventory,
        ),
      ],
      _WorldActionContext.storage => <_WorldAction>[
        _WorldAction(
          label: labels.storage,
          icon: Icons.warehouse_rounded,
          onPressed: onOpenInventory,
        ),
        _WorldAction(
          label: labels.restock,
          icon: Icons.local_shipping_rounded,
          onPressed: () {
            final ordered = game.placeQuickRestock() != null;
            _showContextHint(
              context,
              ordered ? labels.restockOrdered : game.interactionHint,
            );
          },
        ),
      ],
    };
    // These are the primary in-world calls to action, so they get the full
    // extruded treatment rather than flat text on a shared slab.
    return Center(
      child: Row(
        key: const ValueKey('world-context-actions'),
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var index = 0; index < actions.length; index++) ...[
            if (index > 0) const SizedBox(width: 8),
            _WorldContextButton(action: actions[index], primary: index == 0),
          ],
        ],
      ),
    );
  }

  _WorldActionContext? _contextFor(GameController game) {
    final position = game.playerPosition;
    if ((position - GameController.stockZone).distance <= .17) {
      return _WorldActionContext.storage;
    }
    if ((position - GameController.bakeryZone).distance <= .17) {
      return _WorldActionContext.bakery;
    }
    if (game.checkoutStations.any(
      (station) =>
          station.unlocked &&
          (position - game.checkoutStationZone(station.id)).distance <= .17,
    )) {
      return _WorldActionContext.checkout;
    }
    if ((position - GameController.shelfZone).distance <= .24) {
      return _WorldActionContext.shelf;
    }
    return null;
  }
}

enum _WorldActionContext { shelf, checkout, bakery, storage }

class _WorldAction {
  const _WorldAction({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
}

class _WorldContextButton extends StatelessWidget {
  const _WorldContextButton({required this.action, this.primary = false});

  final _WorldAction action;

  /// The leading action in a context group reads as the main move and gets the
  /// bright face; the rest stay in the darker supporting tone.
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return PoButton(
      onPressed: action.onPressed,
      semanticLabel: action.label,
      face: primary ? PoAccent.mintFace : PoDepthColors.canopy,
      radius: 15,
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(action.icon, size: 17),
          const SizedBox(width: 6),
          Text(action.label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}

({
  String stock,
  String inspect,
  String checkout,
  String queue,
  String bakery,
  String storage,
  String restock,
  String restockOrdered,
})
_contextLabels(BuildContext context) {
  return switch (Localizations.localeOf(context).languageCode) {
    'he' => (
      stock: 'מלאי',
      inspect: 'בדיקה',
      checkout: 'קופה',
      queue: 'תור',
      bakery: 'מאפייה',
      storage: 'מחסן',
      restock: 'הזמנה',
      restockOrdered: 'המלאי הוזמן',
    ),
    'ar' => (
      stock: 'المخزون',
      inspect: 'فحص',
      checkout: 'الدفع',
      queue: 'الطابور',
      bakery: 'المخبز',
      storage: 'المخزن',
      restock: 'إعادة الطلب',
      restockOrdered: 'تم طلب المخزون',
    ),
    _ => (
      stock: 'Stock',
      inspect: 'Inspect',
      checkout: 'Checkout',
      queue: 'Queue',
      bakery: 'Bakery',
      storage: 'Storage',
      restock: 'Restock',
      restockOrdered: 'Stock ordered',
    ),
  };
}

void _showContextHint(BuildContext context, String message) {
  if (message.trim().isEmpty) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(milliseconds: 1300),
    ),
  );
}

// Legacy implementation retained temporarily; it is no longer mounted.
// ignore: unused_element
// Legacy implementation retained temporarily; it is no longer mounted.
// ignore: unused_element
// Legacy implementation retained temporarily; it is no longer mounted.
// ignore: unused_element
// Legacy implementation retained temporarily; it is no longer mounted.
// ignore: unused_element
// Legacy implementation retained temporarily; it is no longer mounted.
// ignore: unused_element
// Legacy implementation retained temporarily; it is no longer mounted.
// ignore: unused_element
// Legacy implementation retained temporarily; it is no longer mounted.
// ignore: unused_element
// Legacy implementation retained temporarily; it is no longer mounted.
// ignore: unused_element
// Legacy implementation retained temporarily; it is no longer mounted.
// ignore: unused_element
// Legacy implementation retained temporarily; it is no longer mounted.
// ignore: unused_element
// Legacy implementation retained temporarily; it is no longer mounted.
// ignore: unused_element
// Legacy implementation retained temporarily; it is no longer mounted.
// ignore: unused_element
// Legacy implementation retained temporarily; it is no longer mounted.
// ignore: unused_element
// Legacy implementation retained temporarily; it is no longer mounted.
// ignore: unused_element
// Legacy implementation retained temporarily; it is no longer mounted.
// ignore: unused_element
// Legacy implementation retained temporarily; it is no longer mounted.
// ignore: unused_element
// Legacy implementation retained temporarily; it is no longer mounted.
// ignore: unused_element
// Legacy implementation retained temporarily; it is no longer mounted.
// ignore: unused_element
// Legacy implementation retained temporarily; it is no longer mounted.
// ignore: unused_element
// Legacy implementation retained temporarily; it is no longer mounted.
// ignore: unused_element
// Legacy implementation retained temporarily; it is no longer mounted.
// ignore: unused_element
// Legacy implementation retained temporarily; it is no longer mounted.
// ignore: unused_element
class _ControlDeck extends StatelessWidget {
  const _ControlDeck({
    required this.game,
    required this.settings,
    required this.onUpgrades,
    required this.onReward,
    required this.onShop,
  });

  final GameController game;
  final AppSettings settings;
  final VoidCallback onUpgrades;
  final VoidCallback onReward;
  final VoidCallback onShop;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final showQuickStock = game.inventoryFor('General') == 0;
    return Container(
      key: const ValueKey('bottom-action-dock'),
      margin: const EdgeInsets.fromLTRB(8, 4, 8, 6),
      padding: const EdgeInsets.fromLTRB(8, 5, 8, 5),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0x300B3B2C)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x170B3B2C),
            blurRadius: 10,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 600;
          final actionHeight = narrow ? 54.0 : 46.0;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 18,
                child: Row(
                  children: [
                    Expanded(
                      child: _ControlInstruction(
                        settings: settings,
                        interactionHint: _localizedInteractionHint(loc, game),
                      ),
                    ),
                    const SizedBox(width: 6),
                    _CarriedStatusChip(
                      carried: game.carried,
                      capacity: game.bagCapacity,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              if (showQuickStock) ...[
                _QuickStockAction(game: game, loc: loc),
                const SizedBox(height: 4),
              ],
              SizedBox(
                height: actionHeight,
                child: Row(
                  children: [
                    Flexible(
                      child: SizedBox(
                        key: const ValueKey('quick-upgrades-action'),
                        height: actionHeight,
                        child: _RoundAction(
                          label: loc.upgrades,
                          icon: Icons.upgrade_rounded,
                          color: const Color(0xFF1C3A32),
                          onTap: onUpgrades,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: SizedBox(
                        key: const ValueKey('quick-reward-action'),
                        height: actionHeight,
                        child: _RoundAction(
                          label: game.rewardInProgress
                              ? loc.loading
                              : loc.freeBonus,
                          icon: Icons.ondemand_video_rounded,
                          color: const Color(0xFFD32A47),
                          onTap: game.rewardInProgress ? null : onReward,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: SizedBox(
                        key: const ValueKey('quick-shop-action'),
                        height: actionHeight,
                        child: _RoundAction(
                          label: loc.shop,
                          icon: Icons.shopping_bag_rounded,
                          color: const Color(0xFFB06A04),
                          onTap: onShop,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

String _localizedInteractionHint(AppLocalizations loc, GameController game) {
  if ((game.playerPosition - GameController.bakeryZone).distance <= 0.13) {
    if (!game.bakeryUnlocked) {
      return loc.bakeryLockedHint.replaceFirst(
        '{level}',
        '${GameBalance.bakeryUnlockLevel}',
      );
    }
    if (game.carried >= game.bagCapacity) {
      return loc.bakeryBagFullHint;
    }
    return game.bakeryReadyStock > 0
        ? loc.bakeryCollectingHint
        : loc.bakeryBakingHint;
  }
  if ((game.playerPosition - GameController.stockZone).distance <= 0.13) {
    if (game.inventoryFor('General') <= 0) {
      return loc.storageEmptyHint;
    }
    return game.carried >= game.bagCapacity
        ? loc.bagFullHint
        : loc.collectingStorageHint;
  }
  if ((game.playerPosition - GameController.shelfZone).distance <= 0.14) {
    if (game.carried == 0) {
      return loc.bagEmptyHint;
    }
    if (game.shelfStock >= game.shelfCapacity) {
      return loc.shelfFullHint;
    }
    return loc.stockingShelfHint;
  }
  if ((game.playerPosition - GameController.checkoutZone).distance <= 0.13) {
    return loc.checkoutHint;
  }
  return '';
}

class _QuickStockAction extends StatelessWidget {
  const _QuickStockAction({required this.game, required this.loc});

  final GameController game;
  final AppLocalizations loc;

  @override
  Widget build(BuildContext context) {
    final pending = game.hasPendingGeneralDelivery;
    final emergency = game.canClaimEmergencyStock;
    final enabled = !pending && (emergency || game.canQuickRestock);
    final label = pending
        ? loc.quickRestockPending
        : emergency
        ? '${loc.emergencyStock} +${GameBalance.emergencyStockQuantity}'
        : loc.quickRestock;
    final actionKey = pending
        ? const ValueKey('quick-restock-action-pending')
        : const ValueKey('quick-restock-action');
    final color = emergency ? const Color(0xFF2FD98F) : const Color(0xFFFFCB45);

    void activate() {
      final succeeded = emergency
          ? game.claimEmergencyStock()
          : game.placeQuickRestock() != null;
      unawaited(
        succeeded ? SfxManager.instance.success() : SfxManager.instance.error(),
      );
      if (!succeeded) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            emergency ? loc.emergencyStock : loc.quickRestockOrdered,
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }

    final icon = pending
        ? Icons.local_shipping_rounded
        : emergency
        ? Icons.inventory_2_rounded
        : Icons.add_shopping_cart_rounded;
    return SizedBox(
      key: actionKey,
      width: double.infinity,
      height: 28,
      child: FilledButton.icon(
        onPressed: enabled ? activate : null,
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          backgroundColor: color,
          disabledBackgroundColor: color.withValues(alpha: 0.42),
          textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
        ),
        icon: Icon(icon, size: 15),
        label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    );
  }
}

class _CarriedStatusChip extends StatelessWidget {
  const _CarriedStatusChip({required this.carried, required this.capacity});

  final int carried;
  final int capacity;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0x140B3B2C),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.inventory_2_rounded,
            size: 13,
            color: Color(0xFFD98505),
          ),
          const SizedBox(width: 3),
          Text(
            '$carried/$capacity',
            textDirection: TextDirection.ltr,
            style: const TextStyle(
              color: Color(0xFF1C3A32),
              fontSize: 10,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _ControlInstruction extends StatelessWidget {
  const _ControlInstruction({
    required this.settings,
    required this.interactionHint,
  });

  final AppSettings settings;
  final String interactionHint;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final text = switch (settings.controlMode) {
      ControlMode.directTouch => loc.directTouchInstruction,
      ControlMode.joystick => loc.floatingJoystickInstruction,
      ControlMode.leftJoystick => loc.leftHandedJoystickInstruction,
    };
    final displayText = interactionHint.isNotEmpty ? interactionHint : text;
    return KeyedSubtree(
      key: const ValueKey('movement-hint'),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        child: Text(
          displayText,
          key: ValueKey('$displayText-${settings.controlMode}'),
          semanticsLabel: text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.start,
          style: const TextStyle(
            color: Color(0xFF1C3A32),
            fontSize: 10,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _RoundAction extends StatelessWidget {
  const _RoundAction({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: label,
      child: PressableScale(
        enabled: onTap != null,
        child: SizedBox.expand(
          child: Material(
            color: onTap == null ? color.withValues(alpha: 0.35) : color,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: onTap == null
                  ? null
                  : () {
                      unawaited(SfxManager.instance.click());
                      onTap!();
                    },
              borderRadius: BorderRadius.circular(12),
              child: Align(
                alignment: Alignment.center,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 7),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(icon, color: Colors.white, size: 16),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _UpgradeSheet extends StatelessWidget {
  const _UpgradeSheet({
    required this.game,
    required this.onPurchased,
    required this.onInsufficientCoins,
  });

  final GameController game;
  final VoidCallback onPurchased;
  final VoidCallback onInsufficientCoins;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: AnimatedBuilder(
        animation: game,
        builder: (context, _) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _SheetHandle(),
            Row(
              children: [
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    AppLocalizations.of(context).upgrades,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF1C3A32),
                    ),
                  ),
                ),
                _CurrencyPill(
                  icon: Icons.monetization_on_rounded,
                  value: game.coins,
                  color: const Color(0xFFFFCB45),
                ),
                const SizedBox(width: 16),
              ],
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                itemCount: game.upgrades.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final upgrade = game.upgrades[index];
                  final canAfford = game.canBuyUpgrade(upgrade.type);
                  final isMaxed = upgrade.level >= 10;
                  return _UpgradeTile(
                    upgrade: upgrade,
                    canAfford: canAfford,
                    isMaxed: isMaxed,
                    onTap: isMaxed
                        ? null
                        : () {
                            if (!canAfford) {
                              onInsufficientCoins();
                              return;
                            }
                            game.buyUpgrade(upgrade.type);
                            onPurchased();
                          },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _upgradeEffectLabel(AppLocalizations loc, UpgradeOffer offer) {
  return switch (offer.type) {
    UpgradeType.bag => loc.carryProducts.replaceFirst(
      '{capacity}',
      '${3 + offer.level}',
    ),
    UpgradeType.shelf => '${loc.capacity}: ${4 + offer.level * 2}',
    UpgradeType.price => loc.profitPerSale.replaceFirst(
      '{value}',
      '${4 + offer.level * 2}',
    ),
    UpgradeType.speed => loc.movementSpeed.replaceFirst(
      '{value}',
      '${offer.level * 8}',
    ),
    UpgradeType.checkout => loc.serviceTime.replaceFirst(
      '{value}',
      offer.subtitle.split('s').first,
    ),
    UpgradeType.restock => loc.keepShelvesFilled,
  };
}

String _upgradeNextEffectLabel(AppLocalizations loc, UpgradeOffer offer) {
  final nextLevel = offer.level + 1;
  return switch (offer.type) {
    UpgradeType.bag => loc.carryProducts.replaceFirst(
      '{capacity}',
      '${3 + nextLevel}',
    ),
    UpgradeType.shelf => '${loc.capacity}: ${4 + nextLevel * 2}',
    UpgradeType.price => loc.profitPerSale.replaceFirst(
      '{value}',
      '${4 + nextLevel * 2}',
    ),
    UpgradeType.speed => loc.movementSpeed.replaceFirst(
      '{value}',
      '${nextLevel * 8}',
    ),
    UpgradeType.checkout => loc.serviceTime.replaceFirst(
      '{value}',
      _nextCheckoutEffect(offer),
    ),
    UpgradeType.restock => loc.keepShelvesFilled,
  };
}

String _nextCheckoutEffect(UpgradeOffer offer) {
  final current = double.tryParse(offer.subtitle.split('s').first) ?? 1;
  return current > 0.38
      ? (current - 0.09).clamp(0.38, 9.99).toStringAsFixed(2)
      : '0.38';
}

class _UpgradeTile extends StatelessWidget {
  const _UpgradeTile({
    required this.upgrade,
    required this.canAfford,
    required this.isMaxed,
    required this.onTap,
  });

  final UpgradeOffer upgrade;
  final bool canAfford;
  final bool isMaxed;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return PressableScale(
      enabled: onTap != null,
      child: Material(
        color: onTap == null
            ? const Color(0xFFEFF2EF).withValues(alpha: 0.6)
            : Colors.white,
        borderRadius: BorderRadius.circular(16),
        elevation: onTap == null ? 0 : 2,
        shadowColor: const Color(0x33000000),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: onTap == null
                    ? const Color(0x330B3B2C)
                    : const Color(0x1A0B3B2C),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: isMaxed
                          ? [const Color(0xFF2FD98F), const Color(0xFF0A8B59)]
                          : canAfford
                          ? [const Color(0xFF62B4FF), const Color(0xFF1D6FD4)]
                          : [const Color(0xFFDCE6E0), const Color(0xFFD3DFD8)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: isMaxed || canAfford
                        ? [
                            BoxShadow(
                              color:
                                  (isMaxed
                                          ? const Color(0xFF2FD98F)
                                          : const Color(0xFF62B4FF))
                                      .withValues(alpha: 0.35),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ]
                        : null,
                  ),
                  child: Icon(
                    upgrade.icon,
                    color: isMaxed || canAfford
                        ? Colors.white
                        : const Color(0xFF7D998F),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        loc.upgradeTitle(upgrade.type),
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                          color: Color(0xFF1C3A32),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        isMaxed
                            ? loc.maxLevel
                            : '${loc.level} ${upgrade.level}/10',
                        style: TextStyle(
                          fontSize: 11,
                          color: isMaxed
                              ? const Color(0xFF2FD98F)
                              : const Color(0xFF4A6E63),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isMaxed
                            ? _upgradeEffectLabel(loc, upgrade)
                            : '${_upgradeEffectLabel(loc, upgrade)} → ${_upgradeNextEffectLabel(loc, upgrade)}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF4A6E63),
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (isMaxed)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2FD98F).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      loc.maxLevel,
                      style: const TextStyle(
                        color: Color(0xFF2FD98F),
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      gradient: canAfford
                          ? const LinearGradient(
                              colors: [Color(0xFF62B4FF), Color(0xFF1D6FD4)],
                            )
                          : null,
                      color: canAfford ? null : const Color(0xFFDCE6E0),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.monetization_on_rounded,
                          size: 13,
                          color: canAfford
                              ? Colors.white
                              : const Color(0xFF7D998F),
                        ),
                        const SizedBox(width: 3),
                        Text(
                          '${upgrade.cost}',
                          style: TextStyle(
                            color: canAfford
                                ? Colors.white
                                : const Color(0xFF7D998F),
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MoneyShopSheet extends StatelessWidget {
  const _MoneyShopSheet({
    required this.game,
    required this.onReward,
    required this.onPurchase,
  });

  final GameController game;
  final Future<void> Function() onReward;
  final Future<void> Function(StoreProduct) onPurchase;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: AnimatedBuilder(
        animation: game,
        builder: (context, _) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _SheetHandle(),
            Row(
              children: [
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    AppLocalizations.of(context).shop,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF1C3A32),
                    ),
                  ),
                ),
                _CurrencyPill(
                  icon: Icons.monetization_on_rounded,
                  value: game.coins,
                  color: const Color(0xFFFFCB45),
                ),
                const SizedBox(width: 8),
                _CurrencyPill(
                  icon: Icons.diamond_rounded,
                  value: game.gems,
                  color: const Color(0xFF6234E0),
                ),
                const SizedBox(width: 16),
              ],
            ),
            const SizedBox(height: 8),
            if (game.rewardedAdsAvailable)
              _ShopRewardTile(
                label: AppLocalizations.of(context).freeBonus,
                subtitle:
                    '${AppLocalizations.of(context).freeBonusSubtitle} — ${AppLocalizations.of(context).rewardCoinsBenefit.replaceFirst('{value}', '${game.instantAdReward}')}',
                icon: Icons.ondemand_video_rounded,
                color: const Color(0xFFEE4664),
                onTap: onReward,
              ),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                itemCount: StoreProduct.values.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final product = StoreProduct.values[index];
                  return _ShopProductTile(
                    game: game,
                    product: product,
                    onTap:
                        game.storePurchasesAvailable &&
                            !game.storePurchaseInProgress
                        ? () => onPurchase(product)
                        : null,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShopRewardTile extends StatelessWidget {
  const _ShopRewardTile({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final String subtitle;
  final IconData icon;
  final Color color;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        elevation: 2,
        shadowColor: const Color(0x33000000),
        child: InkWell(
          onTap: () => onTap(),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0x1A0B3B2C)),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [color, color.withValues(alpha: 0.8)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: color.withValues(alpha: 0.35),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(icon, color: Colors.white, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                          color: Color(0xFF1C3A32),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF4A6E63),
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: Color(0xFF7D998F),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ShopProductTile extends StatelessWidget {
  const _ShopProductTile({
    required this.game,
    required this.product,
    required this.onTap,
  });

  final GameController game;
  final StoreProduct product;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final name = switch (product) {
      StoreProduct.noAds => loc.noAds,
      StoreProduct.coinPack => loc.coinPack,
      StoreProduct.gemPack => loc.gemPack,
      StoreProduct.emergencySupply => loc.emergencySupplyPack,
      StoreProduct.starterPack => loc.starterPack,
    };
    final description = switch (product) {
      StoreProduct.noAds => loc.oneTimePurchase,
      StoreProduct.coinPack => loc.coinPackDesc,
      StoreProduct.gemPack => loc.gemPackDesc,
      StoreProduct.emergencySupply => loc.emergencySupplyPackDesc,
      StoreProduct.starterPack => loc.starterPackDesc,
    };
    final price = game.storePurchasesAvailable
        ? game.storePrice(product) ?? loc.setupRequired
        : loc.comingSoon;
    final icon = switch (product) {
      StoreProduct.noAds => Icons.block_rounded,
      StoreProduct.coinPack => Icons.monetization_on_rounded,
      StoreProduct.gemPack => Icons.diamond_rounded,
      StoreProduct.emergencySupply => Icons.inventory_2_rounded,
      StoreProduct.starterPack => Icons.card_giftcard_rounded,
    };

    return PressableScale(
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        elevation: 2,
        shadowColor: const Color(0x33000000),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0x1A0B3B2C)),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        const Color(0xFFFFCB45),
                        const Color(0xFFD98505),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFFCB45).withValues(alpha: 0.35),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(icon, color: Colors.white, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                          color: Color(0xFF1C3A32),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        description,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF4A6E63),
                        ),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  fit: FlexFit.loose,
                  child: Text(
                    price,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                      color: Color(0xFF1C3A32),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: Color(0xFF7D998F),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OfflineEarningsSheet extends StatelessWidget {
  const _OfflineEarningsSheet({required this.game, required this.onCollect});

  final GameController game;
  final Future<void> Function(bool doubled) onCollect;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _SheetHandle(),
          const SizedBox(height: 8),
          SizedBox(
            width: 150,
            height: 150,
            child: PoRayBurst(
              color: PoColor.goldFace,
              rays: 14,
              child: Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFFFFE39B), Color(0xFFD98505)],
                  ),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.6),
                    width: 3,
                  ),
                  boxShadow: PoElevate.glow(PoColor.goldFace, strength: 1.4),
                ),
                child: const Icon(
                  Icons.nightlight_round,
                  size: 50,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(height: 15),
          Text(
            AppLocalizations.of(context).welcomeBack.toUpperCase(),
            style: const TextStyle(
              color: Color(0xFFD98505),
              fontSize: 12,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            AppLocalizations.of(context).businessKeptEarning,
            style: const TextStyle(color: Color(0xFF4A6E63), fontSize: 14),
          ),
          const SizedBox(height: 17),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _BonusPill(
                icon: Icons.monetization_on_rounded,
                value: '+${game.offlineEarnings}',
                color: const Color(0xFFFFCB45),
              ),
            ],
          ),
          const SizedBox(height: 19),
          Row(
            children: [
              Expanded(
                child: PoBtn(
                  onPressed: () => onCollect(false),
                  expand: true,
                  kind: PoBtnKind.secondary,
                  icon: Icons.check_rounded,
                  label: AppLocalizations.of(context).collect,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: PoBtn(
                  onPressed: () => onCollect(true),
                  expand: true,
                  face: PoColor.goldFace,
                  icon: Icons.flash_on_rounded,
                  label: AppLocalizations.of(context).double,
                ),
              ),
            ],
          ).paddingSymmetric(horizontal: 16),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _AchievementToast extends StatelessWidget {
  const _AchievementToast({
    required this.achievement,
    required this.title,
    required this.description,
  });

  final AchievementDefinition achievement;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFFFFFFF), Color(0xFFFCFEFC)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFFFE9B4)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x330B3B2C),
              blurRadius: 20,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFFD874), Color(0xFFD98505)],
                ),
                shape: BoxShape.circle,
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x44FFCB45),
                    blurRadius: 14,
                    offset: Offset(0, 6),
                  ),
                ],
              ),
              child: Text(
                achievement.badge,
                style: const TextStyle(fontSize: 25),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    AppLocalizations.of(context).achievementUnlocked,
                    style: const TextStyle(
                      color: Color(0xFFD98505),
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    title,
                    style: const TextStyle(
                      color: Color(0xFF1C3A32),
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: const TextStyle(
                      color: Color(0xFF4A6E63),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BonusPill extends StatelessWidget {
  const _BonusPill({
    required this.icon,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    // A reward figure is the emotional payload of the whole sheet, so it is
    // rendered as a minted value on an extruded medallion rather than as tinted
    // body text in a bordered box.
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(6, 6, 16, 6),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [PoColor.lighten(color, 0.22), PoColor.deepen(color, 0.24)],
        ),
        borderRadius: BorderRadius.circular(PoRadius.pill),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.5),
          width: 1.6,
        ),
        boxShadow: PoElevate.glow(color, strength: 0.9),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.white, Color(0xFFE7EEEA)],
              ),
            ),
            child: Icon(icon, size: 18, color: PoColor.deepen(color, 0.3)),
          ),
          const SizedBox(width: 9),
          PoValue(value, size: 21, rim: PoColor.deepen(color, 0.6)),
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * 0.9;
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 8),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Container(
          margin: const EdgeInsets.fromLTRB(14, 0, 14, 8),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            // Same layered treatment as a modal panel elsewhere in the app, so
            // every sheet, dialog and card reads as one product.
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [PoColor.surfaceLift, PoColor.surface],
            ),
            borderRadius: BorderRadius.circular(PoRadius.xl),
            border: Border.all(color: Colors.white, width: 1.5),
            boxShadow: PoElevate.e4,
          ),
          child: child,
        ),
      ),
    );
  }
}

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.fromLTRB(0, 9, 0, 5),
        width: 44,
        height: 5,
        decoration: BoxDecoration(
          color: PoColor.ink.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(PoRadius.pill),
        ),
      ),
    );
  }
}

extension _PaddingExtension on Widget {
  Widget paddingSymmetric({double horizontal = 0, double vertical = 0}) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: horizontal, vertical: vertical),
      child: this,
    );
  }
}
