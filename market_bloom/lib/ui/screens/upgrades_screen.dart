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
                affordable: controller.canBuyUpgrade(offer.type),
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
    final loc = AppLocalizations.of(context);
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
                      loc.upgradeTitle(offer.type),
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    Text(
                      '${loc.level} ${offer.level}/10',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      '${_localizedSubtitle(loc, offer)} → ${_localizedNextSubtitle(loc, offer)}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 11,
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

  String _localizedSubtitle(AppLocalizations loc, UpgradeOffer currentOffer) {
    return switch (currentOffer.type) {
      UpgradeType.bag => loc.carryProducts.replaceFirst(
        '{capacity}',
        '${3 + currentOffer.level}',
      ),
      UpgradeType.shelf => '${loc.capacity}: ${4 + currentOffer.level * 2}',
      UpgradeType.price => loc.profitPerSale.replaceFirst(
        '{value}',
        '${4 + currentOffer.level * 2}',
      ),
      UpgradeType.speed => loc.movementSpeed.replaceFirst(
        '{value}',
        '${currentOffer.level * 8}',
      ),
      UpgradeType.checkout => loc.serviceTime.replaceFirst(
        '{value}',
        currentOffer.subtitle.split('s').first,
      ),
      UpgradeType.restock => loc.keepShelvesFilled,
    };
  }

  String _localizedNextSubtitle(
    AppLocalizations loc,
    UpgradeOffer currentOffer,
  ) {
    final nextLevel = currentOffer.level + 1;
    return switch (currentOffer.type) {
      UpgradeType.bag => loc.carryProducts.replaceFirst(
        '{capacity}',
        '${3 + nextLevel}',
      ),
      UpgradeType.shelf => '${loc.capacity}: ${4 + nextLevel * 2}',
      UpgradeType.price => loc.profitPerSale.replaceFirst(
        '{value}',
        '${4 + nextLevel * 2}',
      ),
      UpgradeType.speed => loc.movementSpeed.replaceFirst(
        '{value}',
        '${nextLevel * 8}',
      ),
      UpgradeType.checkout => loc.serviceTime.replaceFirst(
        '{value}',
        _nextCheckoutSeconds(currentOffer),
      ),
      UpgradeType.restock => loc.keepShelvesFilled,
    };
  }

  String _nextCheckoutSeconds(UpgradeOffer offer) {
    final current = double.tryParse(offer.subtitle.split('s').first) ?? 1;
    return current > 0.38
        ? (current - 0.09).clamp(0.38, 9.99).toStringAsFixed(2)
        : '0.38';
  }
}
