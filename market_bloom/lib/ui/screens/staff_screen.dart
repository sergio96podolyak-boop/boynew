import 'package:flutter/material.dart';

import '../../game/game_controller.dart';
import '../../game/game_models.dart';
import '../../services/app_localizations.dart';
import '../widgets/pressable_scale.dart';

class StaffScreen extends StatelessWidget {
  const StaffScreen({super.key, required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(loc.staffManagement)),
      body: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final unlocked =
              controller.storeLevel >= GameBalance.staffUnlockLevel;
          if (!unlocked) {
            return _LockedStaffCard(
              loc: loc,
              storeLevel: controller.storeLevel,
            );
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              for (final role in StaffRole.values)
                _StaffCard(controller: controller, role: role, loc: loc),
            ],
          );
        },
      ),
    );
  }
}

class _LockedStaffCard extends StatelessWidget {
  const _LockedStaffCard({required this.loc, required this.storeLevel});

  final AppLocalizations loc;
  final int storeLevel;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_rounded, size: 54, color: Colors.grey),
                const SizedBox(height: 12),
                Text(
                  loc.staffLocked,
                  style: Theme.of(context).textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  loc.staffUnlockRequirement,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  '${loc.storeLevel}: $storeLevel',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
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

class _StaffCard extends StatelessWidget {
  const _StaffCard({
    required this.controller,
    required this.role,
    required this.loc,
  });

  final GameController controller;
  final StaffRole role;
  final AppLocalizations loc;

  @override
  Widget build(BuildContext context) {
    final member = controller.staffMembers.firstWhere(
      (m) => m.role == role,
      orElse: () => StaffMember(role: role),
    );
    final hired = controller.isStaffHired(role);
    final level = controller.staffLevel(role);
    final status = controller.staffStatus(role);

    String roleName;
    String summary;
    switch (role) {
      case StaffRole.cashier:
        roleName = loc.staffRoleCashier;
        summary = loc.staffSummaryCashier;
      case StaffRole.stocker:
        roleName = loc.staffRoleStocker;
        summary = loc.staffSummaryStocker;
      case StaffRole.cleaner:
        roleName = loc.staffRoleCleaner;
        summary = loc.staffSummaryCleaner;
      case StaffRole.manager:
        roleName = loc.staffRoleManager;
        summary = loc.staffSummaryManager;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: Theme.of(
                    context,
                  ).colorScheme.primaryContainer,
                  child: Icon(
                    _roleIcon(),
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        roleName,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      Text(
                        summary,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                if (hired)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      loc.hired,
                      style: const TextStyle(color: Colors.green, fontSize: 11),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _StaffDetailChip(
                  icon: Icons.trending_up_rounded,
                  label: '${loc.level} $level',
                ),
                _StaffDetailChip(
                  icon: Icons.place_rounded,
                  label:
                      '${loc.staffAssignment}: ${_assignmentLabel(member.assignment)}',
                ),
                if (hired)
                  _StaffDetailChip(
                    icon: Icons.circle,
                    label: '${loc.staffStatus}: ${_statusLabel(status)}',
                  ),
                if (hired)
                  _StaffDetailChip(
                    icon: Icons.bolt_rounded,
                    label: _effectLabel(),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (!hired)
              PressableScale(
                child: FilledButton.icon(
                  onPressed: () {
                    if (controller.hireStaff(role)) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('$roleName ${loc.hired}!'),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                      return;
                    }
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          loc.staffNeedsCoins.replaceFirst(
                            '{cost}',
                            '${member.hireCost}',
                          ),
                        ),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                  icon: const Icon(Icons.person_add_rounded),
                  label: Text('${loc.hire} — ${member.hireCost}'),
                ),
              ),
            if (hired)
              PressableScale(
                child: FilledButton.icon(
                  onPressed: controller.coins >= member.upgradeCost
                      ? () {
                          if (controller.upgradeStaff(role)) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  '$roleName — ${loc.upgradeStaff}',
                                ),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        }
                      : null,
                  icon: const Icon(Icons.upgrade_rounded),
                  label: Text('${loc.upgradeStaff} — ${member.upgradeCost}'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _assignmentLabel(StaffAssignment assignment) {
    return switch (assignment) {
      StaffAssignment.checkout => loc.assignmentCheckout,
      StaffAssignment.shelves => loc.assignmentShelves,
      StaffAssignment.floor => loc.assignmentFloor,
      StaffAssignment.office => loc.assignmentOffice,
    };
  }

  IconData _roleIcon() {
    return switch (role) {
      StaffRole.cashier => Icons.point_of_sale_rounded,
      StaffRole.stocker => Icons.inventory_2_rounded,
      StaffRole.cleaner => Icons.cleaning_services_rounded,
      StaffRole.manager => Icons.business_center_rounded,
    };
  }

  String _statusLabel(StaffStatus status) {
    return switch (status) {
      StaffStatus.notHired => loc.staffLocked,
      StaffStatus.idle => loc.statusIdle,
      StaffStatus.serving => loc.statusServing,
      StaffStatus.stocking => loc.statusStocking,
      StaffStatus.cleaning => loc.statusCleaning,
      StaffStatus.managing => loc.statusManaging,
    };
  }

  String _effectLabel() {
    return switch (role) {
      StaffRole.cashier => loc.serviceTime.replaceFirst(
        '{value}',
        controller.cashierCheckoutSeconds.toStringAsFixed(2),
      ),
      StaffRole.stocker => loc.staffSummaryStocker,
      StaffRole.cleaner => loc.staffSummaryCleaner,
      StaffRole.manager => loc.staffSummaryManager,
    };
  }
}

class _StaffDetailChip extends StatelessWidget {
  const _StaffDetailChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 36),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
