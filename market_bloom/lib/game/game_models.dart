import 'package:flutter/material.dart';

enum CustomerPhase { entering, shopping, checkout, paying, leaving }

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

enum StaffRole { cashier, stocker, cleaner, manager }

class StaffMember {
  StaffMember({required this.role, this.level = 0, this.hired = false});

  final StaffRole role;
  int level;
  bool hired;

  String get name {
    return switch (role) {
      StaffRole.cashier => 'Cashier',
      StaffRole.stocker => 'Stocker',
      StaffRole.cleaner => 'Cleaner',
      StaffRole.manager => 'Manager',
    };
  }

  int get hireCost => 90 + level * 35;

  int get upgradeCost => 70 + level * 45;

  String get summary {
    return switch (role) {
      StaffRole.cashier => 'Speeds checkout and tips',
      StaffRole.stocker => 'Restocks shelves faster',
      StaffRole.cleaner => 'Keeps satisfaction steady',
      StaffRole.manager => 'Boosts global efficiency',
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
  });

  final DepartmentType type;
  final String name;
  final String description;
  final int unlockLevel;
  final int unlockCost;
  final IconData icon;
  final Color color;
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

/// Static catalog of department definitions with unlock requirements.
///
/// The unlock levels mirror the existing store-level gating used in
/// [MarketPainter._drawExpansion] (bakery at level 3) and extend it to
/// all departments represented by [DepartmentType].
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
    ),
    DepartmentDefinition(
      type: DepartmentType.bakery,
      name: 'Bakery',
      description: 'Fresh bread and pastries.',
      unlockLevel: 3,
      unlockCost: 200,
      icon: Icons.bakery_dining_rounded,
      color: Color(0xFFF6A623),
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
