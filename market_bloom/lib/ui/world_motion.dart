import 'dart:math';

import 'package:flutter/material.dart';

import '../game/game_controller.dart';
import '../game/game_models.dart';

/// Paint-only motion vocabulary for the living market world.
///
/// The simulation remains the source of truth. These profiles only translate
/// existing gameplay states into restrained visual motion and feedback.
enum WorldMotionActivity {
  idle,
  walking,
  carrying,
  shopping,
  queueing,
  paying,
  leaving,
  serving,
  stocking,
  cleaning,
  baking,
  managing,
  delivering,
  promoting,
}

@immutable
class WorldMotionProfile {
  const WorldMotionProfile({
    required this.activity,
    required this.moving,
    required this.bob,
    required this.sway,
    required this.pulse,
    required this.frame,
    required this.direction,
  });

  final WorldMotionActivity activity;
  final bool moving;
  final double bob;
  final double sway;
  final double pulse;
  final int frame;
  final double direction;

  bool get hasMotion => bob != 0 || sway != 0 || pulse != 0;
}

abstract final class WorldMotion {
  static WorldMotionProfile customer({
    required MarketCustomer customer,
    required double time,
    required bool reducedMotion,
    Offset? target,
  }) {
    final moving = switch (customer.phase) {
      CustomerPhase.entering || CustomerPhase.leaving => true,
      CustomerPhase.shopping => customer.phaseTime < 0.68,
      CustomerPhase.checkout => target == null
          ? true
          : (target - customer.position).distance > 0.025,
      CustomerPhase.paying => false,
    };
    final activity = switch (customer.phase) {
      CustomerPhase.entering => WorldMotionActivity.walking,
      CustomerPhase.shopping => moving
          ? WorldMotionActivity.shopping
          : WorldMotionActivity.idle,
      CustomerPhase.checkout => moving
          ? WorldMotionActivity.queueing
          : WorldMotionActivity.idle,
      CustomerPhase.paying => WorldMotionActivity.paying,
      CustomerPhase.leaving => WorldMotionActivity.leaving,
    };
    final direction = target == null
        ? 0.0
        : (target.dx - customer.position.dx).clamp(-1.0, 1.0);
    if (reducedMotion) {
      return WorldMotionProfile(
        activity: activity,
        moving: moving,
        bob: 0,
        sway: 0,
        pulse: 0,
        frame: 0,
        direction: direction,
      );
    }
    final cadence = moving ? 8.2 : 2.2;
    final wave = sin(time * cadence + customer.id * 0.83);
    return WorldMotionProfile(
      activity: activity,
      moving: moving,
      bob: wave * (moving ? 0.95 : 0.28),
      sway: moving ? wave * 0.012 : wave * 0.004,
      pulse: customer.phase == CustomerPhase.paying
          ? (sin(time * 7 + customer.id) + 1) / 2
          : 0,
      frame: moving ? ((time * cadence / pi).floor() & 1) : 0,
      direction: direction,
    );
  }

  static WorldMotionProfile player({
    required bool walking,
    required bool carrying,
    required Offset movement,
    required double time,
    required bool reducedMotion,
  }) {
    final activity = carrying
        ? WorldMotionActivity.carrying
        : walking
        ? WorldMotionActivity.walking
        : WorldMotionActivity.idle;
    final direction = movement.dx.abs() < 0.03
        ? 0.0
        : movement.dx.sign.toDouble();
    if (reducedMotion) {
      return WorldMotionProfile(
        activity: activity,
        moving: walking,
        bob: 0,
        sway: 0,
        pulse: 0,
        frame: walking ? 1 : 0,
        direction: direction,
      );
    }
    final wave = sin(time * (walking ? 10.8 : 2.0));
    return WorldMotionProfile(
      activity: activity,
      moving: walking,
      bob: wave * (walking ? 1.15 : carrying ? 0.24 : 0.34),
      sway: walking ? wave * 0.014 : wave * 0.004,
      pulse: carrying ? (sin(time * 3.2) + 1) / 2 : 0,
      frame: walking ? 1 + ((time * 8).floor() & 1) : carrying ? 3 : 0,
      direction: direction,
    );
  }

