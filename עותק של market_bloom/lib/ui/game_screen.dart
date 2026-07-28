import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../game/game_controller.dart';
import '../game/game_models.dart';
import '../game/meta_models.dart';
import '../services/monetization_service.dart';
import '../services/sfx/sfx_manager.dart';
import 'market_painter.dart';
import 'widgets/celebration_overlay.dart';
import 'widgets/meta_hub.dart';
import 'widgets/onboarding_dialog.dart';
import 'widgets/pressable_scale.dart';
import 'widgets/virtual_joystick.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({super.key, required this.controller});

  final GameController controller;

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
  AchievementDefinition? _achievementToast;
  Timer? _achievementToastTimer;
  final CelebrationController _celebration = CelebrationController();

  GameController get game => widget.controller;

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
    final completed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PoMarketOnboardingDialog(),
    );
    if (completed == true) {
      game.completeOnboarding();
      unawaited(SfxManager.instance.success());
    }
  }

  void _replayOnboarding() {
    game.replayOnboarding();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(_showOnboarding());
      }
    });
  }

  void _onGameChanged() {
    if (!mounted || _achievementToast != null) {
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

  Future<void> _toggleMute() async {
    final willMute = !game.muted;
    if (willMute) {
      unawaited(SfxManager.instance.click());
    }
    game.setMuted(willMute);
    await SfxManager.instance.setMuted(willMute);
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
    return Scaffold(
      body: CelebrationOverlay(
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
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Stack(
                  children: [
                    AnimatedBuilder(
                      animation: game,
                      builder: (context, _) => Column(
                        children: [
                          _TopBar(
                            game: game,
                            onMute: () => unawaited(_toggleMute()),
                          ),
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
                                        ),
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    top: 13,
                                    right: 15,
                                    left: 15,
                                    child: _QuestCard(
                                      quest: game.quest,
                                      onClaim: _claimQuest,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          _ControlDeck(
                            game: game,
                            onUpgrades: _showUpgrades,
                            onReward: _claimAdReward,
                            onShop: _showMoneyShop,
                            onHub: _showMetaHub,
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
    final suffix = game.isMonetizationPreview ? ' · preview mode' : '';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('You received $reward coins$suffix'),
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
            const SnackBar(
              content: Text('You need more coins for this upgrade'),
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
                    ? 'Purchase complete — items added to your game'
                    : 'This product has not been configured in the store yet',
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

  Future<void> _showMetaHub() {
    unawaited(SfxManager.instance.click());
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _Panel(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _SheetHandle(),
            MetaHub(
              game: game,
              onCelebrate: _celebration.celebrate,
              onReplayTutorial: _replayOnboarding,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showDailyBonus(DailyBonusResult bonus) async {
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
                const Text(
                  'DAILY BONUS',
                  style: TextStyle(
                    color: Color(0xFFE08D19),
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                  ),
                ),
                Text(
                  '${bonus.streak} DAY STREAK!',
                  style: const TextStyle(
                    color: Color(0xFF315F4A),
                    fontSize: 27,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                const Text(
                  'Come back tomorrow to grow your reward.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF6F766F)),
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
                  label: const Text('COLLECT REWARD'),
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

class _TopBar extends StatelessWidget {
  const _TopBar({required this.game, required this.onMute});

  final GameController game;
  final VoidCallback onMute;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 45,
                height: 45,
                decoration: BoxDecoration(
                  color: const Color(0xFF315F4A),
                  borderRadius: BorderRadius.circular(15),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x26315F4A),
                      blurRadius: 12,
                      offset: Offset(0, 5),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.storefront_rounded,
                  color: Colors.white,
                  size: 27,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'POMARKET',
                      textDirection: TextDirection.ltr,
                      style: TextStyle(
                        color: Color(0xFF214B39),
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.8,
                        fontSize: 17,
                      ),
                    ),
                    Text(
                      'Your mini market',
                      style: TextStyle(
                        color: Color(0xFF6B7D72),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              PressableScale(
                child: IconButton.filledTonal(
                  tooltip: game.muted ? 'Unmute sound' : 'Mute sound',
                  onPressed: onMute,
                  constraints: const BoxConstraints.tightFor(
                    width: 48,
                    height: 48,
                  ),
                  icon: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: Icon(
                      game.muted
                          ? Icons.volume_off_rounded
                          : Icons.volume_up_rounded,
                      key: ValueKey(game.muted),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF315F4A),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'LEVEL ${game.storeLevel}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: LinearProgressIndicator(
                    value: game.levelProgress,
                    minHeight: 9,
                    color: const Color(0xFF38B879),
                    backgroundColor: const Color(0x40315F4A),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _CurrencyPill(
                icon: Icons.monetization_on_rounded,
                value: game.coins,
                color: const Color(0xFFF6A623),
                compact: true,
              ),
              const SizedBox(width: 6),
              _CurrencyPill(
                icon: Icons.diamond_rounded,
                value: game.gems,
                color: const Color(0xFF8B66D8),
                compact: true,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CurrencyPill extends StatelessWidget {
  const _CurrencyPill({
    required this.icon,
    required this.value,
    required this.color,
    this.compact = false,
  });

  final IconData icon;
  final int value;
  final Color color;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 10, vertical: 6),
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
  const _QuestCard({required this.quest, required this.onClaim});

  final Quest quest;
  final VoidCallback onClaim;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 5,
      color: const Color(0xF7FFFFFF),
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
                color: quest.completed ? Colors.white : const Color(0xFFA66B00),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    quest.title,
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
                child: Text('CLAIM ${quest.reward}'),
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
    );
  }
}

class _ControlDeck extends StatelessWidget {
  const _ControlDeck({
    required this.game,
    required this.onUpgrades,
    required this.onReward,
    required this.onShop,
    required this.onHub,
  });

  final GameController game;
  final VoidCallback onUpgrades;
  final VoidCallback onReward;
  final VoidCallback onShop;
  final VoidCallback onHub;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 142,
      margin: const EdgeInsets.fromLTRB(10, 2, 10, 8),
      padding: const EdgeInsets.fromLTRB(10, 7, 10, 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.76),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0x22315F4A)),
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
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.inventory_2_rounded,
                size: 16,
                color: Color(0xFFE09A20),
              ),
              const SizedBox(width: 3),
              Text(
                '${game.carried}/${game.bagCapacity}',
                style: const TextStyle(
                  color: Color(0xFF315F4A),
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Expanded(
            child: Row(
              children: [
                VirtualJoystick(onChanged: game.setMovement, size: 104),
                const SizedBox(width: 10),
                Expanded(
                  child: GridView.count(
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 2,
                    crossAxisSpacing: 7,
                    mainAxisSpacing: 7,
                    childAspectRatio: 1.55,
                    children: [
                      _RoundAction(
                        label: 'UPGRADES',
                        icon: Icons.upgrade_rounded,
                        color: const Color(0xFF5B8DEF),
                        onTap: onUpgrades,
                      ),
                      _RoundAction(
                        label: game.rewardInProgress ? 'LOADING…' : 'REWARD',
                        icon: Icons.ondemand_video_rounded,
                        color: const Color(0xFFE85D75),
                        onTap: game.rewardInProgress ? null : onReward,
                      ),
                      _RoundAction(
                        label: 'SHOP',
                        icon: Icons.shopping_bag_rounded,
                        color: const Color(0xFFF6A623),
                        onTap: onShop,
                      ),
                      _RoundAction(
                        label: 'HUB',
                        icon: Icons.grid_view_rounded,
                        color: const Color(0xFF38B879),
                        onTap: onHub,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
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
        borderRadius: BorderRadius.circular(15),
        child: InkWell(
          onTap: onTap == null
              ? null
              : () {
                  unawaited(SfxManager.instance.click());
                  onTap!();
                },
          borderRadius: BorderRadius.circular(15),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: Colors.white, size: 18),
                const SizedBox(width: 3),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.fade,
                    softWrap: false,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                    ),
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
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Upgrade Your Business',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        'Invest to serve more customers',
                        style: TextStyle(color: Color(0xFF717A74)),
                      ),
                    ],
                  ),
                ),
                _CurrencyPill(
                  icon: Icons.monetization_on_rounded,
                  value: game.coins,
                  color: const Color(0xFFF6A623),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: game.upgrades.length,
                separatorBuilder: (_, _) => const SizedBox(height: 9),
                itemBuilder: (context, index) {
                  final offer = game.upgrades[index];
                  final affordable = game.coins >= offer.cost;
                  return _UpgradeTile(
                    offer: offer,
                    affordable: affordable,
                    onBuy: () {
                      final purchased = game.buyUpgrade(offer.type);
                      if (purchased) {
                        onPurchased();
                      } else {
                        onInsufficientCoins();
                      }
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }
}

class _UpgradeTile extends StatelessWidget {
  const _UpgradeTile({
    required this.offer,
    required this.affordable,
    required this.onBuy,
  });

  final UpgradeOffer offer;
  final bool affordable;
  final VoidCallback onBuy;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: offer.color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: offer.color.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: offer.color,
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(offer.icon, color: Colors.white),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  offer.title,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                Text(
                  '${offer.subtitle} · Level ${offer.level}',
                  style: const TextStyle(
                    color: Color(0xFF6F766F),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          FilledButton.icon(
            onPressed: onBuy,
            style: FilledButton.styleFrom(
              backgroundColor: affordable
                  ? const Color(0xFF315F4A)
                  : const Color(0xFF909791),
              padding: const EdgeInsets.symmetric(horizontal: 11),
            ),
            icon: const Icon(Icons.monetization_on_rounded, size: 16),
            label: Text('${offer.cost}'),
          ),
        ],
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
  final Future<void> Function(StoreProduct product) onPurchase;

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
            const Text(
              'Rewards & Shop',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 4),
            Text(
              game.storePurchasesAvailable
                  ? 'Secure purchases through the App Store or Google Play.'
                  : 'Preview build — store items activate after they are created in the developer accounts.',
              style: const TextStyle(color: Color(0xFF717A74), fontSize: 12),
            ),
            const SizedBox(height: 14),
            _StoreCard(
              icon: Icons.ondemand_video_rounded,
              color: const Color(0xFFE85D75),
              title: 'Rewarded Bonus',
              subtitle: 'Get ${game.instantAdReward} coins now',
              buttonLabel: game.rewardInProgress ? 'LOADING…' : 'WATCH & EARN',
              onTap: game.rewardInProgress ? null : onReward,
            ),
            const SizedBox(height: 9),
            _StoreCard(
              icon: Icons.block_rounded,
              color: const Color(0xFF5B8DEF),
              title: 'No Ads',
              subtitle: game.adsRemoved
                  ? 'Already purchased'
                  : 'One-time purchase',
              buttonLabel: game.adsRemoved
                  ? 'OWNED'
                  : game.storePrice(StoreProduct.noAds) ?? 'SETUP REQUIRED',
              onTap:
                  !game.storePurchasesAvailable ||
                      game.adsRemoved ||
                      game.storePurchaseInProgress
                  ? null
                  : () => onPurchase(StoreProduct.noAds),
            ),
            const SizedBox(height: 9),
            _StoreCard(
              icon: Icons.rocket_launch_rounded,
              color: const Color(0xFFF6A623),
              title: 'Starter Pack',
              subtitle: '500 coins, 20 gems, and two upgrades',
              buttonLabel:
                  game.storePrice(StoreProduct.starterPack) ?? 'SETUP REQUIRED',
              onTap:
                  !game.storePurchasesAvailable || game.storePurchaseInProgress
                  ? null
                  : () => onPurchase(StoreProduct.starterPack),
            ),
            const SizedBox(height: 9),
            _StoreCard(
              icon: Icons.monetization_on_rounded,
              color: const Color(0xFF38B879),
              title: '1,000 Coin Pack',
              subtitle: 'Grow your business faster',
              buttonLabel:
                  game.storePrice(StoreProduct.coinPack) ?? 'SETUP REQUIRED',
              onTap:
                  !game.storePurchasesAvailable || game.storePurchaseInProgress
                  ? null
                  : () => onPurchase(StoreProduct.coinPack),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

class _StoreCard extends StatelessWidget {
  const _StoreCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.buttonLabel,
    this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final String buttonLabel;
  final Future<void> Function()? onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: color,
            child: Icon(icon, color: Colors.white),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Color(0xFF6F766F),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          FilledButton(
            onPressed: onTap == null ? null : () => unawaited(onTap!()),
            child: Text(buttonLabel),
          ),
        ],
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
      child: AnimatedBuilder(
        animation: game,
        builder: (context, _) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.storefront_rounded,
              size: 54,
              color: Color(0xFF38B879),
            ),
            const SizedBox(height: 8),
            const Text(
              'Welcome Back!',
              style: TextStyle(fontSize: 25, fontWeight: FontWeight.w900),
            ),
            const Text('Your business kept earning while you were away.'),
            const SizedBox(height: 16),
            _CurrencyPill(
              icon: Icons.monetization_on_rounded,
              value: game.offlineEarnings,
              color: const Color(0xFFF6A623),
            ),
            const SizedBox(height: 17),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: game.rewardInProgress
                        ? null
                        : () => unawaited(onCollect(false)),
                    child: const Text('COLLECT'),
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: game.rewardInProgress
                        ? null
                        : () => unawaited(onCollect(true)),
                    icon: const Icon(Icons.ondemand_video_rounded),
                    label: const Text('DOUBLE ×2'),
                  ),
                ),
              ],
            ),
            if (game.isMonetizationPreview) ...[
              const SizedBox(height: 8),
              const Text(
                'Preview mode grants the reward without a real ad.',
                style: TextStyle(color: Color(0xFF777D79), fontSize: 11),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AchievementToast extends StatelessWidget {
  const _AchievementToast({required this.achievement});

  final AchievementDefinition achievement;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 390),
        child: Material(
          elevation: 12,
          shadowColor: const Color(0x66315F4A),
          color: const Color(0xFF234B38),
          borderRadius: BorderRadius.circular(21),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(13, 10, 15, 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 49,
                  height: 49,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFD95A),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Text(
                    achievement.badge,
                    style: const TextStyle(fontSize: 24),
                  ),
                ),
                const SizedBox(width: 11),
                Flexible(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'ACHIEVEMENT UNLOCKED',
                        style: TextStyle(
                          color: Color(0xFFFFD95A),
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.9,
                        ),
                      ),
                      Text(
                        achievement.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
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
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 6),
          Text(
            value,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
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
    return SafeArea(
      top: false,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.82,
        ),
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
        decoration: const BoxDecoration(
          color: Color(0xFFFFFCF6),
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: child,
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
        width: 44,
        height: 5,
        margin: const EdgeInsets.only(bottom: 13),
        decoration: BoxDecoration(
          color: const Color(0xFFD6D2CA),
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }
}
