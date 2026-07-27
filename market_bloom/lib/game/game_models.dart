import 'package:flutter/material.dart';

enum CustomerPhase { entering, shopping, checkout, paying, leaving }

class MarketCustomer {
  MarketCustomer({
    required this.id,
    required this.position,
    required this.color,
  });

  final int id;
  Offset position;
  final Color color;
  CustomerPhase phase = CustomerPhase.entering;
  double phaseTime = 0;
  bool hasProduct = false;
}

enum UpgradeType { bag, shelf, price, speed }

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
