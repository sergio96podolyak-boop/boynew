import 'package:flutter/material.dart';

import '../../game/game_controller.dart';
import '../../services/app_localizations.dart';
import '../../services/monetization_service.dart';
import '../widgets/pressable_scale.dart';

/// Preview shop interface for PoMarket.
///
/// Shows example coin/gem packs and rewarded-ad actions using the existing
/// [MonetizationService] abstractions. Does not process real money or fake
/// successful purchases. Rewarded-ad rewards are only granted through the
/// existing monetization service success callback.
class ShopScreen extends StatelessWidget {
  const ShopScreen({super.key, required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final rewardCooldown = controller.rewardCooldownRemaining(
      RewardPlacement.instantCoins,
    );
    return Scaffold(
      appBar: AppBar(title: Text(loc.shopTitle)),
      body: AnimatedBuilder(
        animation: controller,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (controller.isMonetizationPreview) _PreviewBadge(loc: loc),
            const SizedBox(height: 8),
            Text(
              controller.storePurchasesAvailable
                  ? loc.secureStorePurchases
                  : '${loc.previewModeDesc} ${loc.mobileStoreAvailability}',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 16),
            _StoreCard(
              icon: Icons.ondemand_video_rounded,
              color: const Color(0xFFE85D75),
              title: loc.freeBonus,
              subtitle:
                  '${loc.freeBonusSubtitle} — ${loc.rewardCoinsBenefit.replaceFirst('{value}', '${controller.instantAdReward}')}',
              buttonLabel: controller.rewardInProgress
                  ? loc.loading
                  : !controller.rewardedAdsAvailable
                  ? loc.mobileFeaturePreview
                  : rewardCooldown > Duration.zero
                  ? loc.retryIn.replaceFirst(
                      '{seconds}',
                      '${rewardCooldown.inSeconds + 1}',
                    )
                  : loc.watchAndEarn,
              onTap:
                  controller.rewardInProgress ||
                      !controller.canClaimReward(RewardPlacement.instantCoins)
                  ? null
                  : () async {
                      final reward = controller.instantAdReward;
                      final completed = await controller.claimInstantAdReward();
                      if (!context.mounted) return;
                      if (completed) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              loc.coinsEarned.replaceFirst(
                                '{value}',
                                '$reward',
                              ),
                            ),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                    },
            ),
            const SizedBox(height: 12),
            _ShopSectionLabel(label: loc.permanentBenefits),
            const SizedBox(height: 4),
            _StoreCard(
              icon: Icons.block_rounded,
              color: const Color(0xFF5B8DEF),
              title: loc.noAds,
              subtitle: controller.adsRemoved ? loc.owned : loc.oneTimePurchase,
              buttonLabel: controller.adsRemoved
                  ? loc.owned
                  : controller.storePrice(StoreProduct.noAds) ??
                        loc.setupRequired,
              onTap:
                  !controller.storePurchasesAvailable ||
                      controller.adsRemoved ||
                      controller.storePurchaseInProgress
                  ? null
                  : () => _purchase(context, StoreProduct.noAds),
            ),
            const SizedBox(height: 12),
            _ShopSectionLabel(label: loc.starterOffers),
            const SizedBox(height: 4),
            _StoreCard(
              icon: Icons.rocket_launch_rounded,
              color: const Color(0xFFF6A623),
              title: loc.starterPack,
              subtitle: loc.starterPackDesc,
              buttonLabel:
                  controller.storePrice(StoreProduct.starterPack) ??
                  loc.previewPrice2,
              onTap:
                  !controller.storePurchasesAvailable ||
                      controller.storePurchaseInProgress
                  ? null
                  : () => _purchase(context, StoreProduct.starterPack),
            ),
            const SizedBox(height: 12),
            _ShopSectionLabel(label: loc.coinPacks),
            const SizedBox(height: 4),
            _StoreCard(
              icon: Icons.monetization_on_rounded,
              color: const Color(0xFF38B879),
              title: loc.coinPack,
              subtitle: loc.coinPackDesc,
              buttonLabel:
                  controller.storePrice(StoreProduct.coinPack) ??
                  loc.previewPrice,
              onTap:
                  !controller.storePurchasesAvailable ||
                      controller.storePurchaseInProgress
                  ? null
                  : () => _purchase(context, StoreProduct.coinPack),
            ),
            const SizedBox(height: 12),
            _ShopSectionLabel(label: loc.gemPacks),
            const SizedBox(height: 4),
            _StoreCard(
              icon: Icons.diamond_rounded,
              color: const Color(0xFF8B66D8),
              title: loc.gemPack,
              subtitle: loc.gemPackDesc,
              buttonLabel:
                  controller.storePrice(StoreProduct.gemPack) ??
                  loc.previewPrice,
              onTap:
                  !controller.storePurchasesAvailable ||
                      controller.storePurchaseInProgress
                  ? null
                  : () => _purchase(context, StoreProduct.gemPack),
            ),
            const SizedBox(height: 12),
            _ShopSectionLabel(label: loc.emergencySupplies),
            const SizedBox(height: 4),
            _StoreCard(
              icon: Icons.inventory_2_rounded,
              color: const Color(0xFF5B8DEF),
              title: loc.emergencySupplyPack,
              subtitle: loc.emergencySupplyPackDesc,
              buttonLabel:
                  controller.storePrice(StoreProduct.emergencySupply) ??
                  loc.previewPrice2,
              onTap:
                  !controller.storePurchasesAvailable ||
                      controller.storePurchaseInProgress
                  ? null
                  : () => _purchase(context, StoreProduct.emergencySupply),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed:
                  controller.storePurchasesAvailable &&
                      !controller.storePurchaseInProgress
                  ? () => _restore(context)
                  : null,
              icon: const Icon(Icons.restore_rounded),
              label: Text(loc.restorePurchases),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _purchase(BuildContext context, StoreProduct product) async {
    final purchased = await controller.purchaseStoreProduct(product);
    if (!context.mounted) return;
    final loc = AppLocalizations.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          purchased
              ? loc.purchaseComplete
              : controller.lastPurchaseState == PurchaseState.cancelled
              ? loc.purchaseCancelled
              : loc.purchaseFailed,
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _restore(BuildContext context) async {
    final restored = await controller.restoreStorePurchases();
    if (!context.mounted) return;
    final loc = AppLocalizations.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          restored
              ? loc.restorePurchasesSuccess
              : controller.storePurchasesAvailable
              ? loc.restorePurchasesNone
              : loc.restorePurchasesUnavailable,
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

class _PreviewBadge extends StatelessWidget {
  const _PreviewBadge({required this.loc});

  final AppLocalizations loc;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFFFFF3E0),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const Icon(Icons.info_rounded, color: Color(0xFFE65100)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                loc.previewMode,
                style: const TextStyle(
                  color: Color(0xFFE65100),
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShopSectionLabel extends StatelessWidget {
  const _ShopSectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 4, top: 4),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFF315F4A),
          fontSize: 12,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _StoreCard extends StatelessWidget {
  const _StoreCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.buttonLabel,
    this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final String buttonLabel;
  final Future<void> Function()? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final details = Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: color,
                  child: Icon(icon, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
            final action = PressableScale(
              child: FilledButton(
                onPressed: onTap == null ? null : () => onTap!(),
                child: Text(
                  buttonLabel,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            );

            if (constraints.maxWidth < 310) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [details, const SizedBox(height: 10), action],
              );
            }
            return Row(
              children: [
                Expanded(child: details),
                const SizedBox(width: 10),
                action,
              ],
            );
          },
        ),
      ),
    );
  }
}
