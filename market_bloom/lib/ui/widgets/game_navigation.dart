import 'package:flutter/material.dart';

import '../../game/game_controller.dart';
import '../../game/game_models.dart';
import '../../services/app_settings.dart';
import 'premium_ui.dart';

enum AppDestination {
  market,
  upgrades,
  staff,
  departments,
  inventory,
  quests,
  achievements,
  shop,
  settings,
}

class GameNavigationRail extends StatelessWidget {
  const GameNavigationRail({
    super.key,
    required this.controller,
    required this.destinations,
    required this.selected,
    required this.labelFor,
    required this.iconFor,
    required this.onSelect,
    required this.roomy,
  });

  final GameController controller;
  final List<AppDestination> destinations;
  final AppDestination selected;
  final String Function(AppDestination) labelFor;
  final IconData Function(AppDestination) iconFor;
  final ValueChanged<AppDestination> onSelect;
  final bool roomy;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final badges = _BadgeSnapshot.from(controller);
        return Container(
          key: const ValueKey('game-navigation-rail'),
          width: roomy ? 112 : 88,
          margin: const EdgeInsetsDirectional.fromSTEB(5, 8, 8, 8),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF0A4937), Color(0xFF052D23)],
            ),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: const Color(0x3345D39A)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x30052E23),
                blurRadius: 20,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: const BoxDecoration(
                  color: PoMarketPalette.mint,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.storefront_rounded,
                  color: PoMarketPalette.forest,
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    for (final destination in destinations)
                      _RailDestination(
                        icon: iconFor(destination),
                        label: labelFor(destination),
                        selected: selected == destination,
                        badge: badges.forDestination(destination),
                        roomy: roomy,
                        onTap: () => onSelect(destination),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _RailDestination extends StatelessWidget {
  const _RailDestination({
    required this.icon,
    required this.label,
    required this.selected,
    required this.badge,
    required this.roomy,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final bool badge;
  final bool roomy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        child: Material(
          color: selected
              ? PoMarketPalette.mint.withValues(alpha: .18)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(17),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(17),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: roomy ? 8 : 5,
                vertical: 7,
              ),
              child: Column(
                children: [
                  _BadgeIcon(
                    icon: icon,
                    badge: badge,
                    color: selected
                        ? PoMarketPalette.mint
                        : const Color(0xFFBCD2C7),
                    size: selected ? 23 : 20,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected ? Colors.white : const Color(0xFFBCD2C7),
                      fontSize: roomy ? 9 : 8,
                      fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class MobileGameNavigation extends StatelessWidget {
  const MobileGameNavigation({
    super.key,
    required this.controller,
    required this.settings,
    required this.primaryDestinations,
    required this.secondaryDestinations,
    required this.selected,
    required this.labelFor,
    required this.iconFor,
    required this.moreLabel,
    required this.onSelect,
  });

  final GameController controller;
  final AppSettings settings;
  final List<AppDestination> primaryDestinations;
  final List<AppDestination> secondaryDestinations;
  final AppDestination selected;
  final String Function(AppDestination) labelFor;
  final IconData Function(AppDestination) iconFor;
  final String moreLabel;
  final ValueChanged<AppDestination> onSelect;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).height < 620;
    final reducedMotion =
        settings.reducedMotion ||
        MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.accessibleNavigationOf(context);
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final badges = _BadgeSnapshot.from(controller);
        final moreSelected = secondaryDestinations.contains(selected);
        return SafeArea(
          top: false,
          minimum: const EdgeInsets.fromLTRB(7, 0, 7, 5),
          child: Container(
            key: const ValueKey('mobile-game-navigation'),
            height: compact ? 62 : 72,
            padding: const EdgeInsets.fromLTRB(4, 5, 4, 4),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF0D503C), Color(0xFF04291F)],
              ),
              borderRadius: BorderRadius.circular(25),
              border: Border.all(color: const Color(0x5545D39A)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x5A052E23),
                  blurRadius: 20,
                  offset: Offset(0, 9),
                ),
                BoxShadow(
                  color: Color(0x1AFFFFFF),
                  blurRadius: 1,
                  offset: Offset(0, -1),
                ),
              ],
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                PositionedDirectional(
                  top: -5,
                  start: 26,
                  end: 26,
                  child: Container(
                    height: 2,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [
                          Colors.transparent,
                          PoMarketPalette.mint,
                          Colors.transparent,
                        ],
                      ),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                Row(
                  children: [
                    for (final destination in primaryDestinations)
                      Expanded(
                        flex: destination == AppDestination.market ? 12 : 10,
                        child: _DockDestination(
                          key: ValueKey('mobile-nav-${destination.name}'),
                          compatibilityKey: ValueKey(
                            'side-hud-${destination.name}',
                          ),
                          icon: iconFor(destination),
                          label: labelFor(destination),
                          selected: destination == selected,
                          badge: badges.forDestination(destination),
                          compact: compact,
                          reducedMotion: reducedMotion,
                          emphasized: destination == AppDestination.market,
                          onTap: () => onSelect(destination),
                        ),
                      ),
                    Expanded(
                      flex: 10,
                      child: _DockDestination(
                        key: const ValueKey('mobile-nav-more'),
                        compatibilityKey: const ValueKey('side-hud-more'),
                        icon: Icons.grid_view_rounded,
                        label: moreLabel,
                        selected: moreSelected,
                        badge: badges.anyFor(secondaryDestinations),
                        compact: compact,
                        reducedMotion: reducedMotion,
                        emphasized: false,
                        onTap: () => _showHub(context, badges),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showHub(BuildContext context, _BadgeSnapshot badges) async {
    final destination = await showModalBottomSheet<AppDestination>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _MarketHubSheet(
        destinations: secondaryDestinations,
        selected: selected,
        badges: badges,
        labelFor: labelFor,
        iconFor: iconFor,
      ),
    );
    if (destination != null) onSelect(destination);
  }
}

class _DockDestination extends StatelessWidget {
  const _DockDestination({
    super.key,
    required this.compatibilityKey,
    required this.icon,
    required this.label,
    required this.selected,
    required this.badge,
    required this.compact,
    required this.reducedMotion,
    required this.emphasized,
    required this.onTap,
  });

  final Key compatibilityKey;
  final IconData icon;
  final String label;
  final bool selected;
  final bool badge;
  final bool compact;
  final bool reducedMotion;
  final bool emphasized;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final activeColor = emphasized ? PoMarketPalette.gold : PoMarketPalette.mint;
    return Semantics(
      key: compatibilityKey,
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: AnimatedContainer(
            duration: reducedMotion
                ? Duration.zero
                : const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            margin: const EdgeInsets.symmetric(horizontal: 1),
            transform: Matrix4.translationValues(
              0,
              selected && emphasized && !reducedMotion ? -7 : 0,
              0,
            ),
            decoration: BoxDecoration(
              gradient: selected
                  ? LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        activeColor.withValues(alpha: .24),
                        activeColor.withValues(alpha: .08),
                      ],
                    )
                  : null,
              borderRadius: BorderRadius.circular(18),
              border: selected
                  ? Border.all(color: activeColor.withValues(alpha: .45))
                  : null,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedContainer(
                  duration: reducedMotion
                      ? Duration.zero
                      : const Duration(milliseconds: 180),
                  width: emphasized ? (selected ? 36 : 30) : 27,
                  height: emphasized ? (selected ? 36 : 30) : 27,
                  decoration: BoxDecoration(
                    gradient: selected && emphasized
                        ? LinearGradient(
                            colors: [activeColor, const Color(0xFFFFE49A)],
                          )
                        : null,
                    color: selected && !emphasized
                        ? activeColor.withValues(alpha: .13)
                        : null,
                    shape: BoxShape.circle,
                    border: emphasized && !selected
                        ? Border.all(color: const Color(0x5578E4B8))
                        : null,
                    boxShadow: selected && emphasized
                        ? [
                            BoxShadow(
                              color: activeColor.withValues(alpha: .34),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ]
                        : null,
                  ),
                  alignment: Alignment.center,
                  child: _BadgeIcon(
                    icon: icon,
                    badge: badge,
                    color: selected
                        ? emphasized
                              ? PoMarketPalette.forest
                              : activeColor
                        : const Color(0xFFC5D9CF),
                    size: compact ? 18 : 20,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected ? Colors.white : const Color(0xFFB9CFC5),
                    fontSize: compact ? 7 : 8,
                    fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MarketHubSheet extends StatelessWidget {
  const _MarketHubSheet({
    required this.destinations,
    required this.selected,
    required this.badges,
    required this.labelFor,
    required this.iconFor,
  });

  final List<AppDestination> destinations;
  final AppDestination selected;
  final _BadgeSnapshot badges;
  final String Function(AppDestination) labelFor;
  final IconData Function(AppDestination) iconFor;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFFFFBF1),
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: PoMarketPalette.line,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 9),
              Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: const BoxDecoration(
                      color: PoMarketPalette.forest,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.grid_view_rounded,
                      color: PoMarketPalette.mint,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          MaterialLocalizations.of(context).moreButtonTooltip,
                          style: const TextStyle(
                            color: PoMarketPalette.ink,
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const Text(
                          'Market management',
                          style: TextStyle(
                            color: PoMarketPalette.muted,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: destinations.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  childAspectRatio: 2.45,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemBuilder: (context, index) {
                  final destination = destinations[index];
                  final active = destination == selected;
                  return Semantics(
                    button: true,
                    selected: active,
                    label: labelFor(destination),
                    child: Material(
                      color: active
                          ? PoMarketPalette.mintSoft
                          : const Color(0xFFF1F4EC),
                      borderRadius: BorderRadius.circular(15),
                      child: InkWell(
                        onTap: () => Navigator.of(context).pop(destination),
                        borderRadius: BorderRadius.circular(15),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(15),
                            border: Border.all(
                              color: active
                                  ? PoMarketPalette.mint.withValues(alpha: .45)
                                  : PoMarketPalette.line,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  color: PoMarketPalette.forest.withValues(alpha: .09),
                                  borderRadius: BorderRadius.circular(11),
                                ),
                                child: _BadgeIcon(
                                  icon: iconFor(destination),
                                  badge: badges.forDestination(destination),
                                  color: PoMarketPalette.forestLight,
                                  size: 19,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  labelFor(destination),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: PoMarketPalette.ink,
                                    fontSize: 11,
                                    height: 1.1,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                              if (active)
                                const Icon(
                                  Icons.check_circle_rounded,
                                  color: PoMarketPalette.mint,
                                  size: 17,
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BadgeIcon extends StatelessWidget {
  const _BadgeIcon({
    required this.icon,
    required this.badge,
    required this.color,
    required this.size,
  });

  final IconData icon;
  final bool badge;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        Icon(icon, color: color, size: size),
        if (badge)
          const PositionedDirectional(
            top: -3,
            end: -4,
            child: StatusDot(color: PoMarketPalette.coral, size: 7),
          ),
      ],
    );
  }
}

class _BadgeSnapshot {
  const _BadgeSnapshot({
    required this.upgrades,
    required this.staff,
    required this.inventory,
  });

  factory _BadgeSnapshot.from(GameController game) => _BadgeSnapshot(
    upgrades: game.upgrades.any((offer) => game.canBuyUpgrade(offer.type)),
    staff: StaffRole.values.any(
      (role) => game.isStaffRoleUnlocked(role) && !game.isStaffHired(role),
    ),
    inventory: game.pendingDeliveries.any(game.isDeliveryReady),
  );

  final bool upgrades;
  final bool staff;
  final bool inventory;

  bool forDestination(AppDestination destination) => switch (destination) {
    AppDestination.upgrades => upgrades,
    AppDestination.staff => staff,
    AppDestination.inventory => inventory,
    _ => false,
  };

  bool anyFor(Iterable<AppDestination> destinations) =>
      destinations.any(forDestination);
}
