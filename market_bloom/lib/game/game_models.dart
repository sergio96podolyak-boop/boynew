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

  final int id;
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
