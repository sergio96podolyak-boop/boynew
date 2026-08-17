import 'package:flutter/material.dart';

import '../../game/economy_calculator.dart';
import '../../game/game_controller.dart';
import '../../game/game_models.dart';
import '../../services/app_localizations.dart';
import '../theme/po_system.dart';
import '../widgets/management_ui.dart';
import '../widgets/premium_ui.dart';
import '../widgets/pressable_scale.dart';

class InventoryScreen extends StatelessWidget {
  const InventoryScreen({super.key, required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return ManagementScaffold(
      title: loc.inventoryTitle,
      icon: Icons.inventory_2_rounded,
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final deliveries = controller.pendingDeliveries;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            children: [
              ManagementHero(
                icon: Icons.warehouse_rounded,
                title: loc.warehouseStock,
                subtitle:
                    '${controller.activeDepartmentCount} ${loc.activeDepartments}',
                colors: const [Color(0xFF123E6B), Color(0xFF0C837E)],
                metrics: [
                  ManagementHeroMetric(
                    icon: Icons.inventory_rounded,
                    label: loc.warehouseStock,
                    value:
                        '${controller.totalStoredInventory}/${controller.storageCapacity}',
                  ),
                  ManagementHeroMetric(
                    icon: Icons.storefront_rounded,
                    label: loc.floorStock,
                    value: '${controller.totalShelfInventory}',
                  ),
                  ManagementHeroMetric(
                    icon: Icons.local_shipping_rounded,
                    label: loc.pendingDeliveries,
                    value: '${deliveries.length}',
                  ),
                ],
              ),
              const SizedBox(height: 22),
              ManagementSectionTitle(
                title: loc.activeDepartments,
                subtitle: _term(
                  context,
                  en: 'Live stock, pricing and reorder status',
                  he: 'מלאי, תמחור ומצב הזמנות בזמן אמת',
                  ar: 'المخزون والتسعير وحالة الطلبات',
                ),
              ),
              const SizedBox(height: 12),
              ManagementResponsiveWrap(
                children: [
                  for (final definition in DepartmentCatalog.all)
                    if (controller.isDepartmentUnlocked(definition.type))
                      _ProductCard(
                        key: ValueKey('inventory-card-${definition.type.name}'),
                        definition: definition,
                        controller: controller,
                        loc: loc,
                      ),
                ],
              ),
              const SizedBox(height: 24),
              ManagementSectionTitle(
                title: loc.pendingDeliveries,
                subtitle: deliveries.isEmpty ? loc.noPendingDeliveries : null,
                trailing: deliveries.isEmpty
                    ? null
                    : ManagementStatusPill(
                        label: '${deliveries.length}',
                        color: PoMarketPalette.blue,
                        icon: Icons.local_shipping_rounded,
                      ),
              ),
              const SizedBox(height: 10),
              if (deliveries.isEmpty)
                ManagementCard(
                  child: Row(
                    children: [
                      const Icon(
                        Icons.task_alt_rounded,
                        color: PoMarketPalette.mint,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          loc.noPendingDeliveries,
                          style: const TextStyle(
                            color: PoMarketPalette.muted,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else
                ManagementResponsiveWrap(
                  children: [
                    for (final delivery in deliveries)
                      _DeliveryCard(
                        delivery: delivery,
                        loc: loc,
                        ready: controller.isDeliveryReady(delivery),
                        onFulfill: () =>
                            controller.fulfillPendingDelivery(delivery.id),
                      ),
                  ],
                ),
              if (controller.canClaimEmergencyStock) ...[
                const SizedBox(height: 16),
                _EmergencyStockCard(controller: controller, loc: loc),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({
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
    final shelf = controller.departmentStock(definition.type);
    final capacity = controller.departmentCapacity(definition.type);
    final storage = controller.departmentStorage(definition.type);
    final price = controller.departmentItemPrice(definition.type);
    final unitCost = EconomyCalculator.unitCost(definition);
    final profit = EconomyCalculator.estimatedProfitPerItem(
      definition,
      sellingPrice: price,
    );
    final margin = EconomyCalculator.grossMargin(
      definition,
      sellingPrice: price,
    );
    final demand = controller.departmentDemand(definition.type);
    final pending = controller.hasPendingDepartmentDelivery(definition.type);
    final selected = controller.selectedRestockDepartment == definition.type;
    final totalStock = shelf + storage;
    final lowStock = totalStock <= max(2, definition.orderQuantity ~/ 2);
    final statusColor = pending
        ? PoMarketPalette.blue
        : lowStock
        ? PoMarketPalette.coral
        : PoMarketPalette.mint;
    final statusLabel = pending
        ? loc.deliveryInTransit
        : lowStock
        ? loc.lowStock
        : _term(
            context,
            en: 'Stock healthy',
            he: 'מלאי תקין',
            ar: 'المخزون جيد',
          );

    return ManagementCard(
      accent: definition.color,
      highlighted: selected || lowStock,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 54,
                height: 54,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      definition.color.withValues(alpha: 0.24),
                      definition.color.withValues(alpha: 0.08),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(17),
                ),
                child: Text(
                  definition.emoji,
                  style: const TextStyle(fontSize: 27),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _departmentName(definition.type, loc),
                      style: const TextStyle(
                        color: PoMarketPalette.ink,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      definition.category,
                      style: const TextStyle(
                        color: PoMarketPalette.muted,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              ManagementStatusPill(
                label: statusLabel,
                color: statusColor,
                icon: pending
                    ? Icons.local_shipping_rounded
                    : lowStock
                    ? Icons.warning_amber_rounded
                    : Icons.check_circle_rounded,
              ),
            ],
          ),
          const SizedBox(height: 14),
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
                            '${loc.floorStock} $shelf/$capacity · ${loc.warehouseStock} $storage',
                            style: const TextStyle(
                              color: PoMarketPalette.muted,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        Text(
                          '$totalStock',
                          style: TextStyle(
                            color: lowStock
                                ? PoMarketPalette.coral
                                : PoMarketPalette.ink,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 7),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: capacity <= 0
                            ? 0
                            : (shelf / capacity).clamp(0, 1),
                        minHeight: 8,
                        color: lowStock
                            ? PoMarketPalette.coral
                            : definition.color,
                        backgroundColor: definition.color.withValues(
                          alpha: 0.10,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ManagementInfoTile(
                icon: Icons.shopping_cart_checkout_rounded,
                label: _term(
                  context,
                  en: 'Buy cost',
                  he: 'עלות קנייה',
                  ar: 'تكلفة الشراء',
                ),
                value:
                    '${definition.orderCost} · ${unitCost.toStringAsFixed(1)}/${_term(context, en: 'item', he: 'יח׳', ar: 'قطعة')}',
                color: PoMarketPalette.gold,
              ),
              ManagementInfoTile(
                icon: Icons.sell_rounded,
                label: loc.sellingPrice,
                value: '$price',
                color: PoMarketPalette.blue,
              ),
              ManagementInfoTile(
                icon: profit < 0
                    ? Icons.trending_down_rounded
                    : Icons.trending_up_rounded,
                label: loc.profitPerItem,
                value: '$profit',
                color: PoMarketPalette.mint,
                negative: profit < 0,
              ),
              ManagementInfoTile(
                icon: Icons.percent_rounded,
                label: _term(context, en: 'Margin', he: 'מרווח', ar: 'الهامش'),
                value: '${(margin * 100).round()}%',
                color: PoMarketPalette.violet,
                negative: margin < 0,
              ),
              ManagementInfoTile(
                icon: Icons.local_fire_department_rounded,
                label: loc.demand,
                value: '${(demand * 100).round()}%',
                color: definition.color,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: selected
                      ? null
                      : () =>
                            controller.selectRestockDepartment(definition.type),
                  icon: Icon(
                    selected
                        ? Icons.check_circle_rounded
                        : Icons.inventory_2_rounded,
                    size: 17,
                  ),
                  label: Text(
                    selected ? loc.crateSelected : loc.prepareCrate,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: PressableScale(
                  enabled: controller.canOrderDepartmentStock(definition.type),
                  child: PoBtn(
                    onPressed:
                        controller.canOrderDepartmentStock(definition.type)
                        ? () => _order(context)
                        : null,
                    expand: true,
                    face: lowStock ? PoColor.danger : definition.color,
                    icon: pending
                        ? Icons.local_shipping_rounded
                        : Icons.add_shopping_cart_rounded,
                    label: pending
                        ? loc.deliveryInTransit
                        : '${definition.orderQuantity} · ${definition.orderCost}',
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _order(BuildContext context) {
    if (controller.placeDepartmentOrder(definition.type) == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(loc.quickRestockOrdered),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

class _DeliveryCard extends StatelessWidget {
  const _DeliveryCard({
    required this.delivery,
    required this.loc,
    required this.ready,
    required this.onFulfill,
  });

  final InventoryDelivery delivery;
  final AppLocalizations loc;
  final bool ready;
  final VoidCallback onFulfill;

  @override
  Widget build(BuildContext context) {
    final definition = DepartmentCatalog.all.firstWhere(
      (item) => item.category.toLowerCase() == delivery.category.toLowerCase(),
      orElse: () => DepartmentCatalog.all.first,
    );
    return ManagementCard(
      accent: definition.color,
      highlighted: ready,
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: definition.color.withValues(alpha: 0.14),
            child: Text(definition.emoji),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${delivery.category} · ${delivery.quantity}',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                Text(
                  ready
                      ? loc.deliveryReady
                      : MaterialLocalizations.of(context).formatTimeOfDay(
                          TimeOfDay.fromDateTime(delivery.readyAt),
                        ),
                  style: const TextStyle(
                    color: PoMarketPalette.muted,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          PoBtn(onPressed: ready ? onFulfill : null, label: loc.fulfill),
        ],
      ),
    );
  }
}

class _EmergencyStockCard extends StatelessWidget {
  const _EmergencyStockCard({required this.controller, required this.loc});

  final GameController controller;
  final AppLocalizations loc;

  @override
  Widget build(BuildContext context) {
    return ManagementCard(
      accent: PoMarketPalette.gold,
      highlighted: true,
      child: Row(
        children: [
          const Icon(
            Icons.volunteer_activism_rounded,
            color: PoMarketPalette.gold,
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  loc.emergencyStock,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                Text(
                  loc.emergencyStockDesc,
                  style: const TextStyle(
                    color: PoMarketPalette.muted,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: controller.claimEmergencyStock,
            child: Text('+${GameBalance.emergencyStockQuantity}'),
          ),
        ],
      ),
    );
  }
}

String _departmentName(DepartmentType type, AppLocalizations loc) {
  return switch (type) {
    DepartmentType.generalGoods => loc.departmentGeneralGoods,
    DepartmentType.bakery => loc.departmentBakery,
    DepartmentType.produce => loc.departmentProduce,
    DepartmentType.refrigerated => loc.departmentRefrigerated,
    DepartmentType.beauty => loc.departmentBeauty,
    DepartmentType.electronics => loc.departmentElectronics,
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
