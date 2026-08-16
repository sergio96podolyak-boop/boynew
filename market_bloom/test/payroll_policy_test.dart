import 'package:flutter_test/flutter_test.dart';
import 'package:pomarket/game/game_models.dart';
import 'package:pomarket/game/payroll_policy.dart';

void main() {
  const expectedRates = <StaffRole, ({int base, int perLevel})>{
    StaffRole.cashier: (base: 5, perLevel: 2),
    StaffRole.stocker: (base: 5, perLevel: 2),
    StaffRole.cleaner: (base: 4, perLevel: 2),
    StaffRole.baker: (base: 6, perLevel: 2),
    StaffRole.manager: (base: 135, perLevel: 120),
    StaffRole.courier: (base: 6, perLevel: 3),
    StaffRole.promoter: (base: 8, perLevel: 3),
  };

  group('PayrollPolicy role rates', () {
    for (final role in StaffRole.values) {
      test('${role.name} uses its audited base and level rates', () {
        final rates = expectedRates[role]!;

        expect(
          PayrollPolicy.forShift(
            role: role,
            workerLevel: 1,
            workerCount: 1,
          ),
          rates.base,
        );
        expect(
          PayrollPolicy.forShift(
            role: role,
            workerLevel: 4,
            workerCount: 1,
          ),
          rates.base + rates.perLevel * 3,
        );
      });
    }
  });

  test('different worker levels follow the exact linear formula', () {
    expect(
      PayrollPolicy.forShift(
        role: StaffRole.cashier,
        workerLevel: 2,
        workerCount: 1,
      ),
      7,
    );
    expect(
      PayrollPolicy.forShift(
        role: StaffRole.courier,
        workerLevel: 5,
        workerCount: 1,
      ),
      18,
    );
    expect(
      PayrollPolicy.forShift(
        role: StaffRole.manager,
        workerLevel: 10,
        workerCount: 1,
      ),
      1215,
    );
  });

  test('worker count scales payroll linearly', () {
    final oneWorker = PayrollPolicy.forShift(
      role: StaffRole.baker,
      workerLevel: 5,
      workerCount: 1,
    );

    expect(oneWorker, 14);
    expect(
      PayrollPolicy.forShift(
        role: StaffRole.baker,
        workerLevel: 5,
        workerCount: 2,
      ),
      oneWorker * 2,
    );
    expect(
      PayrollPolicy.forShift(
        role: StaffRole.baker,
        workerLevel: 5,
        workerCount: 3,
      ),
      oneWorker * 3,
    );
  });

  test('one worker versus several workers is linear for every role', () {
    for (final role in StaffRole.values) {
      final oneWorker = PayrollPolicy.forShift(
        role: role,
        workerLevel: 3,
        workerCount: 1,
      );
      final severalWorkers = PayrollPolicy.forShift(
        role: role,
        workerLevel: 3,
        workerCount: 7,
      );

      expect(severalWorkers, oneWorker * 7, reason: role.name);
    }
  });

  test('the same inputs always produce deterministic output', () {
    for (final role in StaffRole.values) {
      final expected = PayrollPolicy.forShift(
        role: role,
        workerLevel: 6,
        workerCount: 3,
      );

      for (var iteration = 0; iteration < 25; iteration++) {
        expect(
          PayrollPolicy.forShift(
            role: role,
            workerLevel: 6,
            workerCount: 3,
          ),
          expected,
          reason: '${role.name}, iteration $iteration',
        );
      }
    }
  });

  test('zero workers always returns zero payroll', () {
    for (final role in StaffRole.values) {
      expect(
        PayrollPolicy.forShift(
          role: role,
          workerLevel: 10,
          workerCount: 0,
        ),
        0,
        reason: role.name,
      );
    }
  });

  test('negative worker counts are safely treated as zero workers', () {
    expect(
      PayrollPolicy.forShift(
        role: StaffRole.promoter,
        workerLevel: 4,
        workerCount: -3,
      ),
      0,
    );
  });

  test('non-positive worker levels use the level-one rate', () {
    for (final role in StaffRole.values) {
      final levelOne = PayrollPolicy.forShift(
        role: role,
        workerLevel: 1,
        workerCount: 2,
      );

      expect(
        PayrollPolicy.forShift(
          role: role,
          workerLevel: 0,
          workerCount: 2,
        ),
        levelOne,
        reason: role.name,
      );
      expect(
        PayrollPolicy.forShift(
          role: role,
          workerLevel: -5,
          workerCount: 2,
        ),
        levelOne,
        reason: role.name,
      );
    }
  });
}
