import 'package:flutter/material.dart';

import '../../game/game_controller.dart';
import '../../services/app_localizations.dart';
import '../widgets/management_ui.dart';
import '../widgets/premium_ui.dart';
import '../widgets/pressable_scale.dart';

class QuestsScreen extends StatelessWidget {
  const QuestsScreen({super.key, required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return ManagementScaffold(
      title: loc.questsTitle,
      icon: Icons.flag_circle_rounded,
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final quest = controller.quest;
          final completedCount = <bool>[
            controller.shiftMissionCompleted,
            controller.dailyMissionCompleted,
            quest.completed,
          ].where((completed) => completed).length;
          final readyToClaimCount = <bool>[
            controller.shiftMissionCompleted &&
                !controller.shiftMissionClaimed,
            controller.dailyMissionCompleted &&
                !controller.dailyMissionClaimed,
            quest.completed,
          ].where((ready) => ready).length;
          final unclaimedReward =
              (controller.shiftMissionClaimed ? 0 : 20) +
              (controller.dailyMissionClaimed ? 0 : 15) +
              quest.reward;

          return FocusTraversalGroup(
            policy: OrderedTraversalPolicy(),
            child: ListView(
              padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 28),
              children: [
                ManagementHero(
                  icon: Icons.route_rounded,
                  title: loc.questsTitle,
                  subtitle: _term(
                    context,
                    en: 'Clear goals, visible progress, useful rewards',
                    he: 'יעדים ברורים, התקדמות גלויה ופרסים שימושיים',
                    ar: 'أهداف واضحة وتقدم ظاهر ومكافآت مفيدة',
                  ),
                  colors: const [Color(0xFF4A3514), Color(0xFFB77718)],
                  metrics: [
                    ManagementHeroMetric(
                      icon: Icons.task_alt_rounded,
                      label: _term(
                        context,
                        en: 'Completed',
                        he: 'הושלמו',
                        ar: 'مكتملة',
                      ),
                      value: '$completedCount/3',
                    ),
                    ManagementHeroMetric(
                      icon: Icons.redeem_rounded,
                      label: _term(
                        context,
                        en: 'Ready to claim',
                        he: 'מוכנות לאיסוף',
                        ar: 'جاهزة للجمع',
                      ),
                      value: '$readyToClaimCount',
                    ),
                    ManagementHeroMetric(
                      icon: Icons.stars_rounded,
                      label: _term(
                        context,
                        en: 'Quest stage',
                        he: 'שלב משימה',
                        ar: 'مرحلة المهمة',
                      ),
                      value: '${controller.questStage}',
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _QuestSummary(
                  activeCount: controller.initialized ? 3 : 0,
                  completedCount: completedCount,
                  readyToClaimCount: readyToClaimCount,
                  unclaimedReward: unclaimedReward,
                ),
                const SizedBox(height: 22),
                ManagementSectionTitle(
                  title: _term(
                    context,
                    en: 'Current missions',
                    he: 'משימות נוכחיות',
                    ar: 'المهام الحالية',
                  ),
                  subtitle: _term(
                    context,
                    en: 'Follow the next action, finish the goal and collect the reward',
                    he: 'עקבו אחר הפעולה הבאה, השלימו את היעד ואספו את הפרס',
                    ar: 'اتبع الخطوة التالية وأكمل الهدف واجمع المكافأة',
                  ),
                  trailing: ManagementStatusPill(
                    label: '$completedCount/3',
                    color: completedCount == 3
                        ? PoMarketPalette.mint
                        : PoMarketPalette.gold,
                    icon: Icons.task_alt_rounded,
                  ),
                ),
                const SizedBox(height: 12),
                ManagementResponsiveWrap(
                  children: [
                    FocusTraversalOrder(
                      order: const NumericFocusOrder(1),
                      child: _QuestProgressCard(
                        key: const ValueKey('quest-card-shift'),
                        kind: loc.shiftMission,
                        icon: Icons.schedule_rounded,
                        color: PoMarketPalette.blue,
                        title: loc.serveFiveCustomers,
                        description: _term(
                          context,
                          en: 'Build momentum by serving customers before the current shift ends.',
                          he: 'צברו תנופה באמצעות שירות לקוחות לפני סיום המשמרת הנוכחית.',
                          ar: 'ابنِ الزخم بخدمة العملاء قبل انتهاء الوردية الحالية.',
                        ),
                        nextAction: _term(
                          context,
                          en: 'Serve customers during the current shift',
                          he: 'שרתו לקוחות במהלך המשמרת הנוכחית',
                          ar: 'اخدم العملاء خلال الوردية الحالية',
                        ),
                        progress: controller.shiftMissionProgress,
                        target: controller.shiftMissionTarget,
                        reward: 20,
                        available: controller.initialized,
                        completed: controller.shiftMissionCompleted,
                        claimed: controller.shiftMissionClaimed,
                        onClaim: () => _claimMission(
                          context,
                          controller.claimShiftMission,
                          20,
                        ),
                        loc: loc,
                      ),
                    ),
                    FocusTraversalOrder(
                      order: const NumericFocusOrder(2),
                      child: _QuestProgressCard(
                        key: const ValueKey('quest-card-daily'),
                        kind: loc.dailyMission,
                        icon: Icons.sentiment_satisfied_alt_rounded,
                        color: PoMarketPalette.mint,
                        title: loc.keepCustomersHappy,
                        description: _term(
                          context,
                          en: 'Protect customer satisfaction and finish the day without missed sales.',
                          he: 'שמרו על שביעות רצון הלקוחות וסיימו את היום ללא מכירות שהוחמצו.',
                          ar: 'حافظ على رضا العملاء وأنهِ اليوم دون مبيعات ضائعة.',
                        ),
                        nextAction: _term(
                          context,
                          en: 'Keep satisfaction high and avoid missed sales',
                          he: 'שמרו על שביעות רצון גבוהה והימנעו ממכירות שהוחמצו',
                          ar: 'حافظ على رضا مرتفع وتجنب المبيعات الضائعة',
                        ),
                        progress: controller.dailyMissionCompleted ? 1 : 0,
                        target: 1,
                        reward: 15,
                        available: controller.initialized,
                        completed: controller.dailyMissionCompleted,
                        claimed: controller.dailyMissionClaimed,
                        onClaim: () => _claimMission(
                          context,
                          controller.claimDailyMission,
                          15,
                        ),
                        loc: loc,
                      ),
                    ),
                    FocusTraversalOrder(
                      order: const NumericFocusOrder(3),
                      child: _QuestProgressCard(
                        key: const ValueKey('quest-card-progression'),
                        kind: loc.progressionMission,
                        icon: Icons.auto_graph_rounded,
                        color: PoMarketPalette.violet,
                        title: loc.questTitle(
                          controller.questStage,
                          quest.target,
                        ),
                        description: _term(
                          context,
                          en: 'Advance the market through the current long-term progression stage.',
                          he: 'קדמו את המרקט דרך שלב ההתקדמות ארוך הטווח הנוכחי.',
                          ar: 'طوّر المتجر عبر مرحلة التقدم طويلة المدى الحالية.',
                        ),
                        nextAction: _term(
                          context,
                          en: 'Continue growing the market to advance this stage',
                          he: 'המשיכו לפתח את המרקט כדי להתקדם בשלב',
                          ar: 'واصل تطوير المتجر للتقدم في هذه المرحلة',
                        ),
                        progress: quest.progress,
                        target: quest.target,
                        reward: quest.reward,
                        available: controller.initialized,
                        completed: quest.completed,
                        claimed: false,
                        emphasized: true,
                        onClaim: () {
                          if (!quest.completed) return;
                          controller.claimQuest();
                          _showReward(context, loc, quest.reward);
                        },
                        loc: loc,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _claimMission(
    BuildContext context,
    bool Function() claim,
    int reward,
  ) {
    if (!claim()) return;
    _showReward(context, AppLocalizations.of(context), reward);
  }

  void _showReward(BuildContext context, AppLocalizations loc, int reward) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${loc.questCompleted} +$reward'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

class _QuestSummary extends StatelessWidget {
  const _QuestSummary({
    required this.activeCount,
    required this.completedCount,
    required this.readyToClaimCount,
    required this.unclaimedReward,
  });

  final int activeCount;
  final int completedCount;
  final int readyToClaimCount;
  final int unclaimedReward;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: const ValueKey('quest-summary'),
      container: true,
      label: _term(
        context,
        en: 'Quest summary',
        he: 'סיכום משימות',
        ar: 'ملخص المهام',
      ),
      child: ManagementCard(
        padding: const EdgeInsets.all(14),
        accent: PoMarketPalette.gold,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const StatusDot(color: PoMarketPalette.gold, size: 8),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _term(
                      context,
                      en: 'Mission overview',
                      he: 'סקירת משימות',
                      ar: 'نظرة عامة على المهام',
                    ),
                    style: const TextStyle(
                      color: PoMarketPalette.ink,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                ManagementStatusPill(
                  label: readyToClaimCount > 0
                      ? _term(
                          context,
                          en: '$readyToClaimCount ready',
                          he: '$readyToClaimCount מוכנות',
                          ar: '$readyToClaimCount جاهزة',
                        )
                      : _term(
                          context,
                          en: 'In progress',
                          he: 'בתהליך',
                          ar: 'قيد التقدم',
                        ),
                  color: readyToClaimCount > 0
                      ? PoMarketPalette.mint
                      : PoMarketPalette.blue,
                  icon: readyToClaimCount > 0
                      ? Icons.redeem_rounded
                      : Icons.timelapse_rounded,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ManagementInfoTile(
                  label: _term(
                    context,
                    en: 'Active',
                    he: 'פעילות',
                    ar: 'نشطة',
                  ),
                  value: '$activeCount',
                  icon: Icons.flag_rounded,
                  color: PoMarketPalette.blue,
                ),
                ManagementInfoTile(
                  label: _term(
                    context,
                    en: 'Completed',
                    he: 'הושלמו',
                    ar: 'مكتملة',
                  ),
                  value: '$completedCount/3',
                  icon: Icons.task_alt_rounded,
                  color: PoMarketPalette.mint,
                ),
                ManagementInfoTile(
                  label: _term(
                    context,
                    en: 'Rewards ahead',
                    he: 'פרסים בהמשך',
                    ar: 'مكافآت قادمة',
                  ),
                  value: '$unclaimedReward',
                  icon: Icons.card_giftcard_rounded,
                  color: PoMarketPalette.gold,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

enum _QuestVisualState { locked, available, completed, claimed }

class _QuestProgressCard extends StatefulWidget {
  const _QuestProgressCard({
    super.key,
    required this.kind,
    required this.icon,
    required this.color,
    required this.title,
    required this.description,
    required this.nextAction,
    required this.progress,
    required this.target,
    required this.reward,
    required this.available,
    required this.completed,
    required this.claimed,
    required this.onClaim,
    required this.loc,
    this.emphasized = false,
  });

  final String kind;
  final IconData icon;
  final Color color;
  final String title;
  final String description;
  final String nextAction;
  final int progress;
  final int target;
  final int reward;
  final bool available;
  final bool completed;
  final bool claimed;
  final bool emphasized;
  final VoidCallback onClaim;
  final AppLocalizations loc;

  @override
  State<_QuestProgressCard> createState() => _QuestProgressCardState();
}

class _QuestProgressCardState extends State<_QuestProgressCard> {
  bool _focused = false;

  _QuestVisualState get state {
    if (!widget.available) return _QuestVisualState.locked;
    if (widget.claimed) return _QuestVisualState.claimed;
    if (widget.completed) return _QuestVisualState.completed;
    return _QuestVisualState.available;
  }

  @override
  Widget build(BuildContext context) {
    final safeTarget = widget.target <= 0 ? 1 : widget.target;
    final fraction = (widget.progress / safeTarget).clamp(0.0, 1.0);
    final displayProgress = widget.progress.clamp(0, safeTarget);
    final visualState = state;
    final statusColor = switch (visualState) {
      _QuestVisualState.locked => PoMarketPalette.muted,
      _QuestVisualState.available => widget.color,
      _QuestVisualState.completed => PoMarketPalette.mint,
      _QuestVisualState.claimed => PoMarketPalette.forestLight,
    };
    final statusLabel = switch (visualState) {
      _QuestVisualState.locked => widget.loc.locked,
      _QuestVisualState.available => _term(
        context,
        en: 'In progress',
        he: 'בתהליך',
        ar: 'قيد التقدم',
      ),
      _QuestVisualState.completed => _term(
        context,
        en: 'Ready to claim',
        he: 'מוכן לאיסוף',
        ar: 'جاهزة للجمع',
      ),
      _QuestVisualState.claimed => widget.loc.claimed,
    };
    final statusIcon = switch (visualState) {
      _QuestVisualState.locked => Icons.lock_rounded,
      _QuestVisualState.available => Icons.timelapse_rounded,
      _QuestVisualState.completed => Icons.redeem_rounded,
      _QuestVisualState.claimed => Icons.verified_rounded,
    };
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final semanticsValue = '$displayProgress / $safeTarget';

    return Semantics(
      container: true,
      label:
          '${widget.kind}. ${widget.title}. ${widget.description}. $statusLabel',
      value: semanticsValue,
      child: Focus(
        canRequestFocus: visualState == _QuestVisualState.completed,
        onFocusChange: (focused) {
          if (_focused != focused) setState(() => _focused = focused);
        },
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(
            begin: visualState == _QuestVisualState.completed ? 0.985 : 1,
            end: 1,
          ),
          duration: reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          builder: (context, scale, child) => Transform.scale(
            scale: scale,
            alignment: Alignment.center,
            child: child,
          ),
          child: ManagementCard(
            accent: statusColor,
            highlighted:
                widget.emphasized ||
                _focused ||
                visualState == _QuestVisualState.completed,
            muted: visualState == _QuestVisualState.locked,
            padding: EdgeInsets.zero,
            child: Stack(
              children: [
                if (visualState == _QuestVisualState.completed)
                  const PositionedDirectional(
                    top: 12,
                    end: 14,
                    child: ExcludeSemantics(child: _CompletionSparkles()),
                  ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _QuestCardHeader(
                        kind: widget.kind,
                        icon: widget.icon,
                        color: widget.color,
                        title: widget.title,
                        description: widget.description,
                        state: visualState,
                        statusColor: statusColor,
                        statusLabel: statusLabel,
                        statusIcon: statusIcon,
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 10,
                        runSpacing: 8,
                        children: [
                          ManagementInfoTile(
                            label: _term(
                              context,
                              en: 'Progress',
                              he: 'התקדמות',
                              ar: 'التقدم',
                            ),
                            value: semanticsValue,
                            icon: Icons.trending_up_rounded,
                            color: statusColor,
                          ),
                          ManagementStatusPill(
                            label: '${widget.loc.missionReward} ${widget.reward}',
                            color: PoMarketPalette.gold,
                            icon: Icons.card_giftcard_rounded,
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Semantics(
                        label: _term(
                          context,
                          en: 'Quest progress',
                          he: 'התקדמות במשימה',
                          ar: 'تقدم المهمة',
                        ),
                        value: semanticsValue,
                        child: ExcludeSemantics(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(999),
                            child: LinearProgressIndicator(
                              value: fraction,
                              minHeight: 10,
                              color: statusColor,
                              backgroundColor: statusColor.withValues(
                                alpha: 0.11,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      _QuestActionArea(
                        state: visualState,
                        color: statusColor,
                        nextAction: widget.nextAction,
                        onClaim: widget.onClaim,
                        loc: widget.loc,
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

class _QuestCardHeader extends StatelessWidget {
  const _QuestCardHeader({
    required this.kind,
    required this.icon,
    required this.color,
    required this.title,
    required this.description,
    required this.state,
    required this.statusColor,
    required this.statusLabel,
    required this.statusIcon,
  });

  final String kind;
  final IconData icon;
  final Color color;
  final String title;
  final String description;
  final _QuestVisualState state;
  final Color statusColor;
  final String statusLabel;
  final IconData statusIcon;

  @override
  Widget build(BuildContext context) {
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    return LayoutBuilder(
      builder: (context, constraints) {
        final stackStatus = constraints.maxWidth < 340 || textScale > 1.15;
        final identity = Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    color.withValues(
                      alpha: state == _QuestVisualState.locked ? 0.10 : 0.25,
                    ),
                    color.withValues(alpha: 0.06),
                  ],
                ),
                borderRadius: BorderRadius.circular(17),
                border: Border.all(color: color.withValues(alpha: 0.12)),
              ),
              child: Icon(
                state == _QuestVisualState.claimed
                    ? Icons.verified_rounded
                    : state == _QuestVisualState.completed
                    ? Icons.check_circle_rounded
                    : state == _QuestVisualState.locked
                    ? Icons.lock_rounded
                    : icon,
                color: statusColor,
                size: 27,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    kind.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 9,
                      letterSpacing: 0.7,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: PoMarketPalette.ink,
                      fontSize: 17,
                      height: 1.12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );

        final descriptionText = Text(
          description,
          maxLines: textScale > 1.2 ? 4 : 3,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: PoMarketPalette.muted,
            fontSize: 11,
            height: 1.4,
            fontWeight: FontWeight.w600,
          ),
        );

        if (stackStatus) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              identity,
              const SizedBox(height: 10),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: ManagementStatusPill(
                  label: statusLabel,
                  color: statusColor,
                  icon: statusIcon,
                ),
              ),
              const SizedBox(height: 10),
              descriptionText,
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: identity),
                const SizedBox(width: 10),
                ManagementStatusPill(
                  label: statusLabel,
                  color: statusColor,
                  icon: statusIcon,
                ),
              ],
            ),
            const SizedBox(height: 10),
            descriptionText,
          ],
        );
      },
    );
  }
}

class _QuestActionArea extends StatelessWidget {
  const _QuestActionArea({
    required this.state,
    required this.color,
    required this.nextAction,
    required this.onClaim,
    required this.loc,
  });

  final _QuestVisualState state;
  final Color color;
  final String nextAction;
  final VoidCallback onClaim;
  final AppLocalizations loc;

  @override
  Widget build(BuildContext context) {
    if (state == _QuestVisualState.completed) {
      return Semantics(
        button: true,
        label: loc.claimReward,
        child: PressableScale(
          child: FilledButton.icon(
            key: const ValueKey('quest-claim-action'),
            onPressed: onClaim,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              backgroundColor: PoMarketPalette.forest,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
            ),
            icon: const Icon(Icons.card_giftcard_rounded, size: 19),
            label: Text(
              loc.claimReward,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      );
    }

    final (icon, label) = switch (state) {
      _QuestVisualState.locked => (Icons.lock_outline_rounded, loc.locked),
      _QuestVisualState.claimed => (Icons.verified_rounded, loc.claimed),
      _ => (
        Icons.arrow_circle_right_outlined,
        _term(
          context,
          en: 'Next action',
          he: 'הפעולה הבאה',
          ar: 'الخطوة التالية',
        ),
      ),
    };
    final detail = state == _QuestVisualState.claimed
        ? _term(
            context,
            en: 'Reward collected — this mission is complete',
            he: 'הפרס נאסף — המשימה הושלמה',
            ar: 'تم جمع المكافأة — اكتملت المهمة',
          )
        : state == _QuestVisualState.locked
        ? _term(
            context,
            en: 'Continue progressing to unlock this mission',
            he: 'המשיכו להתקדם כדי לפתוח את המשימה',
            ar: 'واصل التقدم لفتح هذه المهمة',
          )
        : nextAction;

    return Semantics(
      label: '$label. $detail',
      child: PremiumSurface(
        color: color.withValues(alpha: 0.055),
        borderColor: color.withValues(alpha: 0.17),
        elevation: 0,
        radius: 15,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 19),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: color,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    detail,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: PoMarketPalette.ink,
                      fontSize: 11,
                      height: 1.3,
                      fontWeight: FontWeight.w700,
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

class _CompletionSparkles extends StatelessWidget {
  const _CompletionSparkles();

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: 0.42,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.auto_awesome_rounded, color: PoMarketPalette.gold, size: 15),
          SizedBox(width: 3),
          Icon(Icons.star_rounded, color: PoMarketPalette.mint, size: 11),
        ],
      ),
    );
  }
}

String _term(
  BuildContext context, {
  required String en,
  required String he,
  required String ar,
}) => switch (Localizations.localeOf(context).languageCode) {
  'he' => he,
  'ar' => ar,
  _ => en,
};
