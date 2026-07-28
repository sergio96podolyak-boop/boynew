import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../game/game_controller.dart';
import '../game/game_models.dart';
import '../game/meta_models.dart';
import '../services/app_localizations.dart';
import '../services/app_settings.dart';
import '../services/monetization_service.dart';
import '../services/sfx/sfx_manager.dart';
import 'market_painter.dart';
import 'widgets/celebration_overlay.dart';
import 'widgets/onboarding_dialog.dart';
import 'widgets/pressable_scale.dart';
import 'widgets/touch_movement.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({
    super.key,
    required this.controller,
    required this.settings,
  });

  final GameController controller;
  final AppSettings settings;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final Ticker _ticker;
  Duration _previousElapsed = Duration.zero;
  double _animationTime = 0;
  bool _offlineSheetShown = false;
  bool _startupFlowStarted = false;
  bool _onboardingDialogOpen = false;
  AchievementDefinition? _achievementToast;
  Timer? _achievementToastTimer;
  final CelebrationController _celebration = CelebrationController();

  GameController get game => widget.controller;
  AppSettings get settings => widget.settings;

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
    _animationTime = elapsed.inMilliseconds / 1000;
    game.tick(dt);
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
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFDDF5E8), Color(0xFFF8EED9)],
          ),
        ),
        child: SafeArea(
          top: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Stack(
                children: [
                  AnimatedBuilder(
                    animation: game,
                    builder: (context, _) => Column(
                      children: [
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(8, 2, 8, 0),
                            child: Stack(
                              children: [
                                Positioned.fill(
                                  child: RepaintBoundary(
                                    child: CustomPaint(
                                      painter: MarketPainter(
                                        game: game,
                                        animationTime: _animationTime,
                                        storageLabel: AppLocalizations.of(
                                          context,
                                        ).storage.toUpperCase(),
                                        shelfLabel: AppLocalizations.of(
                                          context,
                                        ).shelfStock.toUpperCase(),
                                        checkoutLabel: AppLocalizations.of(
                                          context,
                                        ).assignmentCheckout.toUpperCase(),
                                        bakeryLabel: AppLocalizations.of(
                                          context,
                                        ).departmentBakery.toUpperCase(),
                                        bakeryLockedLabel:
                                            AppLocalizations.of(
                                              context,
                                            ).unlockAtLevel.replaceFirst(
                                              '{level}',
                                              '${GameBalance.bakeryUnlockLevel}',
                                            ),
                                        textDirection: Directionality.of(
                                          context,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                Positioned.fill(
                                  child: TouchMovement(
                                    game: game,
                                    onTap: () {},
                                    controlMode: settings.controlMode,
                                  ),
                                ),
                                Positioned(
                                  top: 13,
                                  right: 15,
                                  left: 15,
                                  child: _QuestCard(
                                    quest: game.quest,
                                    title: AppLocalizations.of(context)
                                        .questTitle(
                                          game.questStage,
                                          game.quest.target,
                                        ),
                                    onClaim: _claimQuest,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        _ControlDeck(
                          game: game,
                          settings: settings,
                          onUpgrades: _showUpgrades,
                          onReward: _claimAdReward,
                          onShop: _showMoneyShop,
                        ),
                        const SizedBox(height: 4),
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
    unawaited(SfxManager.instance.click());
    final reward = game.instantAdReward;
    final completed = await game.claimInstantAdReward();
    if (!mounted || !completed) {
      if (mounted) {
        unawaited(SfxManager.instance.error());
      }
      return;
    }
    unawaited(SfxManager.instance.success());
    final loc = AppLocalizations.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(loc.coinsEarned.replaceFirst('{value}', '$reward')),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

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
  });

  final Quest quest;
  final String title;
  final VoidCallback onClaim;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 0),
      child: Material(
        elevation: 5,
        color: const Color(0xFCFFF9F0),
        shadowColor: const Color(0x33315F4A),
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
          child: Row(
            children: [
              Container(
                width: 39,
                height: 39,
                decoration: BoxDecoration(
                  color: quest.completed
                      ? const Color(0xFF38B879)
                      : const Color(0xFFFFE5AF),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  quest.completed ? Icons.check_rounded : Icons.flag_rounded,
                  color: quest.completed
                      ? Colors.white
                      : const Color(0xFFA66B00),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
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
              const SizedBox(width: 10),
              if (quest.completed)
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
    return Container(
      height: 120,
      margin: const EdgeInsets.fromLTRB(10, 2, 10, 8),
      padding: const EdgeInsets.fromLTRB(10, 7, 10, 8),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFDF8EB), Color(0xFFF2E9D7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0x22315F4A)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x17315F4A),
            blurRadius: 12,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  game.interactionHint,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF315F4A),
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              const Icon(
                Icons.inventory_2_rounded,
                size: 14,
                color: Color(0xFFE09A20),
              ),
              const SizedBox(width: 3),
              Text(
                '${game.carried}/${game.bagCapacity}',
                style: const TextStyle(
                  color: Color(0xFF315F4A),
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Expanded(
            child: GridView.count(
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 3,
              crossAxisSpacing: 6,
              mainAxisSpacing: 6,
              childAspectRatio: 1.4,
              children: [
                _RoundAction(
                  label: AppLocalizations.of(context).upgrades,
                  icon: Icons.upgrade_rounded,
                  color: const Color(0xFF5B8DEF),
                  onTap: onUpgrades,
                ),
                _RoundAction(
                  label: game.rewardInProgress
                      ? AppLocalizations.of(context).loading
                      : AppLocalizations.of(context).reward,
                  icon: Icons.ondemand_video_rounded,
                  color: const Color(0xFFE85D75),
                  onTap: game.rewardInProgress ? null : onReward,
                ),
                _RoundAction(
                  label: AppLocalizations.of(context).shop,
                  icon: Icons.shopping_bag_rounded,
                  color: const Color(0xFFF6A623),
                  onTap: onShop,
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          _ControlInstruction(settings: settings),
        ],
      ),
    );
  }
}

class _ControlInstruction extends StatelessWidget {
  const _ControlInstruction({required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final text = switch (settings.controlMode) {
      ControlMode.directTouch => loc.directTouchInstruction,
      ControlMode.joystick => loc.floatingJoystickInstruction,
      ControlMode.leftJoystick => loc.leftHandedJoystickInstruction,
    };
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      child: Text(
        text,
        key: ValueKey(settings.controlMode),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Color(0xFF315F4A),
          fontSize: 10,
          fontWeight: FontWeight.w800,
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
    return PressableScale(
      enabled: onTap != null,
      child: Material(
        color: onTap == null ? color.withValues(alpha: 0.45) : color,
        borderRadius: BorderRadius.circular(16),
        elevation: 2,
        shadowColor: const Color(0x33000000),
        child: InkWell(
          onTap: onTap == null
              ? null
              : () {
                  unawaited(SfxManager.instance.click());
                  onTap!();
                },
          borderRadius: BorderRadius.circular(16),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  color.withValues(alpha: onTap == null ? 0.6 : 0.95),
                  color.withValues(alpha: onTap == null ? 0.45 : 0.8),
                ],
              ),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 50),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: Colors.white, size: 17),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
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
                label: AppLocalizations.of(context).reward,
                subtitle: AppLocalizations.of(context).coinsEarned.replaceFirst(
                  '{value}',
                  '${game.instantAdReward}',
                ),
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
    final price = game.storePrice(product) ?? loc.previewMode;
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
                Text(
                  price,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                    color: Color(0xFF315F4A),
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
  const _AchievementToast({required this.achievement});

  final AchievementDefinition achievement;

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
                    achievement.title,
                    style: const TextStyle(
                      color: Color(0xFF315F4A),
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    achievement.description,
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
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
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
