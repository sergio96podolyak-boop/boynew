import 'dart:async';

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
  });

  final GameController controller;
  final AppSettings settings;
  final VoidCallback? onOpenStaff;
  final VoidCallback? onOpenInventory;
  final VoidCallback? onOpenDepartments;

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
              PoDepthColors.deepSea,
              PoDepthColors.abyss,
            ],
            stops: [0, 0.5, 1],
          ),
        ),
        child: SafeArea(
          top: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Stack(
                key: const ValueKey('market-page-viewport'),
                children: [
                  AnimatedBuilder(
                    animation: game,
                    builder: (context, _) => Column(
                      children: [
                        Container(
                          key: const ValueKey('objective-strip'),
                          height: MediaQuery.sizeOf(context).width <= 420
                              ? 52
                              : 64,
                          // Trailing gap clears the floating world menu that
                          // AppShell pins to the top-end corner, which was
                          // sitting on top of the objective text.
                          padding: const EdgeInsetsDirectional.fromSTEB(
                            8,
                            2,
                            72,
                            2,
                          ),
                          alignment: Alignment.center,
                          child: _QuestCard(
                            quest: game.quest,
                            title: AppLocalizations.of(
                              context,
                            ).questTitle(game.questStage, game.quest.target),
                            onClaim: _claimQuest,
                            compact: MediaQuery.sizeOf(context).width <= 420,
                            reducedMotion:
                                settings.reducedMotion ||
                                MediaQuery.disableAnimationsOf(context),
                          ),
                        ),
                        Expanded(
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final availableRatio =
                                  constraints.maxWidth / constraints.maxHeight;
                              final boardAspectRatio =
                                  availableRatio.clamp(0.60, 1.08);
                              return Center(
                                child: AspectRatio(
                                  aspectRatio: boardAspectRatio,
                                  child: Container(
                                    key: const ValueKey('market-board'),
                                    margin: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                    ),
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
                                                      AppLocalizations.of(
                                                        context,
                                                      ).departmentBakery.toUpperCase(),
                                                  checkoutLabel:
                                                      AppLocalizations.of(
                                                        context,
                                                      ).assignmentCheckout.toUpperCase(),
                                                  shelfLabel:
                                                      AppLocalizations.of(
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
                                          PositionedDirectional(
                                            start: 10,
                                            end: 10,
                                            bottom: 8,
                                            child: _WorldContextActions(
                                              game: game,
                                              onOpenStaff: widget.onOpenStaff,
                                              onOpenInventory:
                                                  widget.onOpenInventory,
                                              onOpenDepartments:
                                                  widget.onOpenDepartments,
                                            ),
                                          ),
                                          if (game.pendingShiftSummary != null)
                                            Positioned.fill(
                                              child: Padding(
                                                padding: const EdgeInsets.all(8),
                                                child: ShiftPnlSummary(
                                                  summary: game.pendingShiftSummary!,
                                                  cashBalance: game.coins,
                                                  onContinue: game.startNextShift,
                                                ),
                                              ),
                                            ),
                                          if (game.fastCheckoutActive)
                                            Positioned(
                                              top: 70,
                                              left: 22,
                                              right: 22,
                                              child: _FastCheckoutBanner(
                                                claimed: game.fastCheckoutClaimed,
                                                onClaim: () {
                                                  if (game.claimFastCheckoutBonus()) {
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
                                              ),
                                            ),
                                          if (game.comboCount > 1)
                                            Positioned(
                                              top: 14,
                                              right: 14,
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(
                                                  horizontal: 12,
                                                  vertical: 6,
                                                ),
                                                decoration: BoxDecoration(
                                                  gradient: const LinearGradient(
                                                    colors: [
                                                      Color(0xFFFF9F1C),
                                                      Color(0xFFFF4040),
                                                    ],
                                                  ),
                                                  borderRadius: BorderRadius.circular(20),
                                                  boxShadow: const [
                                                    BoxShadow(
                                                      color: Color(0x66FF4040),
                                                      blurRadius: 8,
                                                      offset: Offset(0, 3),
                                                    ),
                                                  ],
                                                ),
                                                child: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    const Icon(
                                                      Icons.local_fire_department_rounded,
                                                      color: Colors.white,
                                                      size: 20,
                                                    ),
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      '${game.comboCount}x COMBO!',
                                                      style: const TextStyle(
                                                        color: Colors.white,
                                                        fontWeight: FontWeight.w900,
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
                                  ),
                                );
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                  Positioned(
                    top: 112,
                    left: 12,
                    right: 12,
                    child: IgnorePointer(
                      ignoring: _achievementToast == null,
                      child: AnimatedSlide(
                        duration: const Duration(milliseconds: 360),
                        curve: Curves.easeOutBack,
                        offset: _achievementToast == null
                            ? const Offset(0, -1.4)
                            : Offset.zero,
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 220),
                          opacity: _achievementToast == null ? 0 : 1,
                          child: _achievementToast == null
                              ? const SizedBox.shrink()
                              : _AchievementToast(
                                  achievement: _achievementToast!,
                                  title: AppLocalizations.of(
                                    context,
                                  ).achievementTitle(_achievementToast!.id),
                                  description: AppLocalizations.of(context)
                                      .achievementDescription(
                                        _achievementToast!.id,
                                      ),
                                ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
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
              color: const Color(0xFFFFFCF6),
              borderRadius: BorderRadius.circular(28),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x44315F4A),
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
                      colors: [Color(0xFFFFC94D), Color(0xFFF08B32)],
                    ),
                    shape: BoxShape.circle,
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x44F6A623),
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
                    color: Color(0xFFE08D19),
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                  ),
                ),
                Text(
                  loc.dayStreak.replaceFirst('{streak}', '${bonus.streak}'),
                  style: const TextStyle(
                    color: Color(0xFF315F4A),
                    fontSize: 27,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  loc.comeBackTomorrow,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFF6F766F)),
                ),
                const SizedBox(height: 17),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _BonusPill(
                      icon: Icons.monetization_on_rounded,
                      value: '+${bonus.coinsAwarded}',
                      color: const Color(0xFFF6A623),
                    ),
                    if (bonus.gemsAwarded > 0) ...[
                      const SizedBox(width: 9),
                      _BonusPill(
                        icon: Icons.diamond_rounded,
                        value: '+${bonus.gemsAwarded}',
                        color: const Color(0xFF8B66D8),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 19),
                FilledButton.icon(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    backgroundColor: const Color(0xFF38B879),
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
      color: const Color(0xFFFFFCF6),
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: AnimatedBuilder(
        animation: game,
        builder: (context, _) {
          final choices = <_RewardChoice>[
            _RewardChoice(
              placement: RewardPlacement.instantCoins,
              icon: Icons.monetization_on_rounded,
              color: const Color(0xFFF6A623),
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
                color: const Color(0xFF38B879),
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
                      color: Color(0xFF315F4A),
                      size: 25,
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        loc.rewardCenterTitle,
                        style: const TextStyle(
                          color: Color(0xFF315F4A),
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
                        color: const Color(0x14315F4A),
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Text(
                        loc.optionalAdDescription,
                        style: const TextStyle(
                          color: Color(0xFF315F4A),
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
                        color: Color(0xFF6B746E),
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
                        color: Color(0xFF315F4A),
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      choice.benefit,
                      style: const TextStyle(
                        color: Color(0xFF6B746E),
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
                            ? const Color(0xFF38A66E)
                            : const Color(0xFF8A7D6C),
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
                  backgroundColor: const Color(0xFF315F4A),
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
        color: const Color(0xFFFFF3E0),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: const Color(0x33E09A20)),
      ),
      child: Row(
        children: [
          const Icon(Icons.phone_android_rounded, color: Color(0xFFE09A20)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${loc.mobileFeaturePreview}: ${loc.rewardPreviewUnavailable}',
              style: const TextStyle(
                color: Color(0xFF8A5B19),
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
      color: const Color(0xFFFFF3D7),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            const Icon(Icons.bolt_rounded, color: Color(0xFFE08D19)),
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

class _QuestCard extends StatelessWidget {
  const _QuestCard({
    required this.quest,
    required this.title,
    required this.onClaim,
    required this.compact,
    required this.reducedMotion,
  });

  final Quest quest;
  final String title;
  final VoidCallback onClaim;
  final bool compact;
  final bool reducedMotion;

  @override
  Widget build(BuildContext context) {
    final motionDuration = reducedMotion
        ? Duration.zero
        : const Duration(milliseconds: 220);
    return TweenAnimationBuilder<double>(
      key: ValueKey(quest.completed),
      tween: Tween(begin: quest.completed ? 0.97 : 1, end: 1),
      duration: motionDuration,
      curve: Curves.easeOut,
      builder: (context, scale, child) =>
          Transform.scale(scale: scale, child: child),
      child: Material(
        elevation: compact ? 3 : 5,
        color: const Color(0xFCFFF9F0),
        shadowColor: const Color(0x33315F4A),
        borderRadius: BorderRadius.circular(compact ? 15 : 18),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 9 : 12,
            vertical: compact ? 5 : 9,
          ),
          child: Row(
            children: [
              Container(
                width: compact ? 30 : 39,
                height: compact ? 30 : 39,
                decoration: BoxDecoration(
                  color: quest.completed
                      ? const Color(0xFF38B879)
                      : const Color(0xFFFFE5AF),
                  borderRadius: BorderRadius.circular(compact ? 10 : 13),
                ),
                child: Icon(
                  quest.completed ? Icons.check_rounded : Icons.flag_rounded,
                  size: compact ? 18 : 24,
                  color: quest.completed
                      ? Colors.white
                      : const Color(0xFFA66B00),
                ),
              ),
              SizedBox(width: compact ? 7 : 10),
              Expanded(
                child: compact
                    ? _CompactQuestDetails(quest: quest, title: title)
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 5),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: LinearProgressIndicator(
                              value: quest.fraction,
                              minHeight: 6,
                              color: const Color(0xFFF6A623),
                              backgroundColor: const Color(0xFFE8E5DC),
                            ),
                          ),
                        ],
                      ),
              ),
              SizedBox(width: compact ? 6 : 10),
              if (quest.completed && compact)
                Semantics(
                  label: AppLocalizations.of(context).claimReward,
                  button: true,
                  child: IconButton(
                    onPressed: onClaim,
                    tooltip: AppLocalizations.of(context).claimReward,
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 30,
                      height: 30,
                    ),
                    icon: const Icon(
                      Icons.card_giftcard_rounded,
                      size: 19,
                      color: Color(0xFF38B879),
                    ),
                  ),
                )
              else if (quest.completed)
                FilledButton(
                  onPressed: onClaim,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  child: Text(
                    '${AppLocalizations.of(context).claimReward} ${quest.reward}',
                  ),
                )
              else
                Text(
                  '${quest.progress.clamp(0, quest.target)}/${quest.target}',
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(
                    color: Color(0xFF6B746E),
                    fontWeight: FontWeight.w900,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompactQuestDetails extends StatelessWidget {
  const _CompactQuestDetails({required this.quest, required this.title});

  final Quest quest;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
        ),
        const SizedBox(height: 3),
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: LinearProgressIndicator(
            value: quest.fraction,
            minHeight: 4,
            color: const Color(0xFFF6A623),
            backgroundColor: const Color(0xFFE8E5DC),
          ),
        ),
      ],
    );
  }
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
}) _contextLabels(BuildContext context) {
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
        color: const Color(0xFFFDF8EB),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0x30315F4A)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x17315F4A),
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
                          color: const Color(0xFF315F4A),
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
                          color: const Color(0xFFB45C55),
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
                          color: const Color(0xFFC48124),
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
    final actionKey = pending ? const ValueKey('quick-restock-action-pending') : const ValueKey('quick-restock-action');
    final color = emergency ? const Color(0xFF38B879) : const Color(0xFFF6A623);

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
        color: const Color(0x14315F4A),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.inventory_2_rounded,
            size: 13,
            color: Color(0xFFE09A20),
          ),
          const SizedBox(width: 3),
          Text(
            '$carried/$capacity',
            textDirection: TextDirection.ltr,
            style: const TextStyle(
              color: Color(0xFF315F4A),
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
            color: Color(0xFF315F4A),
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
                      color: Color(0xFF315F4A),
                    ),
                  ),
                ),
                _CurrencyPill(
                  icon: Icons.monetization_on_rounded,
                  value: game.coins,
                  color: const Color(0xFFF6A623),
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
            ? const Color(0xFFF5F0E8).withValues(alpha: 0.6)
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
                    ? const Color(0x33315F4A)
                    : const Color(0x1A315F4A),
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
                          ? [const Color(0xFF38B879), const Color(0xFF2E9B5F)]
                          : canAfford
                          ? [const Color(0xFF5B8DEF), const Color(0xFF4A7BD5)]
                          : [const Color(0xFFE8E0D8), const Color(0xFFD8D0C8)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: isMaxed || canAfford
                        ? [
                            BoxShadow(
                              color:
                                  (isMaxed
                                          ? const Color(0xFF38B879)
                                          : const Color(0xFF5B8DEF))
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
                        : const Color(0xFF8B8078),
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
                          color: Color(0xFF315F4A),
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
                              ? const Color(0xFF38B879)
                              : const Color(0xFF6B746E),
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
                          color: Color(0xFF6B746E),
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
                      color: const Color(0xFF38B879).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      loc.maxLevel,
                      style: const TextStyle(
                        color: Color(0xFF38B879),
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
                              colors: [Color(0xFF5B8DEF), Color(0xFF4A7BD5)],
                            )
                          : null,
                      color: canAfford ? null : const Color(0xFFE8E0D8),
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
                              : const Color(0xFF8B8078),
                        ),
                        const SizedBox(width: 3),
                        Text(
                          '${upgrade.cost}',
                          style: TextStyle(
                            color: canAfford
                                ? Colors.white
                                : const Color(0xFF8B8078),
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
                      color: Color(0xFF315F4A),
                    ),
                  ),
                ),
                _CurrencyPill(
                  icon: Icons.monetization_on_rounded,
                  value: game.coins,
                  color: const Color(0xFFF6A623),
                ),
                const SizedBox(width: 8),
                _CurrencyPill(
                  icon: Icons.diamond_rounded,
                  value: game.gems,
                  color: const Color(0xFF8B66D8),
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
                color: const Color(0xFFE85D75),
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
              border: Border.all(color: const Color(0x1A315F4A)),
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
                          color: Color(0xFF315F4A),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF6B746E),
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: Color(0xFF8B8078),
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
              border: Border.all(color: const Color(0x1A315F4A)),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        const Color(0xFFF6A623),
                        const Color(0xFFE09A20),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFF6A623).withValues(alpha: 0.35),
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
                          color: Color(0xFF315F4A),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        description,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF6B746E),
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
                      color: Color(0xFF315F4A),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: Color(0xFF8B8078),
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
          Container(
            width: 92,
            height: 92,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFFC94D), Color(0xFFF08B32)],
              ),
              shape: BoxShape.circle,
              boxShadow: const [
                BoxShadow(
                  color: Color(0x44F6A623),
                  blurRadius: 22,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            child: const Icon(
              Icons.nightlight_round,
              size: 53,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 15),
          Text(
            AppLocalizations.of(context).welcomeBack.toUpperCase(),
            style: const TextStyle(
              color: Color(0xFFE08D19),
              fontSize: 12,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            AppLocalizations.of(context).businessKeptEarning,
            style: const TextStyle(color: Color(0xFF6F766F), fontSize: 14),
          ),
          const SizedBox(height: 17),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _BonusPill(
                icon: Icons.monetization_on_rounded,
                value: '+${game.offlineEarnings}',
                color: const Color(0xFFF6A623),
              ),
            ],
          ),
          const SizedBox(height: 19),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => onCollect(false),
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: Text(AppLocalizations.of(context).collect),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    foregroundColor: const Color(0xFF315F4A),
                    side: const BorderSide(color: Color(0xFF315F4A)),
                    textStyle: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => onCollect(true),
                  icon: const Icon(Icons.flash_on_rounded, size: 18),
                  label: Text(AppLocalizations.of(context).double),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    backgroundColor: const Color(0xFFF6A623),
                    textStyle: const TextStyle(fontWeight: FontWeight.w900),
                  ),
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
            colors: [Color(0xFFFFFCF6), Color(0xFFFFF8F0)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFE8DCC8)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33315F4A),
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
                  colors: [Color(0xFFFFC94D), Color(0xFFF08B32)],
                ),
                shape: BoxShape.circle,
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x44F6A623),
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
                      color: Color(0xFFE08D19),
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    title,
                    style: const TextStyle(
                      color: Color(0xFF315F4A),
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: const TextStyle(
                      color: Color(0xFF6B746E),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 4),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w900,
              fontSize: 12,
            ),
          ),
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
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: const Color(0xFFFFFCF6),
            borderRadius: BorderRadius.circular(28),
            boxShadow: const [
              BoxShadow(
                color: Color(0x44315F4A),
                blurRadius: 28,
                offset: Offset(0, 13),
              ),
            ],
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
        margin: const EdgeInsets.fromLTRB(0, 10, 0, 4),
        width: 40,
        height: 5,
        decoration: BoxDecoration(
          color: const Color(0xFFD8D0C8),
          borderRadius: BorderRadius.circular(3),
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
