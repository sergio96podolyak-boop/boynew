import 'package:flutter/material.dart';

import '../../game/game_controller.dart';
import '../../game/game_models.dart';
import '../../services/app_localizations.dart';
import '../widgets/pressable_scale.dart';

class StaffScreen extends StatelessWidget {
  const StaffScreen({super.key, required this.controller});

  final GameController controller;

  static const _unlockLevel = 3;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final unlocked = controller.storeLevel >= _unlockLevel;

    return Scaffold(
      appBar: AppBar(title: Text(loc.staffManagement)),
      body: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
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
                  'Current store level: $storeLevel',
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
                    Icons.person_rounded,
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
            Text(
              'Level: $level',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            if (!hired)
              PressableScale(
                child: FilledButton.icon(
                  onPressed: controller.coins >= member.hireCost
                      ? () {
                          if (controller.hireStaff(role)) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('$roleName ${loc.hired}!'),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        }
                      : null,
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
                                content: Text('$roleName upgraded!'),
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
}
