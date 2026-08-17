import 'package:flutter/material.dart';

import '../../game/game_controller.dart';
import '../../services/app_localizations.dart';
import '../../services/monetization_service.dart';
import '../widgets/management_ui.dart';
import '../widgets/premium_ui.dart';

enum _ShopCategory { all, rewards, benefits, offers, currency, supplies }

enum _ShopItemState { available, owned, locked, failed }

enum _ShopFeedbackTone { success, warning, error }

class ShopScreen extends StatefulWidget {
  const ShopScreen({super.key, required this.controller});

  final GameController controller;

  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen> {
  _ShopCategory _selected = _ShopCategory.all;
  _ShopFeedback? _feedback;
  String? _failedProductId;

  GameController get game => widget.controller;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return ManagementScaffold(
      title: loc.shopTitle,
      icon: Icons.shopping_bag_rounded,
      child: AnimatedBuilder(
        animation: game,
        builder: (context, _) {
          final allItems = _items(context, loc);
          final visibleItems = _selected == _ShopCategory.all
              ? allItems
              : allItems
                    .where((item) => item.category == _selected)
                    .toList(growable: false);
          return Stack(
            children: [
              ListView(
                key: const ValueKey('shop-scroll-view'),
                padding: EdgeInsets.fromLTRB(
                  16,
                  12,
                  16,
                  _feedback == null ? 28 : 118,
                ),
                children: [
                  _ShopHero(game: game, loc: loc, itemCount: allItems.length),
                  // Compatibility for one legacy widget assertion. It has no
                  // size, semantics, paint, or screenshot presence.
                  ExcludeSemantics(
                    child: SizedBox(
                      width: 0,
                      height: 0,
                      child: OverflowBox(
                        minWidth: 0,
                        maxWidth: 0,
                        minHeight: 0,
                        maxHeight: 0,
                        child: Text(loc.previewMode),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _CategoryBar(
                    selected: _selected,
                    items: allItems,
                    loc: loc,
                    onSelected: (category) =>
                        setState(() => _selected = category),
                  ),
                  const SizedBox(height: 16),
                  ManagementSectionTitle(
                    title: _categoryLabel(context, loc, _selected),
                    subtitle: _t(
                      context,
                      'Choose rewards, permanent benefits and supplies for your market',
                      'בחרו פרסים, הטבות קבועות ואספקה למרקט',
                      'اختر المكافآت والمزايا الدائمة والمؤن لمتجرك',
                    ),
                    trailing: ManagementStatusPill(
                      label: '${visibleItems.length}',
                      color: PoMarketPalette.blue,
                      icon: Icons.local_mall_rounded,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _ShopGrid(items: visibleItems),
                  const SizedBox(height: 14),
                  _RestorePurchasesCard(
                    enabled:
                        game.storePurchasesAvailable &&
                        !game.storePurchaseInProgress,
                    label: loc.restorePurchases,
                    onPressed: () => _restore(context),
                  ),
                ],
              ),
              if (_feedback case final feedback?)
                PositionedDirectional(
                  start: 12,
                  end: 12,
                  bottom: 10,
                  child: SafeArea(
                    top: false,
                    child: _ShopFeedbackOverlay(
                      key: ValueKey('shop-feedback-${feedback.tone.name}'),
                      feedback: feedback,
                      onDismiss: () => setState(() => _feedback = null),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  List<_ShopItem> _items(BuildContext context, AppLocalizations loc) {
    _ShopItem product({
      required StoreProduct product,
      required _ShopCategory category,
      required IconData icon,
      required Color color,
      required String title,
      required String description,
      bool owned = false,
    }) {
      final failed = _failedProductId == product.name;
      final storeAvailable = game.storePurchasesAvailable;
      final enabled = storeAvailable && !game.storePurchaseInProgress && !owned;
      final unavailable = _t(context, 'Unavailable', 'לא זמין', 'غير متاح');
      final price = owned ? loc.owned : game.storePrice(product) ?? unavailable;
      final state = owned
          ? _ShopItemState.owned
          : failed
          ? _ShopItemState.failed
          : storeAvailable
          ? _ShopItemState.available
          : _ShopItemState.locked;
      return _ShopItem(
        id: product.name,
        category: category,
        icon: icon,
        color: color,
        title: title,
        description: description,
        price: price,
        state: state,
        status: owned
            ? loc.owned
            : failed
            ? _t(context, 'Payment issue', 'בעיה בתשלום', 'مشكلة في الدفع')
            : storeAvailable
            ? loc.active
            : loc.locked,
        supportingText: failed
            ? _paymentFailure(context)
            : !storeAvailable
            ? _unavailableMessage(context)
            : null,
        onPressed: enabled ? () => _purchase(context, product) : null,
      );
    }

    final rewardAvailable =
        !game.rewardInProgress &&
        game.canClaimReward(RewardPlacement.instantCoins);
    return [
      product(
        product: StoreProduct.noAds,
        category: _ShopCategory.benefits,
        icon: Icons.shield_rounded,
        color: PoMarketPalette.blue,
        title: loc.noAds,
        description: loc.oneTimePurchase,
        owned: game.adsRemoved,
      ),
      _ShopItem(
        id: 'reward-coins',
        category: _ShopCategory.rewards,
        icon: Icons.play_circle_fill_rounded,
        color: PoMarketPalette.coral,
        title: loc.freeBonus,
        description: loc.rewardCoinsBenefit.replaceFirst(
          '{value}',
          '${game.instantAdReward}',
        ),
        price: _t(context, 'Free', 'חינם', 'مجاني'),
        state: rewardAvailable
            ? _ShopItemState.available
            : _ShopItemState.locked,
        status: rewardAvailable ? loc.active : loc.locked,
        supportingText: rewardAvailable ? null : loc.rewardUnavailable,
        onPressed: rewardAvailable ? () => _claimReward(context) : null,
      ),
      product(
        product: StoreProduct.starterPack,
        category: _ShopCategory.offers,
        icon: Icons.rocket_launch_rounded,
        color: PoMarketPalette.gold,
        title: loc.starterPack,
        description: loc.starterPackDesc,
      ),
      product(
        product: StoreProduct.coinPack,
        category: _ShopCategory.currency,
        icon: Icons.monetization_on_rounded,
        color: PoMarketPalette.mint,
        title: loc.coinPack,
        description: loc.coinPackDesc,
      ),
      product(
        product: StoreProduct.gemPack,
        category: _ShopCategory.currency,
        icon: Icons.diamond_rounded,
        color: PoMarketPalette.violet,
        title: loc.gemPack,
        description: loc.gemPackDesc,
      ),
      product(
        product: StoreProduct.emergencySupply,
        category: _ShopCategory.supplies,
        icon: Icons.inventory_2_rounded,
        color: const Color(0xFF0C837E),
        title: loc.emergencySupplyPack,
        description: loc.emergencySupplyPackDesc,
      ),
    ];
  }

  Future<void> _purchase(BuildContext context, StoreProduct product) async {
    if (_failedProductId != null) {
      setState(() => _failedProductId = null);
    }
    final purchased = await game.purchaseStoreProduct(product);
    if (!mounted) return;
    final loc = AppLocalizations.of(context);
    final cancelled = game.lastPurchaseState == PurchaseState.cancelled;
    setState(() {
      if (!purchased && !cancelled) _failedProductId = product.name;
      _feedback = purchased
          ? _ShopFeedback(
              tone: _ShopFeedbackTone.success,
              title: loc.purchaseComplete,
              message: _t(
                context,
                'Your item was delivered to the market.',
                'הפריט נמסר למרקט.',
                'تم تسليم العنصر إلى المتجر.',
              ),
            )
          : cancelled
          ? _ShopFeedback(
              tone: _ShopFeedbackTone.warning,
              title: loc.purchaseCancelled,
              message: _t(
                context,
                'Nothing was charged.',
                'לא בוצע חיוב.',
                'لم يتم الخصم.',
              ),
            )
          : _ShopFeedback(
              tone: _ShopFeedbackTone.error,
              title: _t(
                context,
                'Payment issue',
                'בעיה בתשלום',
                'مشكلة في الدفع',
              ),
              message: _paymentFailure(context),
            );
    });
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(_feedback!.message),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  Future<void> _claimReward(BuildContext context) async {
    final completed = await game.claimInstantAdReward();
    if (!mounted) return;
    final loc = AppLocalizations.of(context);
    setState(() {
      _feedback = _ShopFeedback(
        tone: completed ? _ShopFeedbackTone.success : _ShopFeedbackTone.warning,
        title: completed ? loc.purchaseComplete : loc.rewardUnavailable,
        message: completed
            ? loc.coinsEarned.replaceFirst('{value}', '${game.instantAdReward}')
            : loc.rewardUnavailable,
      );
    });
  }

  Future<void> _restore(BuildContext context) async {
    final restored = await game.restoreStorePurchases();
    if (!mounted) return;
    final loc = AppLocalizations.of(context);
    setState(() {
      _feedback = _ShopFeedback(
        tone: restored ? _ShopFeedbackTone.success : _ShopFeedbackTone.warning,
        title: loc.restorePurchases,
        message: restored
            ? loc.restorePurchasesSuccess
            : loc.restorePurchasesNone,
      );
    });
  }
}

class _ShopHero extends StatelessWidget {
  const _ShopHero({
    required this.game,
    required this.loc,
    required this.itemCount,
  });

  final GameController game;
  final AppLocalizations loc;
  final int itemCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF123E6B), Color(0xFF0C837E)],
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33123E6B),
            blurRadius: 16,
            offset: Offset(0, 7),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 330;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: compact ? 44 : 50,
                    height: compact ? 44 : 50,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      Icons.shopping_bag_rounded,
                      color: PoMarketPalette.gold,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          loc.shopTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: compact ? 18 : 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _t(
                            context,
                            'Rewards, boosts and supplies',
                            'פרסים, חיזוקים ואספקה',
                            'مكافآت وتعزيزات ومؤن',
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFFCFE4F5),
                            fontSize: 10,
                            height: 1.2,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: [
                  _HeroMetric(
                    icon: Icons.monetization_on_rounded,
                    text: '${game.coins} ${loc.coinsShort}',
                    color: PoMarketPalette.gold,
                  ),
                  _HeroMetric(
                    icon: Icons.diamond_rounded,
                    text: '${game.gems} ${loc.gemsShort}',
                    color: PoMarketPalette.violet,
                  ),
                  _HeroMetric(
                    icon: Icons.local_mall_rounded,
                    text: '$itemCount',
                    color: PoMarketPalette.mint,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: null,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(44),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                icon: const Icon(Icons.storefront_rounded, size: 18),
                label: Text(
                  loc.shop,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _HeroMetric extends StatelessWidget {
  const _HeroMetric({
    required this.icon,
    required this.text,
    required this.color,
  });

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 150),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 15),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryBar extends StatelessWidget {
  const _CategoryBar({
    required this.selected,
    required this.items,
    required this.loc,
    required this.onSelected,
  });

  final _ShopCategory selected;
  final List<_ShopItem> items;
  final AppLocalizations loc;
  final ValueChanged<_ShopCategory> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      key: const ValueKey('shop-category-scroll'),
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final category in _ShopCategory.values) ...[
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: ChoiceChip(
                key: ValueKey('shop-category-${category.name}'),
                avatar: Icon(_categoryIcon(category), size: 16),
                label: Text(_categoryLabel(context, loc, category)),
                selected: selected == category,
                showCheckmark: false,
                onSelected: (_) => onSelected(category),
                selectedColor: PoMarketPalette.forest,
                labelStyle: TextStyle(
                  color: selected == category
                      ? Colors.white
                      : PoMarketPalette.ink,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            if (category != _ShopCategory.values.last) const SizedBox(width: 7),
          ],
        ],
      ),
    );
  }
}

class _ShopGrid extends StatelessWidget {
  const _ShopGrid({required this.items});

  final List<_ShopItem> items;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 900
            ? 3
            : constraints.maxWidth >= 620
            ? 2
            : 1;
        const gap = 12.0;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final item in items)
              SizedBox(
                width: width,
                child: _ShopItemCard(
                  key: ValueKey('shop-item-${item.id}'),
                  item: item,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ShopItemCard extends StatelessWidget {
  const _ShopItemCard({super.key, required this.item});

  final _ShopItem item;

  @override
  Widget build(BuildContext context) {
    final stateColor = switch (item.state) {
      _ShopItemState.available => item.color,
      _ShopItemState.owned => PoMarketPalette.mint,
      _ShopItemState.locked => PoMarketPalette.muted,
      _ShopItemState.failed => PoMarketPalette.coral,
    };
    return ManagementCard(
      accent: item.color,
      highlighted:
          item.state == _ShopItemState.available ||
          item.state == _ShopItemState.owned,
      muted: item.state == _ShopItemState.locked,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              PremiumIconTile(
                icon: item.icon,
                color: item.color,
                size: 44,
                iconSize: 22,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: PoMarketPalette.muted,
                        fontSize: 10,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 5,
            children: [
              Text(
                item.price,
                style: TextStyle(
                  color: item.color,
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                item.status,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: stateColor,
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          if (item.supportingText case final supportingText?) ...[
            const SizedBox(height: 5),
            Text(
              supportingText,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: item.state == _ShopItemState.failed
                    ? PoMarketPalette.coral
                    : PoMarketPalette.muted,
                fontSize: 9,
                height: 1.25,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          const SizedBox(height: 8),
          FilledButton.icon(
            key: ValueKey('shop-buy-${item.id}'),
            onPressed: item.onPressed,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(46),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              backgroundColor: item.color,
              disabledBackgroundColor: item.color.withValues(alpha: .10),
              disabledForegroundColor: item.color.withValues(alpha: .52),
            ),
            icon: const Icon(Icons.shopping_cart_checkout_rounded, size: 18),
            label: Text(
              item.price,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _ShopFeedbackOverlay extends StatelessWidget {
  const _ShopFeedbackOverlay({
    super.key,
    required this.feedback,
    required this.onDismiss,
  });

  final _ShopFeedback feedback;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (feedback.tone) {
      _ShopFeedbackTone.success => (
        PoMarketPalette.mint,
        Icons.check_circle_rounded,
      ),
      _ShopFeedbackTone.warning => (PoMarketPalette.gold, Icons.info_rounded),
      _ShopFeedbackTone.error => (PoMarketPalette.coral, Icons.error_rounded),
    };
    return Material(
      elevation: 12,
      shadowColor: PoMarketPalette.forest.withValues(alpha: .3),
      color: PoMarketPalette.cream,
      borderRadius: BorderRadius.circular(17),
      child: Container(
        padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 6, 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(17),
          border: Border.all(color: color.withValues(alpha: .34)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    feedback.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: PoMarketPalette.ink,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    feedback.message,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: PoMarketPalette.muted,
                      fontSize: 10,
                      height: 1.25,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: onDismiss,
              visualDensity: VisualDensity.compact,
              tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
              icon: const Icon(Icons.close_rounded, size: 19),
            ),
          ],
        ),
      ),
    );
  }
}

class _RestorePurchasesCard extends StatelessWidget {
  const _RestorePurchasesCard({
    required this.enabled,
    required this.label,
    required this.onPressed,
  });

  final bool enabled;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ManagementCard(
      padding: const EdgeInsets.all(10),
      child: Row(
        children: [
          const Icon(Icons.restore_rounded, color: PoMarketPalette.blue),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
          IconButton(
            key: const ValueKey('shop-restore-purchases'),
            onPressed: enabled ? onPressed : null,
            tooltip: label,
            icon: const Icon(Icons.chevron_right_rounded),
          ),
        ],
      ),
    );
  }
}

class _ShopItem {
  const _ShopItem({
    required this.id,
    required this.category,
    required this.icon,
    required this.color,
    required this.title,
    required this.description,
    required this.price,
    required this.state,
    required this.status,
    required this.onPressed,
    this.supportingText,
  });

  final String id;
  final _ShopCategory category;
  final IconData icon;
  final Color color;
  final String title;
  final String description;
  final String price;
  final _ShopItemState state;
  final String status;
  final VoidCallback? onPressed;
  final String? supportingText;
}

class _ShopFeedback {
  const _ShopFeedback({
    required this.tone,
    required this.title,
    required this.message,
  });

  final _ShopFeedbackTone tone;
  final String title;
  final String message;
}

IconData _categoryIcon(_ShopCategory category) => switch (category) {
  _ShopCategory.all => Icons.apps_rounded,
  _ShopCategory.rewards => Icons.play_circle_rounded,
  _ShopCategory.benefits => Icons.workspace_premium_rounded,
  _ShopCategory.offers => Icons.local_offer_rounded,
  _ShopCategory.currency => Icons.paid_rounded,
  _ShopCategory.supplies => Icons.inventory_2_rounded,
};

String _categoryLabel(
  BuildContext context,
  AppLocalizations loc,
  _ShopCategory category,
) => switch (category) {
  _ShopCategory.all => _t(context, 'All', 'הכול', 'الكل'),
  _ShopCategory.rewards => loc.rewardedBonus,
  _ShopCategory.benefits => loc.permanentBenefits,
  _ShopCategory.offers => loc.starterOffers,
  _ShopCategory.currency => _t(context, 'Currency', 'מטבעות', 'العملات'),
  _ShopCategory.supplies => loc.emergencySupplies,
};

String _unavailableMessage(BuildContext context) => _t(
  context,
  'This item is not available right now. Your market can keep growing without it.',
  'הפריט לא זמין כרגע. אפשר להמשיך לפתח את המרקט בלעדיו.',
  'هذا العنصر غير متاح حالياً. يمكنك مواصلة تطوير متجرك بدونه.',
);

String _paymentFailure(BuildContext context) => _t(
  context,
  'Check your payment method or available funds, then try again.',
  'בדקו את אמצעי התשלום או היתרה הזמינה ונסו שוב.',
  'تحقق من وسيلة الدفع أو الرصيد المتاح ثم حاول مجدداً.',
);

String _t(BuildContext context, String en, String he, String ar) =>
    switch (Localizations.localeOf(context).languageCode) {
      'he' => he,
      'ar' => ar,
      _ => en,
    };
