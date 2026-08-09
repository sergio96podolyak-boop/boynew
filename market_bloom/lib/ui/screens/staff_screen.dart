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
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: [
            _TeamOverview(controller: controller, loc: loc),
            const SizedBox(height: 18),
            for (final role in StaffRole.values)
              _StaffCard(controller: controller, role: role, loc: loc),
          ],
        ),
      ),
    );
  }
}

class _TeamOverview extends StatelessWidget {
  const _TeamOverview({required this.controller, required this.loc});

  final GameController controller;
  final AppLocalizations loc;

  @override
  Widget build(BuildContext context) {
    final power = controller.staffMembers.fold<int>(
      0,
      (total, member) => total + (member.hired ? member.productivity : 0),
    );
    final availableSlots = StaffRole.values.fold<int>(
      0,
      (total, role) => total + controller.availableWorkerSlots(role),
    );

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF315F4A), Color(0xFF1FA879)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(26),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33315F4A),
            blurRadius: 18,
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
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(17),
                ),
                child: const Icon(
                  Icons.groups_2_rounded,
                  color: Colors.white,
                  size: 31,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      loc.teamOverview,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 21,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      loc.teamMembers.replaceFirst(
                        '{count}',
                        '${controller.totalHiredWorkers}',
                      ),
                      style: const TextStyle(color: Color(0xFFDDF7EA)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 17),
          Row(
            children: [
              Expanded(
                child: _OverviewMetric(
                  icon: Icons.store_rounded,
                  label: loc.storeLevel,
                  value: '${controller.storeLevel}',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _OverviewMetric(
                  icon: Icons.people_alt_rounded,
                  label: loc.hireStaff,
                  value: '${controller.totalHiredWorkers}/$availableSlots',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _OverviewMetric(
                  icon: Icons.bolt_rounded,
                  label: loc.teamPower.replaceFirst('{power}', ''),
                  value: '$power',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OverviewMetric extends StatelessWidget {
  const _OverviewMetric({
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
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        children: [
          Icon(icon, color: const Color(0xFFFFD278), size: 18),
          const SizedBox(height: 3),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xFFDDF7EA), fontSize: 9),
          ),
        ],
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
      (item) => item.role == role,
      orElse: () => StaffMember(role: role),
    );
    final unlocked = controller.isStaffRoleUnlocked(role);
    final hired = controller.isStaffHired(role);
    final status = controller.staffStatus(role);
    final color = _roleColor();
    final workerCount = controller.staffWorkerCount(role);
    final availableSlots = controller.availableWorkerSlots(role);
    final nextWorkerLevel = controller.nextWorkerSlotLevel(role);

    return Container(
      key: ValueKey('staff-card-${role.name}'),
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: unlocked
              ? [Colors.white, color.withValues(alpha: 0.08)]
              : [const Color(0xFFF1EFEA), const Color(0xFFE8E4DC)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: unlocked
              ? color.withValues(alpha: hired ? 0.5 : 0.22)
              : const Color(0x22000000),
          width: hired ? 1.5 : 1,
        ),
        boxShadow: unlocked
            ? const [
                BoxShadow(
                  color: Color(0x14315F4A),
                  blurRadius: 12,
                  offset: Offset(0, 5),
                ),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: unlocked
                      ? color.withValues(alpha: 0.16)
                      : const Color(0x18000000),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(
                  unlocked ? _roleIcon() : Icons.lock_rounded,
                  color: unlocked ? color : Colors.grey,
                  size: 30,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _roleName(),
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF315F4A),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _roleSummary(),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (hired)
                _StatusBadge(
                  label: _statusLabel(status),
                  color: _statusColor(status),
                ),
            ],
          ),
          const SizedBox(height: 15),
          if (!unlocked)
            _LockedRoleBanner(
              label: loc.roleUnlockAtLevel.replaceFirst(
                '{level}',
                '${GameBalance.staffRoleUnlockLevel(role)}',
              ),
            )
          else ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _StaffDetailChip(
                  icon: Icons.trending_up_rounded,
                  label: '${loc.level} ${member.level}',
                ),
                _StaffDetailChip(
                  icon: Icons.place_rounded,
                  label: _assignmentLabel(member.assignment),
                ),
                if (hired)
                  _StaffDetailChip(
                    icon: Icons.bolt_rounded,
                    label: loc.teamPower.replaceFirst(
                      '{power}',
                      '${member.productivity}',
                    ),
                  ),
                if (role == StaffRole.stocker && hired)
                  _StaffDetailChip(
                    icon: Icons.route_rounded,
                    label: loc.workerRoute,
                  ),
              ],
            ),
            if (hired) ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  for (
                    var index = 0;
                    index < GameBalance.maxWorkersPerRole;
                    index++
                  ) ...[
                    _WorkerSlot(
                      filled: index < workerCount,
                      available: index < availableSlots,
                      color: color,
                    ),
                    if (index < GameBalance.maxWorkersPerRole - 1)
                      const SizedBox(width: 7),
                  ],
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      workerCount >= GameBalance.maxWorkersPerRole
                          ? loc.maxWorkers
                          : nextWorkerLevel != null
                          ? loc.nextWorkerSlot.replaceFirst(
                              '{level}',
                              '$nextWorkerLevel',
                            )
                          : '${loc.teamMembers.replaceFirst('{count}', '$workerCount')} · $availableSlots',
                      maxLines: 2,
                      style: const TextStyle(
                        color: Color(0xFF627068),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 15),
            if (!hired)
              _PrimaryAction(
                color: color,
                icon: Icons.person_add_rounded,
                label: '${loc.hire} — ${member.hireCost}',
                onTap: () => _hire(context, member),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _CompactAction(
                    icon: Icons.upgrade_rounded,
                    label: member.level >= 10
                        ? loc.maxLevel
                        : '${loc.upgradeStaff} · ${member.upgradeCost}',
                    color: color,
                    onTap: member.level >= 10
                        ? null
                        : () => _upgrade(context, member),
                  ),
                  if (workerCount < GameBalance.maxWorkersPerRole)
                    _CompactAction(
                      icon: nextWorkerLevel == null
                          ? Icons.group_add_rounded
                          : Icons.lock_clock_rounded,
                      label: nextWorkerLevel == null
                          ? '${loc.addWorker} · ${member.additionalHireCost}'
                          : loc.nextWorkerSlot.replaceFirst(
                              '{level}',
                              '$nextWorkerLevel',
                            ),
                      color: const Color(0xFF5B8DEF),
                      onTap: nextWorkerLevel == null
                          ? () => _addWorker(context, member)
                          : null,
                    ),
                ],
              ),
          ],
        ],
      ),
    );
  }

  void _hire(BuildContext context, StaffMember member) {
    if (controller.hireStaff(role)) {
      _showMessage(context, '${_roleName()} ${loc.hired}!');
      return;
    }
    _showMessage(
      context,
      loc.staffNeedsCoins.replaceFirst('{cost}', '${member.hireCost}'),
    );
  }

  void _upgrade(BuildContext context, StaffMember member) {
    if (controller.upgradeStaff(role)) {
      _showMessage(context, '${_roleName()} — ${loc.upgradeStaff}');
      return;
    }
    _showMessage(context, loc.notEnoughCoins);
  }

  void _addWorker(BuildContext context, StaffMember member) {
    if (controller.hireAdditionalStaff(role)) {
      _showMessage(context, '${_roleName()} — ${loc.addWorker}');
      return;
    }
    _showMessage(
      context,
      loc.staffNeedsCoins.replaceFirst(
        '{cost}',
        '${member.additionalHireCost}',
      ),
    );
  }

  void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  String _roleName() {
    return switch (role) {
      StaffRole.cashier => loc.staffRoleCashier,
      StaffRole.stocker => loc.staffRoleStocker,
      StaffRole.cleaner => loc.staffRoleCleaner,
      StaffRole.baker => loc.staffRoleBaker,
      StaffRole.manager => loc.staffRoleManager,
      StaffRole.courier => loc.staffRoleCourier,
      StaffRole.promoter => loc.staffRolePromoter,
    };
  }

  String _roleSummary() {
    return switch (role) {
      StaffRole.cashier => loc.staffSummaryCashier,
      StaffRole.stocker => loc.staffSummaryStocker,
      StaffRole.cleaner => loc.staffSummaryCleaner,
      StaffRole.baker => loc.staffSummaryBaker,
      StaffRole.manager => loc.staffSummaryManager,
      StaffRole.courier => loc.staffSummaryCourier,
      StaffRole.promoter => loc.staffSummaryPromoter,
    };
  }

  String _assignmentLabel(StaffAssignment assignment) {
    return switch (assignment) {
      StaffAssignment.checkout => loc.assignmentCheckout,
      StaffAssignment.shelves => loc.assignmentShelves,
      StaffAssignment.floor => loc.assignmentFloor,
      StaffAssignment.bakery => loc.assignmentBakery,
      StaffAssignment.office => loc.assignmentOffice,
      StaffAssignment.delivery => loc.assignmentDelivery,
      StaffAssignment.entrance => loc.assignmentEntrance,
    };
  }

  IconData _roleIcon() {
    return switch (role) {
      StaffRole.cashier => Icons.point_of_sale_rounded,
      StaffRole.stocker => Icons.inventory_2_rounded,
      StaffRole.cleaner => Icons.cleaning_services_rounded,
      StaffRole.baker => Icons.bakery_dining_rounded,
      StaffRole.manager => Icons.business_center_rounded,
      StaffRole.courier => Icons.local_shipping_rounded,
      StaffRole.promoter => Icons.campaign_rounded,
    };
  }

  Color _roleColor() {
    return switch (role) {
      StaffRole.cashier => const Color(0xFF315F8F),
      StaffRole.stocker => const Color(0xFF5B8DEF),
      StaffRole.cleaner => const Color(0xFF1FA8A8),
      StaffRole.baker => const Color(0xFFF6A623),
      StaffRole.manager => const Color(0xFF8B66D8),
      StaffRole.courier => const Color(0xFFE85D75),
      StaffRole.promoter => const Color(0xFF38B879),
    };
  }

  String _statusLabel(StaffStatus status) {
    return switch (status) {
      StaffStatus.notHired => loc.staffLocked,
      StaffStatus.idle => loc.statusIdle,
      StaffStatus.serving => loc.statusServing,
      StaffStatus.stocking => loc.statusStocking,
      StaffStatus.waitingForStock => loc.statusWaitingStock,
      StaffStatus.waitingForShelf => loc.statusWaitingShelf,
      StaffStatus.cleaning => loc.statusCleaning,
      StaffStatus.baking => loc.statusBaking,
      StaffStatus.managing => loc.statusManaging,
      StaffStatus.delivering => loc.statusDelivering,
      StaffStatus.promoting => loc.statusPromoting,
    };
  }

  Color _statusColor(StaffStatus status) {
    return switch (status) {
      StaffStatus.waitingForStock ||
      StaffStatus.waitingForShelf => const Color(0xFFE09A20),
      StaffStatus.idle || StaffStatus.notHired => const Color(0xFF7B8580),
      _ => const Color(0xFF2E9B5F),
    };
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 105),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        maxLines: 2,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _LockedRoleBanner extends StatelessWidget {
  const _LockedRoleBanner({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0x11000000),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        children: [
          const Icon(Icons.lock_clock_rounded, size: 19, color: Colors.grey),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF6B746E),
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkerSlot extends StatelessWidget {
  const _WorkerSlot({
    required this.filled,
    required this.available,
    required this.color,
  });

  final bool filled;
  final bool available;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 31,
      height: 31,
      decoration: BoxDecoration(
        color: filled
            ? color
            : available
            ? color.withValues(alpha: 0.1)
            : const Color(0x10000000),
        shape: BoxShape.circle,
        border: Border.all(
          color: available
              ? color.withValues(alpha: 0.5)
              : Colors.grey.shade400,
        ),
      ),
      child: Icon(
        filled
            ? Icons.person_rounded
            : available
            ? Icons.add_rounded
            : Icons.lock_rounded,
        size: 17,
        color: filled
            ? Colors.white
            : available
            ? color
            : Colors.grey.shade500,
      ),
    );
  }
}

class _PrimaryAction extends StatelessWidget {
  const _PrimaryAction({
    required this.color,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final Color color;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      child: FilledButton.icon(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          backgroundColor: color,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
        ),
        icon: Icon(icon),
        label: Text(label),
      ),
    );
  }
}

class _CompactAction extends StatelessWidget {
  const _CompactAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      enabled: onTap != null,
      child: FilledButton.icon(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: color,
          disabledBackgroundColor: color.withValues(alpha: 0.25),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        icon: Icon(icon, size: 18),
        label: Text(
          label,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
        ),
      ),
    );
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
