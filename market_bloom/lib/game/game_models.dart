import 'dart:math';

import 'package:flutter/material.dart';

enum CustomerPhase { entering, shopping, checkout, paying, leaving }

enum CheckoutOperator { player, cashier }

class MarketCustomer {
  MarketCustomer({
    required this.id,
    required this.position,
    required this.color,
    this.patience = 7.4,
    this.satisfaction = 1.0,
    this.isVip = false,
    this.tipValue = 0,
    this.basketCount = 1,
    this.emotion = 'neutral',
  });

  int id;
  Offset position;
  final Color color;
  CustomerPhase phase = CustomerPhase.entering;
  double phaseTime = 0;
  bool hasProduct = false;
  double patience;
  double satisfaction;
  bool isVip;
  int tipValue;
  int basketCount;
  String emotion;
  CheckoutOperator? checkoutOperator;
}

enum UpgradeType { bag, shelf, price, speed, checkout, restock }

class UpgradeOffer {
  const UpgradeOffer({
    required this.type,
    required this.title,
    required this.subtitle,
    required this.level,
    required this.cost,
    required this.icon,
    required this.color,
  });

  final UpgradeType type;
  final String title;
  final String subtitle;
  final int level;
  final int cost;
  final IconData icon;
  final Color color;
}

class Quest {
  const Quest({
    required this.title,
    required this.progress,
    required this.target,
    required this.reward,
  });

  final String title;
  final int progress;
  final int target;
  final int reward;

  bool get completed => progress >= target;
  double get fraction => (progress / target).clamp(0, 1);
}

enum StaffRole { cashier, stocker, cleaner, baker, manager, courier, promoter }

enum StaffAssignment {
  checkout,
  shelves,
  floor,
  bakery,
  office,
  delivery,
  entrance,
}

enum StaffStatus {
  notHired,
  idle,
  serving,
  stocking,
  waitingForStock,
  waitingForShelf,
  cleaning,
  baking,
  managing,
  delivering,
  promoting,
}

class StaffMember {
  StaffMember({
    required this.role,
    String? id,
    this.level = 0,
    this.hired = false,
    this.workerCount = 0,
    StaffAssignment? assignment,
  }) : id = id ?? 'staff-${role.name}',
       assignment = assignment ?? defaultAssignmentFor(role) {
    if (hired && workerCount < 1) {
      workerCount = 1;
    } else if (workerCount > 0) {
      hired = true;
    }
  }

  final String id;
  final StaffRole role;
  int level;
  bool hired;
  int workerCount;
  StaffAssignment assignment;

  static StaffAssignment defaultAssignmentFor(StaffRole role) {
    return switch (role) {
      StaffRole.cashier => StaffAssignment.checkout,
      StaffRole.stocker => StaffAssignment.shelves,
      StaffRole.cleaner => StaffAssignment.floor,
      StaffRole.baker => StaffAssignment.bakery,
      StaffRole.manager => StaffAssignment.office,
      StaffRole.courier => StaffAssignment.delivery,
      StaffRole.promoter => StaffAssignment.entrance,
    };
  }

  String get name {
    return switch (role) {
      StaffRole.cashier => 'Cashier',
      StaffRole.stocker => 'Stocker',
      StaffRole.cleaner => 'Cleaner',
      StaffRole.baker => 'Baker',
      StaffRole.manager => 'Manager',
      StaffRole.courier => 'Courier',
      StaffRole.promoter => 'Promoter',
    };
  }

  int get hireCost => 90 + level * 35;

  int get additionalHireCost => 80 + workerCount * 55 + level * 20;

  int get upgradeCost => 70 + level * 45;

  int get productivity => max(0, level) * max(0, workerCount);

  String get summary {
    return switch (role) {
      StaffRole.cashier => 'Speeds checkout and tips',
      StaffRole.stocker => 'Restocks shelves faster',
      StaffRole.cleaner => 'Keeps satisfaction steady',
      StaffRole.baker => 'Bakes fresh goods faster',
      StaffRole.manager => 'Boosts global efficiency',
      StaffRole.courier => 'Speeds up stock deliveries',
      StaffRole.promoter => 'Attracts more customers',
    };
  }
}

enum DepartmentType {
  generalGoods,
  bakery,
  produce,
  refrigerated,
  beauty,
  electronics,
}

class DepartmentDefinition {
  const DepartmentDefinition({
    required this.type,
    required this.name,
    required this.description,
    required this.unlockLevel,
    required this.unlockCost,
    required this.icon,
    required this.color,
    this.autoUnlock = false,
  });

  final DepartmentType type;
  final String name;
  final String description;
  final int unlockLevel;
  final int unlockCost;
  final IconData icon;
  final Color color;
  final bool autoUnlock;
}

