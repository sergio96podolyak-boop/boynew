import 'package:flutter/material.dart';

import '../game/game_controller.dart';
import '../game/game_models.dart';
import '../services/app_localizations.dart';
import '../services/app_settings.dart';
import 'game_screen.dart';
import 'screens/achievements_screen.dart';
import 'screens/departments_screen.dart';
import 'screens/inventory_screen.dart';
import 'screens/quests_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/shop_screen.dart';
import 'screens/staff_screen.dart';
import 'screens/upgrades_screen.dart';
import 'widgets/global_hud.dart';

/// The nine top-level destinations in the PoMarket experience.
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

/// Responsive application shell with adaptive navigation.
///
/// Narrow phones use a compact floating icon menu over the destination. Wide
/// phones, tablets, and web use a [NavigationRail].
///
/// The [GameController] is passed to every destination and is never
/// recreated when switching, so game state is preserved.
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.controller, required this.settings});

  final GameController controller;
  final AppSettings settings;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selectedIndex = 0;

  static const _sideHudDestinations = <AppDestination>[
    AppDestination.market,
    AppDestination.upgrades,
    AppDestination.staff,
    AppDestination.inventory,
    AppDestination.shop,
    AppDestination.settings,
  ];

  static const _secondaryDestinations = <AppDestination>[
    AppDestination.departments,
    AppDestination.quests,
    AppDestination.achievements,
  ];

  static const _allDestinations = <AppDestination>[
    AppDestination.market,
    AppDestination.upgrades,
    AppDestination.staff,
    AppDestination.departments,
    AppDestination.inventory,
    AppDestination.quests,
    AppDestination.achievements,
    AppDestination.shop,
    AppDestination.settings,
  ];

  void _selectDestination(int index) {
    setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final viewport = MediaQuery.sizeOf(context);
    // A short landscape viewport cannot fit the full labelled rail. Treat it
    // like a phone layout so navigation remains reachable without overflow.
    final isWide = viewport.width >= 600 && viewport.height >= 560;
     return Scaffold(
      body: Column(
        children: [
          GlobalHud(
            game: widget.controller,
            settings: widget.settings,
          ),
          Expanded(
            child: Row(
              children: [
                if (isWide) _buildRail(localizations),

                Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: IndexedStack(
                          index: _selectedIndex,
                          children: [
                            for (final dest in _allDestinations)
                              _buildDestination(dest),
                          ],
                        ),
                      ),

                      if (!isWide)
                        PositionedDirectional(
                          top: 10,
                          end: 8,
                          child: SafeArea(
                            child: RepaintBoundary(
                              child: _buildFloatingMenu(localizations),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRail(AppLocalizations loc) {
    return NavigationRail(
      selectedIndex: _selectedIndex,
      onDestinationSelected: _selectDestination,
      extended: false,
      labelType: NavigationRailLabelType.all,
      groupAlignment: -1,
      destinations: [
        for (final dest in _allDestinations)
          NavigationRailDestination(
            icon: Icon(_iconFor(dest)),
            label: Text(_labelFor(dest, loc)),
            selectedIcon: Icon(
              _iconFor(dest),
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
      ],
    );
  }

  Widget _buildFloatingMenu(AppLocalizations loc) {
    return _FloatingHudMenu(
      controller: widget.controller,
      destinations: _sideHudDestinations,
      selectedDestination: _allDestinations[_selectedIndex],
      labelFor: (destination) => _labelFor(destination, loc),
      iconFor: _iconFor,
      moreLabel: loc.more,
      secondaryDestinations: _secondaryDestinations,
      onSelect: (destination) =>
          _selectDestination(_allDestinations.indexOf(destination)),
    );
  }

  Widget _buildDestination(AppDestination dest) {
    final game = widget.controller;
    final settings = widget.settings;
    switch (dest) {
      case AppDestination.market:
        return GameScreen(controller: game, settings: settings);
      case AppDestination.upgrades:
        return UpgradesScreen(controller: game);
      case AppDestination.staff:
        return StaffScreen(controller: game);
      case AppDestination.departments:
        return DepartmentsScreen(controller: game);
      case AppDestination.inventory:
        return InventoryScreen(controller: game);
      case AppDestination.quests:
        return QuestsScreen(controller: game);
      case AppDestination.achievements:
        return AchievementsScreen(controller: game);
      case AppDestination.shop:
        return ShopScreen(controller: game);
      case AppDestination.settings:
        return SettingsScreen(controller: game, settings: settings);
    }
  }

  static IconData _iconFor(AppDestination dest) {
    return switch (dest) {
      AppDestination.market => Icons.storefront_rounded,
      AppDestination.upgrades => Icons.upgrade_rounded,
      AppDestination.staff => Icons.groups_rounded,
      AppDestination.departments => Icons.category_rounded,
      AppDestination.inventory => Icons.inventory_2_rounded,
      AppDestination.quests => Icons.flag_rounded,
      AppDestination.achievements => Icons.emoji_events_rounded,
      AppDestination.shop => Icons.shopping_bag_rounded,
      AppDestination.settings => Icons.settings_rounded,
    };
  }

  static String _labelFor(AppDestination dest, AppLocalizations loc) {
    return switch (dest) {
      AppDestination.market => loc.market,
      AppDestination.upgrades => loc.upgrades,
      AppDestination.staff => loc.staff,
      AppDestination.departments => loc.departments,
      AppDestination.inventory => loc.inventory,
      AppDestination.quests => loc.quests,
      AppDestination.achievements => loc.achievements,
      AppDestination.shop => loc.shop,
      AppDestination.settings => loc.settings,
    };
  }
}

class _FloatingHudMenu extends StatefulWidget {
  const _FloatingHudMenu({
    required this.controller,
    required this.destinations,
    required this.selectedDestination,
    required this.labelFor,
    required this.iconFor,
    required this.moreLabel,
    required this.secondaryDestinations,
    required this.onSelect,
  });

  final GameController controller;
  final List<AppDestination> destinations;
  final AppDestination selectedDestination;
  final String Function(AppDestination) labelFor;
  final IconData Function(AppDestination) iconFor;
  final String moreLabel;
  final List<AppDestination> secondaryDestinations;
  final ValueChanged<AppDestination> onSelect;

  @override
  State<_FloatingHudMenu> createState() => _FloatingHudMenuState();
}

class _FloatingHudMenuState extends State<_FloatingHudMenu> {
  late _BadgeSnapshot _badges;

  @override
  void initState() {
    super.initState();
    _badges = _BadgeSnapshot.from(widget.controller);
    widget.controller.addListener(_refreshBadges);
  }

  @override
  void didUpdateWidget(covariant _FloatingHudMenu oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_refreshBadges);
      _badges = _BadgeSnapshot.from(widget.controller);
      widget.controller.addListener(_refreshBadges);
    }
  }

  void _refreshBadges() {
    final next = _BadgeSnapshot.from(widget.controller);
    if (mounted && next != _badges) {
      setState(() => _badges = next);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_refreshBadges);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).height < 480;
    final itemSize = compact ? 36.0 : 42.0;
    final itemSpacing = compact ? 4.0 : 7.0;
    return Material(
      color: Colors.transparent,
      child: SizedBox(
        width: itemSize + 4,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            for (final destination in widget.destinations) ...[
              _FloatingHudItem(
                destination: destination,
                selected: widget.selectedDestination == destination,
                label: widget.labelFor(destination),
                icon: widget.iconFor(destination),
                badge: _badges.forDestination(destination),
                size: itemSize,
                onTap: () => widget.onSelect(destination),
              ),
              SizedBox(height: itemSpacing),
            ],
            PopupMenuButton<AppDestination>(
              key: const ValueKey('side-hud-more'),
              tooltip: widget.moreLabel,
              padding: EdgeInsets.zero,
              constraints: BoxConstraints.tightFor(
                width: itemSize,
                height: itemSize,
              ),
              onSelected: widget.onSelect,
              itemBuilder: (context) => [
                for (final destination in widget.secondaryDestinations)
                  PopupMenuItem<AppDestination>(
                    value: destination,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(widget.iconFor(destination), size: 19),
                        const SizedBox(width: 10),
                        Text(widget.labelFor(destination)),
                      ],
                    ),
                  ),
              ],
              child: _HudCircle(
                icon: Icons.apps_rounded,
                selected: false,
                label: widget.moreLabel,
                size: itemSize,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FloatingHudItem extends StatelessWidget {
  const _FloatingHudItem({
    required this.destination,
    required this.selected,
    required this.label,
    required this.icon,
    required this.badge,
    required this.size,
    required this.onTap,
  });

  final AppDestination destination;
  final bool selected;
  final String label;
  final IconData icon;
  final bool badge;
  final double size;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: ValueKey('side-hud-${destination.name}'),
      button: true,
      label: label,
      onTap: onTap,
      child: Tooltip(
        message: label,
        child: _HudCircle(
          icon: icon,
          selected: selected,
          label: label,
          badge: badge,
          size: size,
          onTap: onTap,
        ),
      ),
    );
  }
}

class _HudCircle extends StatelessWidget {
  const _HudCircle({
    required this.icon,
    required this.selected,
    required this.label,
    this.badge = false,
    this.size = 42,
    this.onTap,
  });

  final IconData icon;
  final bool selected;
  final String label;
  final bool badge;
  final double size;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    return Semantics(
      button: onTap != null,
      label: label,
      child: SizedBox(
        width: size,
        height: size,
        child: Material(
          color: selected ? color.primary : const Color(0xEFFFFFF7),
          elevation: selected ? 5 : 3,
          shadowColor: const Color(0x55315F4A),
          shape: const CircleBorder(),
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: Align(
              alignment: Alignment.center,
              child: SizedBox.expand(
                child: Stack(
                  alignment: Alignment.center,
                  clipBehavior: Clip.none,
                  children: [
                    Icon(
                      icon,
                      size: size < 40 ? 19 : 21,
                      color: selected ? Colors.white : color.onSurfaceVariant,
                    ),
                    if (badge)
                      PositionedDirectional(
                        top: -3,
                        end: -3,
                        child: Container(
                          width: 16,
                          height: 16,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: const Color(0xFFD83B4A),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: const Color(0xFFFFFCF6),
                              width: 1.5,
                            ),
                          ),
                          child: const Text(
                            '!',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BadgeSnapshot {
  const _BadgeSnapshot({
    required this.upgrades,
    required this.staff,
    required this.inventory,
  });

  factory _BadgeSnapshot.from(GameController game) {
    return _BadgeSnapshot(
      upgrades: game.upgrades.any((offer) => game.canBuyUpgrade(offer.type)),
      staff: StaffRole.values.any(
        (role) => game.isStaffRoleUnlocked(role) && !game.isStaffHired(role),
      ),
      inventory: game.pendingDeliveries.any(game.isDeliveryReady),
    );
  }

  final bool upgrades;
  final bool staff;
  final bool inventory;

  bool forDestination(AppDestination destination) {
    return switch (destination) {
      AppDestination.upgrades => upgrades,
      AppDestination.staff => staff,
      AppDestination.inventory => inventory,
      _ => false,
    };
  }

  @override
  bool operator ==(Object other) {
    return other is _BadgeSnapshot &&
        other.upgrades == upgrades &&
        other.staff == staff &&
        other.inventory == inventory;
  }

  @override
  int get hashCode => Object.hash(upgrades, staff, inventory);
}

class CircleCaddy extends StatelessWidget {
  const CircleCaddy({super.key, required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: 16,
      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      child: Icon(icon, color: Theme.of(context).colorScheme.primary),
    );
  }
}
