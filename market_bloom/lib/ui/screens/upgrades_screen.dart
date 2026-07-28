import 'package:flutter/material.dart';

import '../../game/game_controller.dart';
import '../../game/game_models.dart';
import '../../services/app_localizations.dart';
import '../widgets/pressable_scale.dart';

class UpgradesScreen extends StatelessWidget {
  const UpgradesScreen({super.key, required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(loc.upgradeYourBusiness)),
      body: AnimatedBuilder(
        animation: controller,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              loc.investToServe,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            for (final offer in controller.upgrades)
              _UpgradeTile(
                offer: offer,
                affordable: controller.coins >= offer.cost,
                onBuy: () {
                  final purchased = controller.buyUpgrade(offer.type);
                  if (!purchased) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(loc.notEnoughCoins),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _UpgradeTile extends StatelessWidget {
  const _UpgradeTile({
    required this.offer,
    required this.affordable,
    required this.onBuy,
  });

  final UpgradeOffer offer;
  final bool affordable;
  final VoidCallback onBuy;

  @override
  Widget build(BuildContext context) {
    final color = offer.color;
    return PressableScale(
      child: Card(
        color: color.withValues(alpha: 0.09),
        shape: RoundedRectangleBorder(
          side: BorderSide(color: color.withValues(alpha: 0.22)),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(offer.icon, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      offer.title,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    Text(
                      '${offer.subtitle} · Level ${offer.level}',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: affordable ? onBuy : null,
                style: FilledButton.styleFrom(
                  backgroundColor: affordable
                      ? const Color(0xFF315F4A)
                      : Theme.of(context).disabledColor,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                icon: const Icon(Icons.monetization_on_rounded, size: 16),
                label: Text('${offer.cost}'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
