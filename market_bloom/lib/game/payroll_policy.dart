import 'dart:math';

import 'game_models.dart';

/// Pure, deterministic payroll calculation for one shift.
///
/// This policy never reads or mutates game state and never charges coins. It
/// only returns the payroll amount implied by [role], [workerLevel], and
/// [workerCount].
abstract final class PayrollPolicy {
  static const Map<StaffRole, int> basePayPerWorker = <StaffRole, int>{
    StaffRole.cashier: 5,
    StaffRole.stocker: 5,
    StaffRole.cleaner: 4,
    StaffRole.baker: 6,
    StaffRole.manager: 135,
    StaffRole.courier: 6,
    StaffRole.promoter: 8,
  };

  static const Map<StaffRole, int> payPerAdditionalLevel = <StaffRole, int>{
    StaffRole.cashier: 2,
    StaffRole.stocker: 2,
    StaffRole.cleaner: 2,
    StaffRole.baker: 2,
    StaffRole.manager: 120,
    StaffRole.courier: 3,
    StaffRole.promoter: 3,
  };

  /// Returns the total payroll for this role for one shift.
  ///
  /// Formula:
  /// `workerCount * (basePay + (max(1, workerLevel) - 1) * levelPay)`.
  /// A non-positive [workerCount] always returns zero.
  static int forShift({
    required StaffRole role,
    required int workerLevel,
    required int workerCount,
  }) {
    if (workerCount <= 0) return 0;

    final normalizedLevel = max(1, workerLevel);
    final payPerWorker =
        basePayPerWorker[role]! +
        (normalizedLevel - 1) * payPerAdditionalLevel[role]!;
    return payPerWorker * workerCount;
  }
}
