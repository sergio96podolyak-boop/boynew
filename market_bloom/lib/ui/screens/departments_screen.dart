import 'package:flutter/material.dart';

import '../../game/game_controller.dart';
import '../../game/game_models.dart';
import '../../services/app_localizations.dart';
import '../widgets/pressable_scale.dart';

class DepartmentsScreen extends StatelessWidget {
  const DepartmentsScreen({super.key, required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(loc.departmentsTitle)),
      body: AnimatedBuilder(
        animation: controller,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: [
            _OperationsHeader(controller: controller, loc: loc),
            const SizedBox(height: 20),
            Text(
              loc.departmentMilestones,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 4),
            Text(
              loc.departmentOperationsSubtitle,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),
            for (final definition in DepartmentCatalog.all) ...[
              _DepartmentCard(
                key: ValueKey('department-card-${definition.type.name}'),
                definition: definition,
                controller: controller,
                loc: loc,
              ),
              const SizedBox(height: 14),
            ],
          ],
        ),
      ),
    );
  }
}

class _OperationsHeader extends StatelessWidget {
  const _OperationsHeader({required this.controller, required this.loc});

  final GameController controller;
  final AppLocalizations loc;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF163F35), Color(0xFF237A5A), Color(0xFF46B981)],
        ),
        borderRadius: BorderRadius.circular(30),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33237A5A),
            blurRadius: 22,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0x55FFFFFF)),
                ),
                child: const Icon(
                  Icons.dashboard_customize_rounded,
                  color: Colors.white,
                  size: 29,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      loc.departmentOperations,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      '${loc.level} ${controller.storeLevel}',
                      style: const TextStyle(
                        color: Color(0xD9FFFFFF),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFD46B),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${controller.activeDepartmentCount}/${DepartmentType.values.length}',
                  style: const TextStyle(
                    color: Color(0xFF163F35),
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _HeaderMetric(
                icon: Icons.store_mall_directory_rounded,
                label: loc.activeDepartments,
                value: '${controller.activeDepartmentCount}',
              ),
              _HeaderMetric(
                icon: Icons.inventory_2_rounded,
                label: loc.floorStock,
                value: '${controller.totalShelfInventory}',
              ),
              _HeaderMetric(
                icon: Icons.trending_up_rounded,
                label: loc.salesBoost,
                value: '+${controller.departmentSalesBonus}',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeaderMetric extends StatelessWidget {
  const _HeaderMetric({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 96),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0x33FFFFFF)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: const Color(0xFFFFD46B), size: 18),
          const SizedBox(width: 7),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: Color(0xCFFFFFFF),
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ],
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
    final pending = controller.hasPendingDepartmentDelivery(definition.type);
    final selected =
        controller.selectedRestockDepartment == definition.type && unlocked;
    final background = unlocked
        ? definition.color
        : Theme.of(context).colorScheme.surfaceContainerHighest;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(27),
          border: Border.all(
            color: unlocked
                ? definition.color.withValues(alpha: 0.38)
                : Theme.of(context).colorScheme.outlineVariant,
            width: unlocked ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: unlocked
                  ? definition.color.withValues(alpha: 0.16)
                  : const Color(0x10000000),
              blurRadius: 18,
              offset: const Offset(0, 7),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(17),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: unlocked
                      ? [
                          background,
                          Color.lerp(background, Colors.black, 0.18)!,
                        ]
                      : [
                          background,
                          Theme.of(context).colorScheme.surfaceContainer,
                        ],
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 66,
                    height: 66,
                    decoration: BoxDecoration(
                      color: unlocked
                          ? Colors.white.withValues(alpha: 0.18)
                          : Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: unlocked
                            ? const Color(0x55FFFFFF)
                            : Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: unlocked
                        ? Text(
                            definition.emoji,
                            style: const TextStyle(fontSize: 31),
                          )
                        : Icon(
                            Icons.lock_rounded,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                            size: 29,
                          ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _nameFor(definition.type, loc),
                          style: TextStyle(
                            color: unlocked
                                ? Colors.white
                                : Theme.of(context).colorScheme.onSurface,
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _descriptionFor(definition.type, loc),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: unlocked
                                ? Colors.white.withValues(alpha: 0.84)
                                : Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _StatusPill(
                    unlocked: unlocked,
                    text: unlocked
                        ? '${loc.unlocked} · ${loc.level} ${state.level}'
                        : loc.locked,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(17),
              child: unlocked
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: _StockProgress(
                                color: definition.color,
                                value: stock,
                                capacity: capacity,
                                label: loc.floorStock,
                              ),
                            ),
                            const SizedBox(width: 14),
                            _LevelBadge(level: state.level),
                          ],
                        ),
                        const SizedBox(height: 15),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _DataChip(
                              icon: Icons.warehouse_rounded,
                              label: loc.warehouseStock,
                              value: '$storage',
                              color: const Color(0xFFF0A12B),
                            ),
                            _DataChip(
                              icon: Icons.sell_rounded,
                              label: loc.profitPerItem,
                              value:
                                  '${controller.departmentItemPrice(definition.type)}',
                              color: const Color(0xFF37A877),
                            ),
                            _DataChip(
                              icon: Icons.shopping_basket_rounded,
                              label: loc.itemsSold,
                              value: '${state.itemsSold}',
                              color: definition.color,
                            ),
                          ],
                        ),
                        const SizedBox(height: 15),
                        Wrap(
                          spacing: 9,
                          runSpacing: 9,
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
                              color: const Color(0xFFF0A12B),
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
                              label:
                                  '${loc.upgradeDepartment} · ${controller.departmentUpgradeCost(definition.type)}',
                              color: const Color(0xFF7658C8),
                              filled: false,
                              onPressed:
                                  state.level < 10 &&
                                      controller.coins >=
                                          controller.departmentUpgradeCost(
                                            definition.type,
                                          )
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
    );
  }

  void _unlock(BuildContext context) {
    if (!controller.unlockDepartment(definition.type)) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${_nameFor(definition.type, loc)} — ${loc.starterStockAdded}',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _upgrade(BuildContext context) {
    if (!controller.upgradeDepartment(definition.type)) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${_nameFor(definition.type, loc)} — ${loc.departmentUpgraded}',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _order(BuildContext context) {
    if (controller.placeDepartmentOrder(definition.type) == null) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(loc.quickRestockOrdered),
        behavior: SnackBarBehavior.floating,
      ),
    );
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
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.unlocked, required this.text});

  final bool unlocked;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: unlocked
            ? Colors.white.withValues(alpha: 0.18)
            : Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: unlocked
              ? Colors.white
              : Theme.of(context).colorScheme.onSurfaceVariant,
          fontSize: 9,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _StockProgress extends StatelessWidget {
  const _StockProgress({
    required this.color,
    required this.value,
    required this.capacity,
    required this.label,
  });

  final Color color;
  final int value;
  final int capacity;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Text(
              '$value/$capacity',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ],
        ),
        const SizedBox(height: 7),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: capacity == 0 ? 0 : value / capacity,
            minHeight: 9,
            color: color,
            backgroundColor: color.withValues(alpha: 0.13),
          ),
        ),
      ],
    );
  }
}

