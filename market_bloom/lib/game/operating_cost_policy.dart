import 'dart:math';

import 'game_models.dart';
import 'payroll_policy.dart';

/// Balanced end-of-shift operating cost rules.
///
/// These methods are pure calculations. Charging cash and recording the ledger
/// remain the responsibility of [GameController] so each shift is settled once.
abstract final class OperatingCostPolicy {
  static int payrollForRole(
    StaffRole role, {
    required int level,
    required int workerCount,
  }) {
    return PayrollPolicy.forShift(
      role: role,
      workerLevel: level,
      workerCount: workerCount,
    );
  }

  static int totalPayroll(Iterable<StaffMember> staff) {
    return staff.fold<int>(0, (total, member) {
      if (!member.hired || member.workerCount <= 0) return total;
      return total +
          payrollForRole(
            member.role,
            level: member.level,
            workerCount: member.workerCount,
          );
    });
  }

  /// Returns the operating cost for one department for one shift.
  ///
  /// Locked or inactive departments cost zero. Non-positive levels normalize
  /// to level one. The tier formulas are deterministic and monotonic while
  /// keeping the starter department free at level one.
  ///
  /// This function reads but never mutates [department].
  static int operatingCostPerShift(
    DepartmentState department,
    int level,
  ) {
    if (!department.unlocked || !department.activated) return 0;
    return departmentOperatingCost(department.type, level: level);
  }

  /// Type-level calculation for a department already known to be active.
  static int departmentOperatingCost(
    DepartmentType type, {
    required int level,
  }) {
    final normalizedLevel = max(1, level);
    final extraLevels = normalizedLevel - 1;
    return switch (type) {
      // The starter department remains free at level one and gains one coin of
      // overhead after each three department upgrades.
      DepartmentType.generalGoods => extraLevels ~/ 3,
      DepartmentType.bakery => 2 + extraLevels,
      DepartmentType.produce => 3 + extraLevels,
      DepartmentType.refrigerated => 5 + extraLevels * 2,
      DepartmentType.beauty => 7 + extraLevels * 2,
      DepartmentType.electronics => 9 + extraLevels * 3,
    };
  }

  static int totalDepartmentOperatingCosts(
    Iterable<DepartmentState> departments,
  ) {
    return departments.fold<int>(
      0,
      (total, department) =>
          total + operatingCostPerShift(department, department.level),
    );
  }
}
