import 'package:flutter/material.dart';

import '../../game/game_controller.dart';
import '../../game/game_models.dart';
import '../../services/app_localizations.dart';
import '../widgets/management_ui.dart';
import '../widgets/premium_ui.dart';
import '../widgets/pressable_scale.dart';

class UpgradesScreen extends StatelessWidget {
  const UpgradesScreen({super.key, required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return ManagementScaffold(
      title: loc.upgradeYourBusiness,
      icon: Icons.auto_awesome_rounded,
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final offers = controller.upgrades;
          final affordable = offers
              .where((offer) => controller.canBuyUpgrade(offer.type))
              .length;
          final maxed = offers.where((offer) => offer.level >= 10).length;
          return FocusTraversalGroup(
            policy: OrderedTraversalPolicy(),
            child: ListView(
              key: const ValueKey('upgrades-scroll-view'),
              padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 28),
              children: [
                ManagementHero(
                  icon: Icons.trending_up_rounded,
                  title: _t(
                    context,
                    'Grow Your Market',
                    'פתחו את המרקט',
                    'طوّر متجرك',
                  ),
                  subtitle: loc.investToServe,
                  colors: const [Color(0xFF1C3A32), Color(0xFF0C837E)],
                  metrics: [
                    ManagementHeroMetric(
                      icon: Icons.monetization_on_rounded,
                      label: loc.coinsShort,
                      value: '${controller.coins} ${loc.coinsShort}',
                    ),
                    ManagementHeroMetric(
                      icon: Icons.shopping_cart_checkout_rounded,
                      label: _t(
                        context,
                        'Affordable now',
                        'זמינים עכשיו',
                        'متاحة الآن',
                      ),
                      value: '$affordable/${offers.length}',
                    ),
                    ManagementHeroMetric(
                      icon: Icons.verified_rounded,
                      label: _t(
                        context,
                        'Max level',
                        'רמה מרבית',
                        'المستوى الأقصى',
                      ),
                      value: '$maxed/${offers.length}',
                    ),
                  ],
                ),
                const SizedBox(height: PoMarketSpacing.section),
                ManagementSectionTitle(
                  title: _t(
                    context,
                    'Business upgrades',
                    'שדרוגי העסק',
                    'ترقيات العمل',
                  ),
                  subtitle: _t(
                    context,
                    'Compare the current benefit, next level and purchase state',
                    'השוו את ההטבה הנוכחית, הרמה הבאה ומצב הרכישה',
                    'قارن الميزة الحالية والمستوى التالي وحالة الشراء',
                  ),
                  trailing: ManagementStatusPill(
                    label: '$affordable',
                    color: affordable > 0
                        ? PoMarketPalette.mint
                        : PoMarketPalette.muted,
                    icon: affordable > 0
                        ? Icons.upgrade_rounded
                        : Icons.savings_rounded,
                  ),
                ),
                const SizedBox(height: 12),
                ManagementResponsiveWrap(
                  children: [
                    for (var index = 0; index < offers.length; index++)
                      FocusTraversalOrder(
                        order: NumericFocusOrder(index + 1),
                        child: _UpgradeCard(
                          key: ValueKey(
                            'upgrade-card-${offers[index].type.name}',
                          ),
                          offer: offers[index],
                          affordable: controller.canBuyUpgrade(
                            offers[index].type,
                          ),
                          balance: controller.coins,
                          onBuy: () => _buy(context, offers[index], loc),
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

  void _buy(BuildContext context, UpgradeOffer offer, AppLocalizations loc) {
    final purchased = controller.buyUpgrade(offer.type);
    final message = purchased
        ? _t(
            context,
            '${loc.upgradeTitle(offer.type)} upgraded',
            '${loc.upgradeTitle(offer.type)} שודרג',
            'تمت ترقية ${loc.upgradeTitle(offer.type)}',
          )
        : loc.notEnoughCoins;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }
}

class _UpgradeCard extends StatelessWidget {
  const _UpgradeCard({
    super.key,
    required this.offer,
    required this.affordable,
    required this.balance,
    required this.onBuy,
  });

  final UpgradeOffer offer;
  final bool affordable;
  final int balance;
  final VoidCallback onBuy;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final maxed = offer.level >= 10;
    final color = offer.color;
    final stateColor = maxed
        ? PoMarketPalette.mint
        : affordable
        ? color
        : PoMarketPalette.muted;
    final stateLabel = maxed
        ? loc.maxLevel
        : affordable
        ? _t(context, 'Ready to buy', 'מוכן לרכישה', 'جاهزة للشراء')
        : _t(context, 'Needs more coins', 'נדרשים מטבעות', 'تحتاج عملات');
    final stateIcon = maxed
        ? Icons.verified_rounded
        : affordable
        ? Icons.lock_open_rounded
        : Icons.savings_rounded;
    final progress = (offer.level / 10).clamp(0.0, 1.0);
    final missingCoins = (offer.cost - balance).clamp(0, offer.cost);

    return Semantics(
      container: true,
      label:
          '${loc.upgradeTitle(offer.type)}. ${loc.level} ${offer.level} of 10. $stateLabel',
      child: ManagementCard(
        accent: color,
        highlighted: affordable || maxed,
        muted: !affordable && !maxed,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PremiumIconTile(icon: offer.icon, color: color),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        loc.upgradeTitle(offer.type),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: PoMarketTextStyles.cardTitle,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${loc.level} ${offer.level}/10',
                        style: PoMarketTextStyles.supporting,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                ManagementStatusPill(
                  label: stateLabel,
                  color: stateColor,
                  icon: stateIcon,
                ),
              ],
            ),
            const SizedBox(height: 13),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                color: maxed ? PoMarketPalette.mint : color,
                backgroundColor: color.withValues(alpha: 0.10),
              ),
            ),
            const SizedBox(height: 13),
            _BenefitComparison(
              current: _localizedSubtitle(loc, offer),
              next: maxed ? loc.maxLevel : _localizedNextSubtitle(loc, offer),
              color: color,
            ),
            if (!affordable && !maxed) ...[
              const SizedBox(height: 11),
              PremiumStateMessage(
                icon: Icons.monetization_on_outlined,
                color: PoMarketPalette.gold,
                message: _t(
                  context,
                  'Earn $missingCoins more coins to unlock this upgrade.',
                  'יש להרוויח עוד $missingCoins מטבעות כדי לרכוש את השדרוג.',
                  'اربح $missingCoins عملة إضافية لشراء هذه الترقية.',
                ),
              ),
            ],
            const SizedBox(height: 14),
            PressableScale(
              enabled: affordable,
              child: FilledButton.icon(
                key: ValueKey('upgrade-buy-${offer.type.name}'),
                onPressed: affordable ? onBuy : null,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  backgroundColor: color,
                  disabledBackgroundColor: maxed
                      ? PoMarketPalette.mint.withValues(alpha: 0.12)
                      : color.withValues(alpha: 0.08),
                  disabledForegroundColor: maxed
                      ? PoMarketPalette.forestLight
                      : PoMarketPalette.muted,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(PoMarketRadii.control),
                  ),
                ),
                icon: Icon(
                  maxed ? Icons.verified_rounded : Icons.upgrade_rounded,
                  size: 19,
                ),
                label: Text(
                  maxed ? loc.maxLevel : '${offer.cost} ${loc.coinsShort}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _localizedSubtitle(AppLocalizations loc, UpgradeOffer currentOffer) {
    return switch (currentOffer.type) {
      UpgradeType.bag => loc.carryProducts.replaceFirst(
        '{capacity}',
        '${3 + currentOffer.level}',
      ),
      UpgradeType.shelf => '${loc.capacity}: ${4 + currentOffer.level * 2}',
      UpgradeType.price => loc.profitPerSale.replaceFirst(
        '{value}',
        '${4 + currentOffer.level * 2}',
      ),
      UpgradeType.speed => loc.movementSpeed.replaceFirst(
        '{value}',
        '${currentOffer.level * 8}',
      ),
      UpgradeType.checkout => loc.serviceTime.replaceFirst(
        '{value}',
        currentOffer.subtitle.split('s').first,
      ),
      UpgradeType.restock => loc.keepShelvesFilled,
    };
  }

  String _localizedNextSubtitle(
    AppLocalizations loc,
    UpgradeOffer currentOffer,
  ) {
    final nextLevel = currentOffer.level + 1;
    return switch (currentOffer.type) {
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
        _nextCheckoutSeconds(currentOffer),
      ),
      UpgradeType.restock => loc.keepShelvesFilled,
    };
  }

  String _nextCheckoutSeconds(UpgradeOffer offer) {
    final current = double.tryParse(offer.subtitle.split('s').first) ?? 1;
    return current > 0.38
        ? (current - 0.09).clamp(0.38, 9.99).toStringAsFixed(2)
        : '0.38';
  }
}

class _BenefitComparison extends StatelessWidget {
  const _BenefitComparison({
    required this.current,
    required this.next,
    required this.color,
  });

  final String current;
  final String next;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return PremiumSurface(
      elevation: 0,
      radius: PoMarketRadii.control,
      color: color.withValues(alpha: 0.045),
      borderColor: color.withValues(alpha: 0.16),
      padding: const EdgeInsets.all(11),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _BenefitRow(
            label: _t(context, 'Current', 'נוכחי', 'الحالي'),
            value: current,
            icon: Icons.check_circle_outline_rounded,
            color: PoMarketPalette.muted,
          ),
          const SizedBox(height: 8),
          Divider(height: 1, color: color.withValues(alpha: 0.15)),
          const SizedBox(height: 8),
          _BenefitRow(
            label: _t(context, 'Next level', 'הרמה הבאה', 'المستوى التالي'),
            value: next,
            icon: Icons.arrow_circle_up_rounded,
            color: color,
          ),
        ],
      ),
    );
  }
}

class _BenefitRow extends StatelessWidget {
  const _BenefitRow({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: PoMarketTextStyles.overline.copyWith(color: color),
              ),
              const SizedBox(height: 2),
              Text(
                value,
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
    );
  }
}

String _t(BuildContext context, String en, String he, String ar) =>
    switch (Localizations.localeOf(context).languageCode) {
      'he' => he,
      'ar' => ar,
      _ => en,
    };
