import 'package:flutter/material.dart';

import '../../game/game_controller.dart';
import '../../game/meta_models.dart';
import '../../services/app_localizations.dart';
import '../widgets/management_ui.dart';
import '../widgets/premium_ui.dart';
import '../widgets/pressable_scale.dart';

class AchievementsScreen extends StatelessWidget {
  const AchievementsScreen({super.key, required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return ManagementScaffold(
      title: loc.achievementsTitle,
      icon: Icons.emoji_events_rounded,
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final definitions = AchievementCatalog.all;
          final total = definitions.length;
          final unlocked = controller.unlockedAchievementCount;
          if (total == 0) {
            return Center(
              child: ManagementCard(
                child: Text(
                  loc.noAchievementsYet,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: PoMarketPalette.muted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            );
          }

          final completion = unlocked / total;
          final inProgress = definitions.where((definition) {
            final progress = controller.progressFor(definition);
            return !progress.isUnlocked && progress.currentValue > 0;
          }).length;
          final remaining = total - unlocked;

          return FocusTraversalGroup(
            policy: OrderedTraversalPolicy(),
            child: ListView(
              padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 28),
              children: [
                ManagementHero(
                  icon: Icons.workspace_premium_rounded,
                  title: loc.achievementsTitle,
                  subtitle: _term(
                    context,
                    en: 'Build a premium collection by reaching meaningful business milestones',
                    he: 'בנו אוסף יוקרתי באמצעות השגת אבני דרך עסקיות משמעותיות',
                    ar: 'ابنِ مجموعة مميزة عبر تحقيق مراحل عمل مهمة',
                  ),
                  colors: const [Color(0xFF2C1470), Color(0xFF6234E0)],
                  metrics: [
                    ManagementHeroMetric(
                      icon: Icons.emoji_events_rounded,
                      label: loc.unlockedLabel,
                      value: '$unlocked/$total',
                    ),
                    ManagementHeroMetric(
                      icon: Icons.trending_up_rounded,
                      label: _term(
                        context,
                        en: 'In progress',
                        he: 'בתהליך',
                        ar: 'قيد التقدم',
                      ),
                      value: '$inProgress',
                    ),
                    ManagementHeroMetric(
                      icon: Icons.percent_rounded,
                      label: _term(
                        context,
                        en: 'Completion',
                        he: 'השלמה',
                        ar: 'الإنجاز',
                      ),
                      value: '${(completion * 100).round()}%',
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _AchievementSummary(
                  unlocked: unlocked,
                  inProgress: inProgress,
                  remaining: remaining,
                  total: total,
                  fraction: completion,
                  loc: loc,
                ),
                const SizedBox(height: 22),
                for (final tier in AchievementTier.values) ...[
                  _AchievementTierSection(
                    tier: tier,
                    definitions: definitions
                        .where((definition) => definition.tier == tier)
                        .toList(growable: false),
                    controller: controller,
                    loc: loc,
                  ),
                  if (tier != AchievementTier.values.last)
                    const SizedBox(height: 22),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _AchievementSummary extends StatelessWidget {
  const _AchievementSummary({
    required this.unlocked,
    required this.inProgress,
    required this.remaining,
    required this.total,
    required this.fraction,
    required this.loc,
  });

  final int unlocked;
  final int inProgress;
  final int remaining;
  final int total;
  final double fraction;
  final AppLocalizations loc;

  @override
  Widget build(BuildContext context) {
    final completed = unlocked == total;
    return Semantics(
      key: const ValueKey('achievements-summary'),
      container: true,
      label: _term(
        context,
        en: 'Achievement progression summary',
        he: 'סיכום התקדמות הישגים',
        ar: 'ملخص تقدم الإنجازات',
      ),
      value: '$unlocked / $total',
      child: ManagementCard(
        accent: completed ? PoMarketPalette.mint : PoMarketPalette.gold,
        highlighted: completed,
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: PoMarketPalette.gold.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: const Icon(
                    Icons.military_tech_rounded,
                    color: PoMarketPalette.gold,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$unlocked/$total ${loc.badgesUnlocked}',
                        style: const TextStyle(
                          color: PoMarketPalette.ink,
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        completed
                            ? _term(
                                context,
                                en: 'Collection complete — every milestone is yours.',
                                he: 'האוסף הושלם — כל אבני הדרך שלך.',
                                ar: 'اكتملت المجموعة — جميع المراحل أصبحت لك.',
                              )
                            : _term(
                                context,
                                en: 'Keep progressing to complete the full badge collection.',
                                he: 'המשיכו להתקדם כדי להשלים את אוסף התגים.',
                                ar: 'واصل التقدم لإكمال مجموعة الشارات.',
                              ),
                        style: const TextStyle(
                          color: PoMarketPalette.muted,
                          fontSize: 10,
                          height: 1.3,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                ManagementStatusPill(
                  label: '${(fraction * 100).round()}%',
                  color: completed
                      ? PoMarketPalette.mint
                      : PoMarketPalette.gold,
                  icon: completed
                      ? Icons.verified_rounded
                      : Icons.insights_rounded,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Semantics(
              label: _term(
                context,
                en: 'Achievement completion',
                he: 'השלמת הישגים',
                ar: 'إكمال الإنجازات',
              ),
              value: '${(fraction * 100).round()}%',
              child: ExcludeSemantics(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: fraction,
                    minHeight: 9,
                    color: completed
                        ? PoMarketPalette.mint
                        : PoMarketPalette.gold,
                    backgroundColor: PoMarketPalette.gold.withValues(
                      alpha: 0.12,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ManagementInfoTile(
                  label: _term(
                    context,
                    en: 'Completed',
                    he: 'הושלמו',
                    ar: 'مكتملة',
                  ),
                  value: '$unlocked',
                  icon: Icons.emoji_events_rounded,
                  color: PoMarketPalette.mint,
                ),
                ManagementInfoTile(
                  label: _term(
                    context,
                    en: 'In progress',
                    he: 'בתהליך',
                    ar: 'قيد التقدم',
                  ),
                  value: '$inProgress',
                  icon: Icons.trending_up_rounded,
                  color: PoMarketPalette.blue,
                ),
                ManagementInfoTile(
                  label: _term(
                    context,
                    en: 'Remaining',
                    he: 'נותרו',
                    ar: 'متبقية',
                  ),
                  value: '$remaining',
                  icon: Icons.flag_outlined,
                  color: PoMarketPalette.violet,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AchievementTierSection extends StatelessWidget {
  const _AchievementTierSection({
    required this.tier,
    required this.definitions,
    required this.controller,
    required this.loc,
  });

  final AchievementTier tier;
  final List<AchievementDefinition> definitions;
  final GameController controller;
  final AppLocalizations loc;

  @override
  Widget build(BuildContext context) {
    if (definitions.isEmpty) return const SizedBox.shrink();
    final color = _tierColor(tier);
    final completed = definitions
        .where((definition) => controller.progressFor(definition).isUnlocked)
        .length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ManagementSectionTitle(
          title: _tierLabel(context, tier),
          subtitle: _tierDescription(context, tier),
          trailing: ManagementStatusPill(
            label: '$completed/${definitions.length}',
            color: color,
            icon: Icons.workspace_premium_rounded,
          ),
        ),
        const SizedBox(height: 12),
        ManagementResponsiveWrap(
          children: [
            for (var index = 0; index < definitions.length; index++)
              FocusTraversalOrder(
                order: NumericFocusOrder(
                  AchievementTier.values.indexOf(tier) * 100 + index + 1,
                ),
                child: _AchievementCard(
                  key: ValueKey('achievement-card-${definitions[index].id}'),
                  definition: definitions[index],
                  progress: controller.progressFor(definitions[index]),
                  loc: loc,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

enum _AchievementVisualState { locked, available, completed }

class _AchievementCard extends StatefulWidget {
  const _AchievementCard({
    super.key,
    required this.definition,
    required this.progress,
    required this.loc,
  });

  final AchievementDefinition definition;
  final AchievementProgress progress;
  final AppLocalizations loc;

  @override
  State<_AchievementCard> createState() => _AchievementCardState();
}

class _AchievementCardState extends State<_AchievementCard> {
  bool _focused = false;

  _AchievementVisualState get state {
    if (widget.progress.isUnlocked) return _AchievementVisualState.completed;
    if (widget.progress.currentValue > 0) {
      return _AchievementVisualState.available;
    }
    return _AchievementVisualState.locked;
  }

  @override
  Widget build(BuildContext context) {
    final visualState = state;
    final completed = visualState == _AchievementVisualState.completed;
    final color = _tierColor(widget.definition.tier);
    final current = widget.progress.currentValue.clamp(
      0,
      widget.definition.target,
    );
    final fraction = widget.progress.fractionFor(widget.definition);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final statusColor = switch (visualState) {
      _AchievementVisualState.locked => PoMarketPalette.muted,
      _AchievementVisualState.available => color,
      _AchievementVisualState.completed => PoMarketPalette.mint,
    };
    final statusLabel = switch (visualState) {
      _AchievementVisualState.locked => widget.loc.locked,
      _AchievementVisualState.available => _term(
        context,
        en: 'In progress',
        he: 'בתהליך',
        ar: 'قيد التقدم',
      ),
      _AchievementVisualState.completed => _term(
        context,
        en: 'Completed',
        he: 'הושלם',
        ar: 'مكتمل',
      ),
    };
    final statusIcon = switch (visualState) {
      _AchievementVisualState.locked => Icons.lock_outline_rounded,
      _AchievementVisualState.available => Icons.trending_up_rounded,
      _AchievementVisualState.completed => Icons.verified_rounded,
    };
    final semanticsValue = '$current / ${widget.definition.target}';

    return Semantics(
      container: true,
      focusable: true,
      label:
          '${widget.loc.achievementTitle(widget.definition.id)}. '
          '${widget.loc.achievementDescription(widget.definition.id)}. '
          '$statusLabel',
      value: semanticsValue,
      child: Focus(
        canRequestFocus: true,
        onFocusChange: (focused) {
          if (_focused != focused) setState(() => _focused = focused);
        },
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: completed ? 0.975 : 1, end: 1),
          duration: reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          builder: (context, scale, child) => Transform.scale(
            scale: scale,
            alignment: Alignment.center,
            child: child,
          ),
          child: PressableScale(
            child: ManagementCard(
              accent: completed ? PoMarketPalette.mint : color,
              highlighted: completed || _focused,
              muted: visualState == _AchievementVisualState.locked,
              padding: EdgeInsets.zero,
              child: Stack(
                children: [
                  if (completed)
                    const PositionedDirectional(
                      top: 12,
                      end: 14,
                      child: ExcludeSemantics(child: _AchievementSparkles()),
                    ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _AchievementHeader(
                          definition: widget.definition,
                          title: widget.loc.achievementTitle(
                            widget.definition.id,
                          ),
                          description: widget.loc.achievementDescription(
                            widget.definition.id,
                          ),
                          state: visualState,
                          tierColor: color,
                          statusColor: statusColor,
                          statusLabel: statusLabel,
                          statusIcon: statusIcon,
                        ),
                        const SizedBox(height: 14),
                        Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 8,
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
                              icon: Icons.insights_rounded,
                              color: statusColor,
                            ),
                            ManagementStatusPill(
                              label: _term(
                                context,
                                en: 'Badge ${widget.definition.badge}',
                                he: 'תג ${widget.definition.badge}',
                                ar: 'شارة ${widget.definition.badge}',
                              ),
                              color: color,
                              icon: Icons.card_giftcard_rounded,
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Semantics(
                          label: _term(
                            context,
                            en: 'Achievement progress',
                            he: 'התקדמות בהישג',
                            ar: 'تقدم الإنجاز',
                          ),
                          value: semanticsValue,
                          child: ExcludeSemantics(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(999),
                              child: LinearProgressIndicator(
                                value: fraction,
                                minHeight: 9,
                                color: completed ? PoMarketPalette.mint : color,
                                backgroundColor: color.withValues(alpha: 0.11),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 13),
                        _AchievementActionPanel(
                          state: visualState,
                          color: statusColor,
                          nextAction: _nextAction(
                            context,
                            widget.definition.metric,
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
      ),
    );
  }
}

class _AchievementHeader extends StatelessWidget {
  const _AchievementHeader({
    required this.definition,
    required this.title,
    required this.description,
    required this.state,
    required this.tierColor,
    required this.statusColor,
    required this.statusLabel,
    required this.statusIcon,
  });

  final AchievementDefinition definition;
  final String title;
  final String description;
  final _AchievementVisualState state;
  final Color tierColor;
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
            _AchievementBadge(
              badge: definition.badge,
              color: tierColor,
              completed: state == _AchievementVisualState.completed,
              locked: state == _AchievementVisualState.locked,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _tierLabel(context, definition.tier),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: tierColor,
                      fontSize: 9,
                      letterSpacing: 0.5,
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
                      fontSize: 16,
                      height: 1.15,
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
                const SizedBox(width: 8),
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

class _AchievementBadge extends StatelessWidget {
  const _AchievementBadge({
    required this.badge,
    required this.color,
    required this.completed,
    required this.locked,
  });

  final String badge;
  final Color color;
  final bool completed;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 58,
          height: 58,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: locked
                  ? const [Color(0xFFEFF2EF), Color(0xFFDCE6E0)]
                  : [
                      color.withValues(alpha: completed ? 0.92 : 0.24),
                      color.withValues(alpha: completed ? 0.62 : 0.08),
                    ],
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: color.withValues(alpha: 0.22)),
            boxShadow: completed
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.24),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : null,
          ),
          child: Opacity(
            opacity: locked ? 0.48 : 1,
            child: Text(badge, style: const TextStyle(fontSize: 27)),
          ),
        ),
        if (locked)
          PositionedDirectional(
            end: -4,
            bottom: -4,
            child: Container(
              width: 23,
              height: 23,
              decoration: BoxDecoration(
                color: PoMarketPalette.cream,
                shape: BoxShape.circle,
                border: Border.all(color: PoMarketPalette.line),
              ),
              child: const Icon(
                Icons.lock_rounded,
                color: PoMarketPalette.muted,
                size: 13,
              ),
            ),
          ),
      ],
    );
  }
}

class _AchievementActionPanel extends StatelessWidget {
  const _AchievementActionPanel({
    required this.state,
    required this.color,
    required this.nextAction,
  });

  final _AchievementVisualState state;
  final Color color;
  final String nextAction;

  @override
  Widget build(BuildContext context) {
    final completed = state == _AchievementVisualState.completed;
    final label = completed
        ? _term(
            context,
            en: 'Milestone complete',
            he: 'אבן הדרך הושלמה',
            ar: 'اكتملت المرحلة',
          )
        : _term(
            context,
            en: 'Next action',
            he: 'הפעולה הבאה',
            ar: 'الخطوة التالية',
          );
    final detail = completed
        ? _term(
            context,
            en: 'Badge unlocked and added to your achievement collection.',
            he: 'התג נפתח ונוסף לאוסף ההישגים שלך.',
            ar: 'تم فتح الشارة وإضافتها إلى مجموعة إنجازاتك.',
          )
        : nextAction;

    return PremiumSurface(
      color: color.withValues(alpha: completed ? 0.09 : 0.055),
      borderColor: color.withValues(alpha: completed ? 0.25 : 0.16),
      elevation: 0,
      radius: 15,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              completed
                  ? Icons.auto_awesome_rounded
                  : Icons.arrow_circle_right_outlined,
              color: color,
              size: 19,
            ),
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
    );
  }
}

class _AchievementSparkles extends StatelessWidget {
  const _AchievementSparkles();

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: 0.44,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(
            Icons.auto_awesome_rounded,
            color: PoMarketPalette.gold,
            size: 15,
          ),
          SizedBox(width: 3),
          Icon(Icons.star_rounded, color: PoMarketPalette.mint, size: 11),
        ],
      ),
    );
  }
}

String _nextAction(BuildContext context, AchievementMetric metric) =>
    switch (metric) {
      AchievementMetric.totalSales => _term(
        context,
        en: 'Serve more customers and complete sales at checkout',
        he: 'שרתו לקוחות נוספים והשלימו מכירות בקופה',
        ar: 'اخدم المزيد من العملاء وأكمل المبيعات عند الدفع',
      ),
      AchievementMetric.itemsStocked => _term(
        context,
        en: 'Move products from storage and keep shelves stocked',
        he: 'העבירו מוצרים מהמחסן ושמרו על מדפים מלאים',
        ar: 'انقل المنتجات من المخزن وحافظ على امتلاء الرفوف',
      ),
      AchievementMetric.totalCoinsEarned => _term(
        context,
        en: 'Keep selling products to grow total coin earnings',
        he: 'המשיכו למכור מוצרים כדי להגדיל את סך ההכנסות',
        ar: 'واصل بيع المنتجات لزيادة إجمالي الأرباح',
      ),
      AchievementMetric.upgradesPurchased => _term(
        context,
        en: 'Purchase business upgrades from the Upgrades screen',
        he: 'רכשו שדרוגים עסקיים ממסך השדרוגים',
        ar: 'اشترِ ترقيات العمل من شاشة الترقيات',
      ),
      AchievementMetric.storeLevel => _term(
        context,
        en: 'Grow sales and upgrades to raise the store level',
        he: 'הגדילו מכירות ושדרוגים כדי להעלות את רמת החנות',
        ar: 'زد المبيعات والترقيات لرفع مستوى المتجر',
      ),
      AchievementMetric.dailyStreak => _term(
        context,
        en: 'Open PoMarket on consecutive days to continue the streak',
        he: 'פתחו את PoMarket בימים רצופים כדי להמשיך את הרצף',
        ar: 'افتح PoMarket في أيام متتالية لمواصلة السلسلة',
      ),
      AchievementMetric.highestBalance => _term(
        context,
        en: 'Save coins and reach a higher business balance',
        he: 'חסכו מטבעות והגיעו ליתרה עסקית גבוהה יותר',
        ar: 'ادخر العملات وحقق رصيد عمل أعلى',
      ),
      AchievementMetric.totalActions => _term(
        context,
        en: 'Keep managing the market and completing useful actions',
        he: 'המשיכו לנהל את המרקט ולהשלים פעולות מועילות',
        ar: 'واصل إدارة المتجر وتنفيذ الإجراءات المفيدة',
      ),
      AchievementMetric.playTimeMinutes => _term(
        context,
        en: 'Continue playing and developing the market',
        he: 'המשיכו לשחק ולפתח את המרקט',
        ar: 'واصل اللعب وتطوير المتجر',
      ),
    };

Color _tierColor(AchievementTier tier) => switch (tier) {
  AchievementTier.bronze => const Color(0xFFB87333),
  AchievementTier.silver => const Color(0xFF7A9EBD),
  AchievementTier.gold => const Color(0xFFD98505),
  AchievementTier.platinum => const Color(0xFF4E7FA8),
};

String _tierDescription(BuildContext context, AchievementTier tier) =>
    switch (tier) {
      AchievementTier.bronze => _term(
        context,
        en: 'Early milestones that establish your market',
        he: 'אבני דרך ראשונות שמבססות את המרקט',
        ar: 'مراحل مبكرة تؤسس متجرك',
      ),
      AchievementTier.silver => _term(
        context,
        en: 'Growing-business milestones with stronger targets',
        he: 'אבני דרך לעסק צומח עם יעדים משמעותיים יותר',
        ar: 'مراحل لنمو العمل بأهداف أقوى',
      ),
      AchievementTier.gold => _term(
        context,
        en: 'Advanced milestones for committed market managers',
        he: 'אבני דרך מתקדמות למנהלי מרקט מחויבים',
        ar: 'مراحل متقدمة لمديري المتاجر الملتزمين',
      ),
      AchievementTier.platinum => _term(
        context,
        en: 'Elite milestones for a top-performing business',
        he: 'אבני דרך עילית לעסק מצטיין',
        ar: 'مراحل نخبوية لعمل عالي الأداء',
      ),
    };

String _tierLabel(BuildContext context, AchievementTier tier) => switch (tier) {
  AchievementTier.bronze => _term(
    context,
    en: 'Bronze',
    he: 'ארד',
    ar: 'برونزي',
  ),
  AchievementTier.silver => _term(context, en: 'Silver', he: 'כסף', ar: 'فضי'),
  AchievementTier.gold => _term(context, en: 'Gold', he: 'זהב', ar: 'ذهبي'),
  AchievementTier.platinum => _term(
    context,
    en: 'Platinum',
    he: 'פלטינה',
    ar: 'بلاتيني',
  ),
};

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
