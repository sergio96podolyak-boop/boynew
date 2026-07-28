import 'package:flutter/material.dart';

import '../../game/game_controller.dart';
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
          final totalInventory =
              controller.inventoryFor('General') +
              controller.inventoryFor('Produce') +
              controller.inventoryFor('Bakery');
          final capacity = controller.shelfCapacity + controller.bagCapacity;
          final deliveries = controller.pendingDeliveryCount;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _StatCard(
                icon: Icons.inventory_2_rounded,
                label: loc.carried,
                value: '${controller.carried}/${controller.bagCapacity}',
                color: const Color(0xFF5B8DEF),
              ),
              const SizedBox(height: 12),
              _StatCard(
                icon: Icons.storefront_rounded,
                label: loc.shelfStock,
                value: '${controller.shelfStock}/${controller.shelfCapacity}',
                color: const Color(0xFF38B879),
              ),
              const SizedBox(height: 12),
              _StatCard(
                icon: Icons.warehouse_rounded,
                label: loc.storage,
                value: '$totalInventory',
                color: const Color(0xFFF6A623),
              ),
              const SizedBox(height: 12),
              _StatCard(
                icon: Icons.category_rounded,
                label: loc.totalInventory,
                value: '$totalInventory/$capacity',
                color: const Color(0xFF8B66D8),
              ),
              const SizedBox(height: 24),
              Text(
                loc.pendingDeliveries,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              if (deliveries == 0)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      loc.noPendingDeliveries,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                )
              else
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      '$deliveries ${loc.pendingDeliveries.toLowerCase()}',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: color.withValues(alpha: 0.15),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
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