class _LevelBadge extends StatelessWidget {
  const _LevelBadge({required this.level});

  final int level;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFEEE8FF),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Text(
        '${loc.level} $level',
        style: const TextStyle(
          color: Color(0xFF6548B5),
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _DataChip extends StatelessWidget {
  const _DataChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 6),
          Text(
            '$label $value',
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
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
          backgroundColor: filled ? color : color.withValues(alpha: 0.11),
          foregroundColor: filled ? Colors.white : color,
          disabledBackgroundColor: color.withValues(alpha: 0.07),
          disabledForegroundColor: color.withValues(alpha: 0.45),
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
          visualDensity: VisualDensity.compact,
        ),
        icon: Icon(icon, size: 17),
        label: Text(
          label,
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
          child: Text(
            meetsLevel
                ? loc.unlockCost.replaceFirst(
                    '{cost}',
                    '${definition.unlockCost}',
                  )
                : loc.unlockAtLevel.replaceFirst(
                    '{level}',
                    '${definition.unlockLevel}',
                  ),
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        if (meetsLevel)
          FilledButton.icon(
            onPressed: onUnlock,
            icon: const Icon(Icons.add_business_rounded, size: 18),
            label: Text(
              '${definition.unlockCost}',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          )
        else
          Text(
            '${loc.level} ${definition.unlockLevel}',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w900,
            ),
          ),
      ],
    );
  }
}
