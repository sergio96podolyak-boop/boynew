import 'package:flutter/material.dart';

import '../../game/game_controller.dart';
import '../../game/game_models.dart';
import '../../services/app_localizations.dart';

class InventoryScreen extends StatelessWidget {
  const InventoryScreen({super.key, required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(loc.inventoryTitle)),
      body: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final totalInventory = controller.totalStoredInventory;
          final capacity = controller.storageCapacity;
          final deliveries = controller.pendingDeliveries;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            children: [
              _InventoryHeader(
                controller: controller,
                loc: loc,
                totalInventory: totalInventory,
                capacity: capacity,
              ),
              const SizedBox(height: 20),
              Text(
                loc.activeDepartments,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 10),
              for (final definition in DepartmentCatalog.all)
                if (controller.isDepartmentUnlocked(definition.type)) ...[
                  _CategoryCard(
                    definition: definition,
                    controller: controller,
                    loc: loc,
                  ),
                  const SizedBox(height: 11),
                ],
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      loc.pendingDeliveries,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  if (deliveries.isNotEmpty)
                    Badge(label: Text('${deliveries.length}')),
                ],
              ),
              const SizedBox(height: 8),
              if (deliveries.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.task_alt_rounded,
                          color: Color(0xFF38A878),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          loc.noPendingDeliveries,
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                for (final delivery in deliveries)
                  _DeliveryCard(
                    delivery: delivery,
                    loc: loc,
                    ready: controller.isDeliveryReady(delivery),
                    onFulfill: () =>
                        controller.fulfillPendingDelivery(delivery.id),
                  ),
              if (controller.canClaimEmergencyStock) ...[
                const SizedBox(height: 14),
                _EmergencyStockCard(controller: controller, loc: loc),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _InventoryHeader extends StatelessWidget {
  const _InventoryHeader({
    required this.controller,
    required this.loc,
    required this.totalInventory,
    required this.capacity,
  });

  final GameController controller;
  final AppLocalizations loc;
  final int totalInventory;
  final int capacity;

  @override
  Widget build(BuildContext context) {
    final fraction = capacity == 0 ? 0.0 : totalInventory / capacity;
    return Container(
      padding: const EdgeInsets.all(19),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF202C46), Color(0xFF345887), Color(0xFF43A7A0)],
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [
          BoxShadow(
            color: Color(0x30202C46),
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(17),
                ),
                child: const Icon(
                  Icons.warehouse_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      loc.warehouseStock,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      '${controller.activeDepartmentCount} ${loc.activeDepartments}',
                      style: const TextStyle(
                        color: Color(0xCCFFFFFF),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '$totalInventory/$capacity',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 17),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: fraction.clamp(0, 1),
              minHeight: 11,
              color: const Color(0xFFFFD36A),
              backgroundColor: const Color(0x30FFFFFF),
            ),
          ),
          const SizedBox(height: 13),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _HeaderChip(
                icon: Icons.shopping_bag_rounded,
                label: loc.carried,
                value: '${controller.carried}/${controller.bagCapacity}',
              ),
              _HeaderChip(
                icon: Icons.storefront_rounded,
                label: loc.floorStock,
                value: '${controller.totalShelfInventory}',
              ),
              _HeaderChip(
                icon: Icons.local_shipping_rounded,
                label: loc.pendingDeliveries,
                value: '${controller.pendingDeliveryCount}',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeaderChip extends StatelessWidget {
  const _HeaderChip({
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: const Color(0xFFFFD36A), size: 16),
          const SizedBox(width: 5),
          Text(
            '$label $value',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
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
    final shelfCapacity = controller.departmentCapacity(definition.type);
    final storage = controller.departmentStorage(definition.type);
    final selected = controller.selectedRestockDepartment == definition.type;
    final pending = controller.hasPendingDepartmentDelivery(definition.type);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(21),
        border: Border.all(
          color: selected
              ? definition.color
              : Theme.of(context).colorScheme.outlineVariant,
          width: selected ? 2 : 1,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: definition.color.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(16),
                ),
                alignment: Alignment.center,
                child: Text(
                  definition.emoji,
                  style: const TextStyle(fontSize: 24),
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _departmentName(definition.type, loc),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      '${loc.floorStock} $shelf/$shelfCapacity · ${loc.warehouseStock} $storage',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                Icon(Icons.check_circle_rounded, color: definition.color),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              _InfoChip(
                label: loc.demand,
                value:
                    '${(controller.departmentDemand(definition.type) * 100).round()}%',
              ),
              _InfoChip(
                label: loc.sellingPrice,
                value: '${controller.departmentItemPrice(definition.type)}',
              ),
              _InfoChip(
                label: loc.estimatedProfit,
                value:
                    '${controller.departmentEstimatedProfit(definition.type)}',
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: selected
                      ? null
                      : () =>
                            controller.selectRestockDepartment(definition.type),
                  icon: Icon(
                    selected ? Icons.check_rounded : Icons.inventory_2_rounded,
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
                child: FilledButton.icon(
                  onPressed: controller.canOrderDepartmentStock(definition.type)
                      ? () => controller.placeDepartmentOrder(definition.type)
                      : null,
                  icon: Icon(
                    pending
                        ? Icons.local_shipping_rounded
                        : Icons.add_shopping_cart_rounded,
                    size: 17,
                  ),
                  label: Text(
                    pending
                        ? loc.deliveryInTransit
                        : '${definition.orderQuantity} · ${definition.orderCost}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$label $value',
        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800),
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
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: definition.color.withValues(alpha: 0.14),
          child: Text(definition.emoji),
        ),
        title: Text('${delivery.category} · ${delivery.quantity}'),
        subtitle: Text(
          ready
              ? loc.deliveryReady
              : MaterialLocalizations.of(
                  context,
                ).formatTimeOfDay(TimeOfDay.fromDateTime(delivery.readyAt)),
        ),
        trailing: FilledButton(
          onPressed: ready ? onFulfill : null,
          child: Text(loc.fulfill),
        ),
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
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF2D7),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFFFD27A)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.volunteer_activism_rounded,
            color: Color(0xFFE49A21),
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
                  style: const TextStyle(fontSize: 10),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: controller.claimEmergencyStock,
            child: Text(
              '+${GameBalance.emergencyStockQuantity}',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
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
