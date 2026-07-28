import 'package:flutter/material.dart';

import '../game/game_controller.dart';
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
/// Narrow phones use a compact bottom navigation bar for the four primary
/// destinations (Market, Upgrades, Shop, Settings) and a More sheet for the
/// rest. Wide phones, tablets, and web use a [NavigationRail].
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

  static const _primaryDestinations = <AppDestination>[
    AppDestination.market,
    AppDestination.upgrades,
    AppDestination.shop,
    AppDestination.settings,
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
    final isWide = MediaQuery.sizeOf(context).width >= 600;
    final reducedMotion =
        widget.settings.reducedMotion ||
        MediaQuery.disableAnimationsOf(context);

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: Row(
              children: [
                if (isWide) _buildRail(localizations, reducedMotion),
                Expanded(
                  child: IndexedStack(
                    index: _selectedIndex,
                    children: [
                      for (final dest in _allDestinations) _buildDestination(dest),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              ignoring: true,
              child: GlobalHud(game: widget.controller, settings: widget.settings),
            ),
          ),
        ],
      ),
      bottomNavigationBar: isWide
          ? null
          : _buildBottomNavBar(localizations, reducedMotion),
    );
  }

  Widget _buildRail(AppLocalizations loc, bool reducedMotion) {
    return NavigationRail(
      selectedIndex: _selectedIndex,
      onDestinationSelected: _selectDestination,
      extended: false,
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

  Widget _buildBottomNavBar(AppLocalizations loc, bool reducedMotion) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            for (int i = 0; i < _primaryDestinations.length; i++)
              Expanded(
                child: _buildBottomNavItem(
                  _primaryDestinations[i],
                  loc,
                  i == _selectedIndex,
                  () => _selectDestination(i),
                ),
              ),
            Expanded(
              child: IconButton(
                icon: const Icon(Icons.more_horiz_rounded),
                tooltip: loc.more,
                onPressed: () => _showMoreSheet(loc),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomNavItem(
    AppDestination dest,
    AppLocalizations loc,
    bool selected,
    VoidCallback onTap,
  ) {
    final color = selected
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.onSurfaceVariant;
    return IconButton(
      icon: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_iconFor(dest), color: color, size: 24),
          Text(
            _labelFor(dest, loc),
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
            ),
          ),
        ],
      ),
      onPressed: onTap,
    );
  }

  void _showMoreSheet(AppLocalizations loc) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 5,
              margin: const EdgeInsets.only(bottom: 13),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.outline,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            for (final dest in _allDestinations)
              if (!_primaryDestinations.contains(dest))
                ListTile(
                  leading: CircleCaddy(icon: _iconFor(dest)),
                  title: Text(_labelFor(dest, loc)),
                  onTap: () {
                    final index = _allDestinations.indexOf(dest);
                    Navigator.of(sheetContext).pop();
                    _selectDestination(index);
                  },
                ),
          ],
        ),
      ),
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