  static WorldMotionProfile staff({
    required StaffRole role,
    required StaffStatus status,
    required int workerIndex,
    required double time,
    required bool reducedMotion,
  }) {
    final activity = switch (status) {
      StaffStatus.serving => WorldMotionActivity.serving,
      StaffStatus.stocking => WorldMotionActivity.stocking,
      StaffStatus.cleaning => WorldMotionActivity.cleaning,
      StaffStatus.baking => WorldMotionActivity.baking,
      StaffStatus.managing => WorldMotionActivity.managing,
      StaffStatus.delivering => WorldMotionActivity.delivering,
      StaffStatus.promoting => WorldMotionActivity.promoting,
      _ => WorldMotionActivity.idle,
    };
    final moving = switch (status) {
      StaffStatus.stocking ||
      StaffStatus.cleaning ||
      StaffStatus.delivering => true,
      _ => false,
    };
    if (reducedMotion) {
      return WorldMotionProfile(
        activity: activity,
        moving: moving,
        bob: 0,
        sway: 0,
        pulse: 0,
        frame: 0,
        direction: 0,
      );
    }
    final seed = role.index * 0.71 + workerIndex;
    final cadence = moving ? 8.0 : activity == WorldMotionActivity.idle ? 1.8 : 5.8;
    final wave = sin(time * cadence + seed);
    return WorldMotionProfile(
      activity: activity,
      moving: moving,
      bob: wave * (moving ? 0.9 : 0.42),
      sway: wave * (moving ? 0.012 : 0.007),
      pulse: (sin(time * 4.5 + seed) + 1) / 2,
      frame: moving ? ((time * cadence / pi).floor() & 1) : 0,
      direction: role == StaffRole.stocker || role == StaffRole.courier
          ? cos(time * 0.7 + seed).sign.toDouble()
          : 0,
    );
  }

  static Offset customerTarget(GameController game, MarketCustomer customer) {
    return switch (customer.phase) {
      CustomerPhase.entering || CustomerPhase.shopping =>
        game.departmentZone(
              customer.currentDepartment ?? DepartmentType.generalGoods,
            ) +
            const Offset(0, -0.10),
      CustomerPhase.checkout || CustomerPhase.paying =>
        game.checkoutStationZone(
              customer.checkoutStationId ??
                  GameController.primaryCheckoutStationId,
            ) +
            const Offset(-0.03, 0.10),
      CustomerPhase.leaving => GameController.exit,
    };
  }
}

@immutable
class WorldMotionSnapshot {
  const WorldMotionSnapshot({
    required this.reducedMotion,
    required this.player,
    required this.customers,
    required this.staff,
    required this.activeCheckouts,
    required this.stockingActive,
  });

  final bool reducedMotion;
  final WorldMotionProfile player;
  final List<WorldMotionProfile> customers;
  final Map<StaffRole, WorldMotionProfile> staff;
  final int activeCheckouts;
  final bool stockingActive;
}

/// Stable diagnostics used by widget tests without coupling tests to pixels.
abstract final class WorldMotionDiagnostics {
  static WorldMotionSnapshot snapshot(
    GameController game, {
    required bool reducedMotion,
  }) {
    final player = WorldMotion.player(
      walking: game.movement.distance > 0.05,
      carrying: game.carried > 0,
      movement: game.movement,
      time: game.totalPlaySeconds,
      reducedMotion: reducedMotion,
    );
    final customers = <WorldMotionProfile>[
      for (final customer in game.customers)
        WorldMotion.customer(
          customer: customer,
          time: game.totalPlaySeconds,
          reducedMotion: reducedMotion,
          target: WorldMotion.customerTarget(game, customer),
        ),
    ];
    final staff = <StaffRole, WorldMotionProfile>{
      for (final role in StaffRole.values)
        if (game.isStaffHired(role))
          role: WorldMotion.staff(
            role: role,
            status: game.staffStatus(role),
            workerIndex: 0,
            time: game.totalPlaySeconds,
            reducedMotion: reducedMotion,
          ),
    };
    return WorldMotionSnapshot(
      reducedMotion: reducedMotion,
      player: player,
      customers: customers,
      staff: staff,
      activeCheckouts: game.customers
          .where((customer) => customer.phase == CustomerPhase.paying)
          .length,
      stockingActive:
          game.carried > 0 ||
          game.stockerCarried > 0 ||
          game.staffStatus(StaffRole.stocker) == StaffStatus.stocking,
    );
  }
}
