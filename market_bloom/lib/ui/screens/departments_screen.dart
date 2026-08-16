import 'package:flutter/material.dart';

import '../../game/economy_calculator.dart';
import '../../game/game_controller.dart';
import '../../game/game_models.dart';
import '../../services/app_localizations.dart';
import '../widgets/management_ui.dart';
import '../widgets/premium_ui.dart';
import '../widgets/pressable_scale.dart';

class DepartmentsScreen extends StatelessWidget {
  const DepartmentsScreen({super.key, required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return ManagementScaffold(
      title: loc.departmentsTitle,
      icon: Icons.grid_view_rounded,
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: [
            ManagementHero(
              icon: Icons.dashboard_customize_rounded,
              title: loc.departmentOperations,
              subtitle: '${loc.level} ${controller.storeLevel}',
              metrics: [
                ManagementHeroMetric(
                  icon: Icons.store_mall_directory_rounded,
                  label: loc.activeDepartments,
                  value:
                      '${controller.activeDepartmentCount}/${DepartmentType.values.length}',
                ),
                ManagementHeroMetric(
                  icon: Icons.inventory_2_rounded,
                  label: loc.floorStock,
                  value: '${controller.totalShelfInventory}',
                ),
                ManagementHeroMetric(
                  icon: Icons.trending_up_rounded,
                  label: loc.salesBoost,
                  value: '+${controller.departmentSalesBonus}',
                ),
              ],
            ),
            const SizedBox(height: 22),
            ManagementSectionTitle(
              title: loc.departmentMilestones,
              subtitle: loc.departmentOperationsSubtitle,
            ),
            const SizedBox(height: 12),
            ManagementResponsiveWrap(
              children: [
                for (final definition in DepartmentCatalog.all)
                  _DepartmentCard(
                    key: ValueKey(
                      'department-card-${definition.type.name}',
                    ),
                    definition: definition,
                    controller: controller,
                    loc: loc,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DepartmentCard extends StatelessWidget {
  const _DepartmentCard({
    super.key,
    required this.definition,
    required this.controller,
    required this.loc,
  });

  final DepartmentDefinition definition;
  final GameController controller;
  final AppLocalizations loc;

  @override
  Widget build(BuildContext context) {
    final state = controller.departments.firstWhere(
      (department) => department.type == definition.type,
      orElse: () => DepartmentState(type: definition.type),
    );
    final unlocked = state.unlocked;
    final meetsLevel = controller.storeLevel >= definition.unlockLevel;
    final canUnlock =
        !unlocked && meetsLevel && controller.coins >= definition.unlockCost;
    final stock = controller.departmentStock(definition.type);
    final capacity = controller.departmentCapacity(definition.type);
    final storage = controller.departmentStorage(definition.type);
    final price = controller.departmentItemPrice(definition.type);
    final orderRevenue = EconomyCalculator.grossRevenueForOrder(
      definition,
      sellingPrice: price,
    );
    final orderProfit = EconomyCalculator.grossProfitForOrder(
      definition,
      sellingPrice: price,
    );
    final profitPerItem = EconomyCalculator.estimatedProfitPerItem(
      definition,
      sellingPrice: price,
    );
    final margin = EconomyCalculator.grossMargin(
      definition,
      sellingPrice: price,
    );
    final demand = controller.departmentDemand(definition.type);
    final upgradeCost = controller.departmentUpgradeCost(definition.type);
    final pending = controller.hasPendingDepartmentDelivery(definition.type);
    final selected =
        controller.selectedRestockDepartment == definition.type && unlocked;
    final upgradeable = unlocked && state.level < 10;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: Colors.transparent,
      child: ManagementCard(
        accent: definition.color,
        highlighted: unlocked,
        muted: !unlocked,
        padding: EdgeInsets.zero,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(23),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: unlocked
                      ? LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            definition.color,
                            Color.lerp(definition.color, Colors.black, 0.24)!,
                          ],
                        )
                      : const LinearGradient(
                          colors: [Color(0xFFE8EAE5), Color(0xFFDADFD8)],
                        ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 60,
                      height: 60,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: unlocked
                            ? Colors.white.withValues(alpha: 0.17)
                            : Colors.white.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(19),
                        border: Border.all(
                          color: unlocked
                              ? const Color(0x44FFFFFF)
                              : PoMarketPalette.line,
                        ),
                      ),
                      child: unlocked
                          ? Text(
                              definition.emoji,
                              style: const TextStyle(fontSize: 29),
                            )
                          : const Icon(
                              Icons.lock_rounded,
                              color: PoMarketPalette.muted,
                              size: 27,
                            ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _nameFor(definition.type, loc),
                            style: TextStyle(
                              color: unlocked
                                  ? Colors.white
                                  : PoMarketPalette.ink,
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            _descriptionFor(definition.type, loc),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: unlocked
                                  ? Colors.white.withValues(alpha: 0.82)
                                  : PoMarketPalette.muted,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    ManagementStatusPill(
                      label: unlocked
                          ? '${loc.unlocked} · ${loc.level} ${state.level}'
                          : loc.locked,
                      color: unlocked
                          ? Colors.white
                          : PoMarketPalette.muted,
                      icon: unlocked
                          ? Icons.check_circle_rounded
                          : Icons.lock_rounded,
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: unlocked
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            loc.floorStock,
                                            style: const TextStyle(
                                              color: PoMarketPalette.muted,
                                              fontSize: 10,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ),
                                        Text(
                                          '$stock/$capacity',
                                          style: const TextStyle(
                                            color: PoMarketPalette.ink,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(999),
                                      child: LinearProgressIndicator(
                                        value: capacity <= 0
                                            ? 0
                                            : (stock / capacity).clamp(0, 1),
                                        minHeight: 8,
                                        color: definition.color,
                                        backgroundColor: definition.color
                                            .withValues(alpha: 0.11),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              ManagementStatusPill(
                                label: '${loc.level} ${state.level}',
                                color: PoMarketPalette.violet,
                                icon: Icons.stars_rounded,
                              ),
                            ],
                          ),
                          const SizedBox(height: 13),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              ManagementInfoTile(
                                icon: Icons.warehouse_rounded,
                                label: loc.warehouseStock,
                                value: '$storage',
                                color: PoMarketPalette.gold,
                              ),
                              ManagementInfoTile(
                                icon: Icons.local_fire_department_rounded,
                                label: loc.demand,
                                value: '${(demand * 100).round()}%',
                                color: definition.color,
                              ),
                              ManagementInfoTile(
                                icon: Icons.payments_rounded,
                                label: _term(
                                  context,
                                  en: 'Order revenue',
                                  he: 'הכנסה להזמנה',
                                  ar: 'إيراد الطلب',
                                ),
                                value: '$orderRevenue',
                                color: PoMarketPalette.blue,
                              ),
                              ManagementInfoTile(
                                icon: orderProfit < 0
                                    ? Icons.trending_down_rounded
                                    : Icons.trending_up_rounded,
                                label: _term(
                                  context,
                                  en: 'Order profit',
                                  he: 'רווח להזמנה',
                                  ar: 'ربح الطلب',
                                ),
                                value: '$orderProfit',
                                color: PoMarketPalette.mint,
                                negative: orderProfit < 0,
                              ),
                              // Keep the established localized presentation;
                              // tests and players already know this as "Value".
                              ManagementInfoTile(
                                icon: Icons.sell_rounded,
                                label: loc.estimatedProfit,
                                value: '$profitPerItem',
                                color: PoMarketPalette.mint,
                                negative: profitPerItem < 0,
                              ),
                              ManagementInfoTile(
                                icon: Icons.percent_rounded,
                                label: _term(
                                  context,
                                  en: 'Margin',
                                  he: 'מרווח',
                                  ar: 'الهامش',
                                ),
                                value: '${(margin * 100).round()}%',
                                color: PoMarketPalette.violet,
                                negative: margin < 0,
                              ),
                            ],
                          ),
                          const SizedBox(height: 13),
                          Container(
                            padding: const EdgeInsets.all(11),
                            decoration: BoxDecoration(
                              color: PoMarketPalette.violet.withValues(
                                alpha: 0.08,
                              ),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: PoMarketPalette.violet.withValues(
                                  alpha: 0.16,
                                ),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.auto_graph_rounded,
                                  color: PoMarketPalette.violet,
                                  size: 19,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    upgradeable
                                        ? _term(
                                            context,
                                            en: 'Next upgrade: +2 floor capacity and stronger department contribution.',
                                            he: 'השדרוג הבא: ‎+2 קיבולת מדף ותרומה חזקה יותר של המחלקה.',
                                            ar: 'الترقية التالية: +2 سعة عرض ومساهمة أقوى للقسم.',
                                          )
                                        : loc.maxLevel,
                                    style: const TextStyle(
                                      color: PoMarketPalette.ink,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                if (upgradeable)
                                  Text(
                                    '$upgradeCost',
                                    style: const TextStyle(
                                      color: PoMarketPalette.violet,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _ActionButton(
                                icon: selected
                                    ? Icons.check_circle_rounded
                                    : Icons.inventory_rounded,
                                label: selected
                                    ? loc.crateSelected
                                    : loc.prepareCrate,
                                color: definition.color,
                                filled: selected,
                                onPressed: selected
                                    ? null
                                    : () => controller.selectRestockDepartment(
                                        definition.type,
                                      ),
                              ),
                              _ActionButton(
                                icon: pending
                                    ? Icons.local_shipping_rounded
                                    : Icons.add_shopping_cart_rounded,
                                label: pending
                                    ? loc.deliveryInTransit
                                    : '${loc.orderCategoryStock} · ${definition.orderCost}',
                                color: PoMarketPalette.gold,
                                filled: false,
                                onPressed:
                                    controller.canOrderDepartmentStock(
                                      definition.type,
                                    )
                                    ? () => _order(context)
                                    : null,
                              ),
                              _ActionButton(
                                icon: Icons.upgrade_rounded,
                                label: upgradeable
                                    ? '${loc.upgradeDepartment} · $upgradeCost'
                                    : loc.maxLevel,
                                color: PoMarketPalette.violet,
                                filled: false,
                                onPressed:
                                    upgradeable &&
                                        controller.coins >= upgradeCost
                                    ? () => _upgrade(context)
                                    : null,
                              ),
                            ],
                          ),
                        ],
                      )
                    : _LockedPanel(
                        definition: definition,
                        loc: loc,
                        meetsLevel: meetsLevel,
                        onUnlock: canUnlock ? () => _unlock(context) : null,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _unlock(BuildContext context) {
    if (!controller.unlockDepartment(definition.type)) return;
    _message(
      context,
      '${_nameFor(definition.type, loc)} — ${loc.starterStockAdded}',
    );
  }

  void _upgrade(BuildContext context) {
    if (!controller.upgradeDepartment(definition.type)) return;
    _message(
      context,
      '${_nameFor(definition.type, loc)} — ${loc.departmentUpgraded}',
    );
  }

  void _order(BuildContext context) {
    if (controller.placeDepartmentOrder(definition.type) == null) return;
    _message(context, loc.quickRestockOrdered);
  }

  void _message(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.filled,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final Color color;
  final bool filled;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      enabled: onPressed != null,
      child: FilledButton.icon(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          minimumSize: const Size(44, 44),
          backgroundColor: filled ? color : color.withValues(alpha: 0.10),
          foregroundColor: filled ? Colors.white : color,
          disabledBackgroundColor: color.withValues(alpha: 0.06),
          disabledForegroundColor: color.withValues(alpha: 0.42),
        ),
        icon: Icon(icon, size: 17),
        label: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900),
        ),
      ),
    );
  }
}

class _LockedPanel extends StatelessWidget {
  const _LockedPanel({
    required this.definition,
    required this.loc,
    required this.meetsLevel,
    required this.onUnlock,
  });

  final DepartmentDefinition definition;
  final AppLocalizations loc;
  final bool meetsLevel;
  final VoidCallback? onUnlock;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          meetsLevel ? Icons.payments_rounded : Icons.lock_clock_rounded,
          color: definition.color,
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                meetsLevel
                    ? loc.unlockCost.replaceFirst(
                        '{cost}',
                        '${definition.unlockCost}',
                      )
                    : loc.unlockAtLevel.replaceFirst(
                        '{level}',
                        '${definition.unlockLevel}',
                      ),
                style: const TextStyle(
                  color: PoMarketPalette.ink,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                _term(
                  context,
                  en: 'Unlocks a new product line, demand and upgrade path.',
                  he: 'פותח קו מוצרים, ביקוש ומסלול שדרוג חדש.',
                  ar: 'يفتح خط منتجات وطلباً ومسار ترقيات جديداً.',
                ),
                style: const TextStyle(
                  color: PoMarketPalette.muted,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
        if (meetsLevel)
          FilledButton.icon(
            onPressed: onUnlock,
            icon: const Icon(Icons.add_business_rounded, size: 18),
            label: Text('${definition.unlockCost}'),
          )
        else
          ManagementStatusPill(
            label: '${loc.level} ${definition.unlockLevel}',
            color: PoMarketPalette.muted,
            icon: Icons.lock_clock_rounded,
          ),
      ],
    );
  }
}

String _nameFor(DepartmentType type, AppLocalizations loc) {
  return switch (type) {
    DepartmentType.generalGoods => loc.departmentGeneralGoods,
    DepartmentType.bakery => loc.departmentBakery,
    DepartmentType.produce => loc.departmentProduce,
    DepartmentType.refrigerated => loc.departmentRefrigerated,
    DepartmentType.beauty => loc.departmentBeauty,
    DepartmentType.electronics => loc.departmentElectronics,
  };
}

String _descriptionFor(DepartmentType type, AppLocalizations loc) {
  return switch (type) {
    DepartmentType.generalGoods => loc.departmentGeneralGoodsDesc,
    DepartmentType.bakery => loc.departmentBakeryDesc,
    DepartmentType.produce => loc.departmentProduceDesc,
    DepartmentType.refrigerated => loc.departmentRefrigeratedDesc,
    DepartmentType.beauty => loc.departmentBeautyDesc,
    DepartmentType.electronics => loc.departmentElectronicsDesc,
  };
}

String _term(
  BuildContext context, {
  required String en,
  required String he,
  required String ar,
}) {
  return switch (Localizations.localeOf(context).languageCode) {
    'he' => he,
    'ar' => ar,
    _ => en,
  };
}