class DepartmentState {
  DepartmentState({required this.type, this.level = 0, this.unlocked = false});

  final DepartmentType type;
  int level;
  bool unlocked;
}

class InventoryDelivery {
  InventoryDelivery({
    required this.id,
    required this.category,
    required this.quantity,
    required this.cost,
    required this.readyAt,
    this.completed = false,
  });

  final String id;
  final String category;
  final int quantity;
  final int cost;
  final DateTime readyAt;
  bool completed;
}

/// Central progression and economy rules shared by the controller and UI.
abstract final class GameBalance {
  static const salesPerStoreLevel = 8;
  static const upgradesPerStoreLevel = 4;
  static const staffUnlockLevel = 3;
  static const bakeryUnlockLevel = 3;
  static const bakeryReadyCapacity = 4;
  static const bakeryStarterStock = 3;
  static const bakeryProductionInterval = Duration(seconds: 8);
  static const bakeryCollectionSeconds = 0.45;
  static const starterStorageStock = 12;
  static const quickRestockQuantity = 6;
  static const quickRestockCost = 20;
  static const emergencyStockQuantity = 4;
  static const emergencyStockCooldown = Duration(minutes: 10);
  static const baseCheckoutSeconds = 1.05;
  static const minimumCheckoutSeconds = 0.38;
  static const inventoryOrderDelay = Duration(seconds: 6);
  static const maxWorkersPerRole = 3;

  static int staffRoleUnlockLevel(StaffRole role) {
    return switch (role) {
      StaffRole.cashier || StaffRole.stocker => staffUnlockLevel,
      StaffRole.cleaner || StaffRole.baker => 4,
      StaffRole.manager => 5,
      StaffRole.courier => 6,
      StaffRole.promoter => 7,
    };
  }

  static int availableWorkerSlots(StaffRole role, int storeLevel) {
    final unlockLevel = staffRoleUnlockLevel(role);
    if (storeLevel < unlockLevel) {
      return 0;
    }
    return (1 + (storeLevel - unlockLevel) ~/ 2).clamp(1, maxWorkersPerRole);
  }

  static int? nextWorkerSlotLevel(
    StaffRole role,
    int storeLevel,
    int workerCount,
  ) {
    if (workerCount >= maxWorkersPerRole) {
      return null;
    }
    final requiredLevel = staffRoleUnlockLevel(role) + workerCount * 2;
    return storeLevel >= requiredLevel ? null : requiredLevel;
  }
}

/// Static catalog of department definitions with centralized unlock rules.
abstract final class DepartmentCatalog {
  static const List<DepartmentDefinition> all = <DepartmentDefinition>[
    DepartmentDefinition(
      type: DepartmentType.generalGoods,
      name: 'General Goods',
      description: 'The foundation of your market.',
      unlockLevel: 1,
      unlockCost: 0,
      icon: Icons.storefront_rounded,
      color: Color(0xFF5B8DEF),
      autoUnlock: true,
    ),
    DepartmentDefinition(
      type: DepartmentType.bakery,
      name: 'Bakery',
      description: 'Fresh bread and pastries.',
      unlockLevel: GameBalance.bakeryUnlockLevel,
      unlockCost: 0,
      icon: Icons.bakery_dining_rounded,
      color: Color(0xFFF6A623),
      autoUnlock: true,
    ),
    DepartmentDefinition(
      type: DepartmentType.produce,
      name: 'Produce',
      description: 'Fresh fruits and vegetables.',
      unlockLevel: 5,
      unlockCost: 400,
      icon: Icons.eco_rounded,
      color: Color(0xFF43AA8B),
    ),
    DepartmentDefinition(
      type: DepartmentType.refrigerated,
      name: 'Refrigerated',
      description: 'Cold storage for perishables.',
      unlockLevel: 7,
      unlockCost: 600,
      icon: Icons.ac_unit_rounded,
      color: Color(0xFF3F88C5),
    ),
    DepartmentDefinition(
      type: DepartmentType.beauty,
      name: 'Beauty',
      description: 'Cosmetics and personal care.',
      unlockLevel: 9,
      unlockCost: 800,
      icon: Icons.spa_rounded,
      color: Color(0xFFE85D75),
    ),
    DepartmentDefinition(
      type: DepartmentType.electronics,
      name: 'Electronics',
      description: 'Gadgets and tech accessories.',
      unlockLevel: 11,
      unlockCost: 1000,
      icon: Icons.devices_rounded,
      color: Color(0xFF8B66D8),
    ),
  ];

  static final Map<DepartmentType, DepartmentDefinition> byType =
      <DepartmentType, DepartmentDefinition>{
        for (final definition in all) definition.type: definition,
      };

  static DepartmentDefinition? find(DepartmentType type) => byType[type];
}
