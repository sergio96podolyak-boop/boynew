import 'package:flutter/material.dart';

import '../../game/game_controller.dart';
import '../../game/game_models.dart';
import '../../services/app_localizations.dart';
import '../widgets/management_ui.dart';
import '../widgets/premium_ui.dart';
import '../widgets/pressable_scale.dart';

class StaffScreen extends StatelessWidget {
  const StaffScreen({super.key, required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return ManagementScaffold(
      title: loc.staffManagement,
      icon: Icons.groups_2_rounded,
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final hired = controller.totalHiredWorkers;
          final productivity = controller.staffMembers.fold<int>(
            0,
            (total, member) => total + (member.hired ? member.productivity : 0),
          );
          final availableSlots = StaffRole.values.fold<int>(
            0,
            (total, role) => total + controller.availableWorkerSlots(role),
          );
          final workingRoles = StaffRole.values.where((role) {
            final status = controller.staffStatus(role);
            return controller.isStaffHired(role) && status != StaffStatus.idle;
          }).length;

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            children: [
              ManagementHero(
                icon: Icons.badge_rounded,
                title: loc.teamOverview,
                subtitle: loc.teamMembers.replaceFirst('{count}', '$hired'),
                colors: const [Color(0xFF0B1F1A), Color(0xFF2FD98F)],
                metrics: [
                  ManagementHeroMetric(
                    icon: Icons.people_alt_rounded,
                    label: loc.hireStaff,
                    value: '$hired/$availableSlots',
                  ),
                  ManagementHeroMetric(
                    icon: Icons.bolt_rounded,
                    label: loc.teamPower.replaceFirst('{power}', ''),
                    value: '$productivity',
                  ),
                  ManagementHeroMetric(
                    icon: Icons.work_history_rounded,
                    label: _term(
                      context,
                      en: 'Working roles',
                      he: 'תפקידים פעילים',
                      ar: 'الأدوار العاملة',
                    ),
                    value: '$workingRoles',
                  ),
                ],
              ),
              const SizedBox(height: 22),
              ManagementSectionTitle(
                title: loc.staffManagement,
                subtitle: _term(
                  context,
                  en: 'Hire, assign and upgrade your store team',
                  he: 'גייסו, שייכו ושדרגו את צוות החנות',
                  ar: 'وظّف فريق المتجر ووزّعه وطوّره',
                ),
              ),
              const SizedBox(height: 12),
              ManagementResponsiveWrap(
                children: [
                  for (final role in StaffRole.values)
                    _StaffCard(
                      key: ValueKey('staff-card-${role.name}'),
                      controller: controller,
                      role: role,
                      loc: loc,
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _StaffCard extends StatelessWidget {
  const _StaffCard({
    super.key,
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
    final color = _roleColor(role);
    final workerCount = controller.staffWorkerCount(role);
    final availableSlots = controller.availableWorkerSlots(role);
    final nextWorkerLevel = controller.nextWorkerSlotLevel(role);
    final upgradeable = hired && member.level < 10;
    final canHire = unlocked && controller.coins >= member.hireCost;
    final canUpgrade = upgradeable && controller.coins >= member.upgradeCost;
    final canAddWorker =
        hired &&
        workerCount < GameBalance.maxWorkersPerRole &&
        nextWorkerLevel == null &&
        controller.coins >= member.additionalHireCost;
    final presentation = _statusPresentation(
      context,
      unlocked: unlocked,
      hired: hired,
      status: status,
    );

    return ManagementCard(
      accent: color,
      highlighted: hired || (unlocked && !hired),
      muted: !unlocked,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _StaffAvatar(
                icon: unlocked ? _roleIcon(role) : Icons.lock_rounded,
                color: unlocked ? color : PoMarketPalette.muted,
                active: hired,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _roleName(role, loc),
                      style: const TextStyle(
                        color: PoMarketPalette.ink,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _roleSummary(role, loc),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: PoMarketPalette.muted,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ManagementStatusPill(
                label: presentation.label,
                color: presentation.color,
                icon: presentation.icon,
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (!unlocked)
            _LockedRolePanel(
              color: color,
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
                ManagementInfoTile(
                  icon: Icons.place_rounded,
                  label: _term(
                    context,
                    en: 'Station',
                    he: 'עמדה',
                    ar: 'المحطة',
                  ),
                  value: _assignmentLabel(member.assignment, loc),
                  color: color,
                ),
                ManagementInfoTile(
                  icon: Icons.payments_rounded,
                  label: hired
                      ? _term(
                          context,
                          en: 'Upgrade cost',
                          he: 'עלות שדרוג',
                          ar: 'تكلفة الترقية',
                        )
                      : _term(
                          context,
                          en: 'Hire cost',
                          he: 'עלות גיוס',
                          ar: 'تكلفة التوظيف',
                        ),
                  value: hired && member.level >= 10
                      ? loc.maxLevel
                      : '${hired ? member.upgradeCost : member.hireCost}',
                  color: PoMarketPalette.gold,
                ),
                ManagementInfoTile(
                  icon: Icons.bolt_rounded,
                  label: _term(
                    context,
                    en: 'Productivity',
                    he: 'תפוקה',
                    ar: 'الإنتاجية',
                  ),
                  value: hired ? '${member.productivity}' : '—',
                  color: PoMarketPalette.mint,
                ),
                ManagementInfoTile(
                  icon: Icons.stars_rounded,
                  label: loc.level,
                  value: '${member.level}',
                  color: PoMarketPalette.violet,
                ),
              ],
            ),
            if (hired) ...[
              const SizedBox(height: 14),
              _WorkerCapacity(
                workerCount: workerCount,
                availableSlots: availableSlots,
                nextWorkerLevel: nextWorkerLevel,
                color: color,
                loc: loc,
              ),
            ],
            if (role == StaffRole.cashier && hired) ...[
              const SizedBox(height: 14),
              _CheckoutStationControls(controller: controller),
            ],
            const SizedBox(height: 14),
            if (!hired)
              _StaffAction(
                icon: Icons.person_add_rounded,
                label: '${loc.hire} — ${member.hireCost}',
                color: color,
                filled: true,
                enabled: canHire,
                onPressed: () => _hire(context, member),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _StaffAction(
                    icon: Icons.upgrade_rounded,
                    label: upgradeable
                        ? '${loc.upgradeStaff} · ${member.upgradeCost}'
                        : loc.maxLevel,
                    color: color,
                    filled: true,
                    enabled: canUpgrade,
                    onPressed: () => _upgrade(context),
                  ),
                  if (workerCount < GameBalance.maxWorkersPerRole)
                    _StaffAction(
                      icon: nextWorkerLevel == null
                          ? Icons.group_add_rounded
                          : Icons.lock_clock_rounded,
                      label: nextWorkerLevel == null
                          ? '${loc.addWorker} · ${member.additionalHireCost}'
                          : loc.nextWorkerSlot.replaceFirst(
                              '{level}',
                              '$nextWorkerLevel',
                            ),
                      color: PoMarketPalette.blue,
                      filled: false,
                      enabled: canAddWorker,
                      onPressed: () => _addWorker(context, member),
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
      _message(context, '${_roleName(role, loc)} ${loc.hired}!');
      return;
    }
    _message(
      context,
      loc.staffNeedsCoins.replaceFirst('{cost}', '${member.hireCost}'),
    );
  }

  void _upgrade(BuildContext context) {
    if (controller.upgradeStaff(role)) {
      _message(context, '${_roleName(role, loc)} — ${loc.upgradeStaff}');
      return;
    }
    _message(context, loc.notEnoughCoins);
  }

  void _addWorker(BuildContext context, StaffMember member) {
    if (controller.hireAdditionalStaff(role)) {
      _message(context, '${_roleName(role, loc)} — ${loc.addWorker}');
      return;
    }
    _message(
      context,
      loc.staffNeedsCoins.replaceFirst(
        '{cost}',
        '${member.additionalHireCost}',
      ),
    );
  }

  void _message(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }
}

class _StaffAvatar extends StatelessWidget {
  const _StaffAvatar({
    required this.icon,
    required this.color,
    required this.active,
  });

  final IconData icon;
  final Color color;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 58,
      height: 58,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: active ? 0.28 : 0.15),
            color.withValues(alpha: 0.06),
          ],
        ),
        borderRadius: BorderRadius.circular(19),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Icon(icon, color: color, size: 29),
    );
  }
}

class _LockedRolePanel extends StatelessWidget {
  const _LockedRolePanel({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 52),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Row(
        children: [
          Icon(Icons.lock_clock_rounded, color: color, size: 20),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: PoMarketPalette.ink,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkerCapacity extends StatelessWidget {
  const _WorkerCapacity({
    required this.workerCount,
    required this.availableSlots,
    required this.nextWorkerLevel,
    required this.color,
    required this.loc,
  });

  final int workerCount;
  final int availableSlots;
  final int? nextWorkerLevel;
  final Color color;
  final AppLocalizations loc;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
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
              const SizedBox(width: 6),
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
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: PoMarketPalette.muted,
                fontSize: 10,
                fontWeight: FontWeight.w700,
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
            ? color.withValues(alpha: 0.10)
            : PoMarketPalette.line,
        shape: BoxShape.circle,
        border: Border.all(
          color: available
              ? color.withValues(alpha: 0.5)
              : PoMarketPalette.muted.withValues(alpha: 0.35),
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
            : PoMarketPalette.muted,
      ),
    );
  }
}

class _StaffAction extends StatelessWidget {
  const _StaffAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.filled,
    required this.enabled,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final Color color;
  final bool filled;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      enabled: enabled,
      child: FilledButton.icon(
        onPressed: enabled ? onPressed : null,
        style: FilledButton.styleFrom(
          minimumSize: const Size(44, 46),
          backgroundColor: filled ? color : color.withValues(alpha: 0.11),
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

class _CheckoutStationControls extends StatelessWidget {
  const _CheckoutStationControls({required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    final stations = controller.checkoutStations
        .where((station) => station.unlocked)
        .toList(growable: false);
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: PoMarketPalette.blue.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: PoMarketPalette.blue.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _term(
              context,
              en: 'Assigned registers',
              he: 'קופות משויכות',
              ar: 'صناديق الدفع المعيّنة',
            ),
            style: const TextStyle(
              color: PoMarketPalette.ink,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 7),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              for (var index = 0; index < stations.length; index++)
                FilterChip(
                  label: Text(
                    _term(
                      context,
                      en: 'Register ${index + 1}',
                      he: 'קופה ${index + 1}',
                      ar: 'صندوق ${index + 1}',
                    ),
                  ),
                  avatar: Icon(
                    controller.checkoutStationHasCashier(stations[index].id)
                        ? Icons.person_rounded
                        : Icons.touch_app_rounded,
                    size: 16,
                  ),
                  selected: stations[index].active,
                  onSelected:
                      stations[index].id ==
                          GameController.primaryCheckoutStationId
                      ? null
                      : (active) => controller.setCheckoutStationActive(
                          stations[index].id,
                          active,
                        ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

({String label, Color color, IconData icon}) _statusPresentation(
  BuildContext context, {
  required bool unlocked,
  required bool hired,
  required StaffStatus status,
}) {
  if (!unlocked) {
    return (
      label: _term(context, en: 'Unavailable', he: 'לא זמין', ar: 'غير متاح'),
      color: PoMarketPalette.muted,
      icon: Icons.lock_rounded,
    );
  }
  if (!hired) {
    return (
      label: _term(context, en: 'Available', he: 'זמין', ar: 'متاح'),
      color: PoMarketPalette.blue,
      icon: Icons.person_add_alt_1_rounded,
    );
  }
  if (status == StaffStatus.idle) {
    return (
      label: _term(context, en: 'Hired', he: 'מגויס', ar: 'موظف'),
      color: PoMarketPalette.violet,
      icon: Icons.badge_rounded,
    );
  }
  if (status == StaffStatus.waitingForShelf ||
      status == StaffStatus.waitingForStock) {
    return (
      label: _term(context, en: 'Waiting', he: 'ממתין', ar: 'بانتظار'),
      color: PoMarketPalette.gold,
      icon: Icons.hourglass_top_rounded,
    );
  }
  return (
    label: _term(context, en: 'Working', he: 'עובד', ar: 'يعمل'),
    color: PoMarketPalette.mint,
    icon: Icons.play_circle_fill_rounded,
  );
}

String _roleName(StaffRole role, AppLocalizations loc) => switch (role) {
  StaffRole.cashier => loc.staffRoleCashier,
  StaffRole.stocker => loc.staffRoleStocker,
  StaffRole.cleaner => loc.staffRoleCleaner,
  StaffRole.baker => loc.staffRoleBaker,
  StaffRole.manager => loc.staffRoleManager,
  StaffRole.courier => loc.staffRoleCourier,
  StaffRole.promoter => loc.staffRolePromoter,
};

String _roleSummary(StaffRole role, AppLocalizations loc) => switch (role) {
  StaffRole.cashier => loc.staffSummaryCashier,
  StaffRole.stocker => loc.staffSummaryStocker,
  StaffRole.cleaner => loc.staffSummaryCleaner,
  StaffRole.baker => loc.staffSummaryBaker,
  StaffRole.manager => loc.staffSummaryManager,
  StaffRole.courier => loc.staffSummaryCourier,
  StaffRole.promoter => loc.staffSummaryPromoter,
};

String _assignmentLabel(StaffAssignment assignment, AppLocalizations loc) {
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

IconData _roleIcon(StaffRole role) => switch (role) {
  StaffRole.cashier => Icons.point_of_sale_rounded,
  StaffRole.stocker => Icons.inventory_2_rounded,
  StaffRole.cleaner => Icons.cleaning_services_rounded,
  StaffRole.baker => Icons.bakery_dining_rounded,
  StaffRole.manager => Icons.business_center_rounded,
  StaffRole.courier => Icons.local_shipping_rounded,
  StaffRole.promoter => Icons.campaign_rounded,
};

Color _roleColor(StaffRole role) => switch (role) {
  StaffRole.cashier => const Color(0xFF1D6FD4),
  StaffRole.stocker => PoMarketPalette.blue,
  StaffRole.cleaner => const Color(0xFF0C837E),
  StaffRole.baker => PoMarketPalette.gold,
  StaffRole.manager => PoMarketPalette.violet,
  StaffRole.courier => PoMarketPalette.coral,
  StaffRole.promoter => const Color(0xFF2FD98F),
};

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
