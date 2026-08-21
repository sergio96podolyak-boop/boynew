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
import 'widgets/daily_event_banner.dart';
import 'widgets/game_dock.dart';
import 'widgets/game_navigation.dart';
import 'widgets/global_hud.dart';
import 'widgets/main_game_phase_two.dart';
import 'theme/po_system.dart';
import 'widgets/privacy_consent_layer.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.controller, required this.settings});

  final GameController controller;
  final AppSettings settings;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  AppDestination _selectedDestination = AppDestination.market;
  late final ScrollController _settingsScrollController;
  bool _worldMenuOpen = false;

  /// Always-visible dock slots, ordered by how often a shift needs them.
  static const _dockDestinations = <AppDestination>[
    AppDestination.market,
    AppDestination.upgrades,
    AppDestination.staff,
    AppDestination.shop,
  ];

  /// Revealed by the dock's "more" slot — one tap, no hunting.
  static const _moreDestinations = <AppDestination>[
    AppDestination.departments,
    AppDestination.inventory,
    AppDestination.quests,
    AppDestination.achievements,
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

  int get _selectedIndex => _allDestinations.indexOf(_selectedDestination);

  @override
  void initState() {
    super.initState();
    _settingsScrollController = ScrollController();
  }

  @override
  void dispose() {
    _settingsScrollController.dispose();
    super.dispose();
  }

  void _selectDestination(AppDestination destination) {
    if (destination == _selectedDestination) {
      if (_worldMenuOpen) setState(() => _worldMenuOpen = false);
      return;
    }
    setState(() {
      _selectedDestination = destination;
      _worldMenuOpen = false;
    });
  }

  void _toggleWorldMenu() {
    setState(() => _worldMenuOpen = !_worldMenuOpen);
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final dailyEvent = DailyEventBannerLayer.maybeOf(context);
    final marketSelected = _selectedDestination == AppDestination.market;
    return Scaffold(
      backgroundColor: PoColor.canvas,
      body: PoPageGround(
        // Softer on the board screen: the market art supplies its own colour,
        // so a strong page wash behind it would compete with the shelves.
        aurora: marketSelected ? 0.5 : 1,
        child: marketSelected
            // The world is full-bleed and the chrome floats over it. Stacking
            // the HUD, event banner and dock as bars above and below the board
            // is what kept the composition feeling like a form with a picture
            // in it rather than a game.
            ? Stack(
                children: [
                  // The market screen owns one layout column for every
                  // persistent layer, and the shell hands it the chrome to
                  // place. Positioning the HUD and dock separately here, while
                  // the screen positioned its own pods against guessed offsets,
                  // is what let the banners collide.
                  Positioned.fill(
                    child: MainGamePhaseTwo(
                      game: widget.controller,
                      settings: widget.settings,
                      child: GameScreen(
                        controller: widget.controller,
                        settings: widget.settings,
                        onOpenStaff: () =>
                            _selectDestination(AppDestination.staff),
                        onOpenInventory: () =>
                            _selectDestination(AppDestination.inventory),
                        onOpenDepartments: () =>
                            _selectDestination(AppDestination.departments),
                        topChrome: GlobalHud(
                          game: widget.controller,
                          settings: widget.settings,
                          compactMode: true,
                          floating: true,
                        ),
                        bottomChrome: Builder(
                          builder: (context) {
                            // Ambient context, so it sits at the foot of the
                            // world rather than taking a slot at the top — and
                            // it is the first thing to go when there is no room
                            // for it. On a landscape phone the banner plus the
                            // dock sandwiched the world into a sliver.
                            final height = MediaQuery.sizeOf(context).height;
                            final showEvent = dailyEvent != null && height >= 520;
                            return Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (showEvent)
                                  Padding(
                                    padding: EdgeInsetsDirectional.fromSTEB(
                                      PoChrome.dockInset(context),
                                      0,
                                      PoChrome.dockInset(context),
                                      6 * PoScale.of(context),
                                    ),
                                    // Shares the dock's measure so the two read
                                    // as one bottom stack rather than a
                                    // full-bleed bar above a floating pill.
                                    child: Center(
                                      child: ConstrainedBox(
                                        constraints: const BoxConstraints(
                                          maxWidth: 620,
                                        ),
                                        child: DailyEventBanner(
                                          game: dailyEvent.game,
                                          settings: dailyEvent.settings,
                                          compact: true,
                                        ),
                                      ),
                                    ),
                                  ),
                                _dock(loc),
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                  // Keeps the other destinations mounted so their state and
                  // controllers survive navigation exactly as before.
                  Offstage(
                    offstage: true,
                    child: TickerMode(
                      enabled: false,
                      child: IndexedStack(
                        index: _selectedIndex,
                        children: [
                          for (final destination in _allDestinations)
                            if (destination == AppDestination.market)
                              const SizedBox.shrink()
                            else
                              _buildDestination(destination),
                        ],
                      ),
                    ),
                  ),
                ],
              )
            : Column(
                children: [
                  GlobalHud(
                    game: widget.controller,
                    settings: widget.settings,
                    compactMode: false,
                  ),
                  if (dailyEvent != null)
                    DailyEventBanner(
                      game: dailyEvent.game,
                      settings: dailyEvent.settings,
                      compact: true,
                    ),
                  Expanded(
                    child: IndexedStack(
                      index: _selectedIndex,
                      children: [
                        for (final destination in _allDestinations)
                          _buildDestination(destination),
                      ],
                    ),
                  ),
                  _dock(loc),
                ],
              ),
      ),
    );
  }

  /// One dock, built the same way for both compositions.
  Widget _dock(AppLocalizations loc) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final badges = _CommandBadges.from(widget.controller);
      return GameDock(
        primary: _dockDestinations,
        overflow: _moreDestinations,
        selected: _selectedDestination,
        expanded: _worldMenuOpen,
        labelFor: (destination) => _labelFor(destination, loc),
        iconFor: _iconFor,
        hasBadge: badges.forDestination,
        moreLabel: loc.more,
        onSelect: _selectDestination,
        onToggleMore: _toggleWorldMenu,
      );
    },
  );

  Widget _buildDestination(AppDestination destination) {
    final game = widget.controller;
    return switch (destination) {
      AppDestination.market => MainGamePhaseTwo(
        game: game,
        settings: widget.settings,
        child: GameScreen(
          controller: game,
          settings: widget.settings,
          onOpenStaff: () => _selectDestination(AppDestination.staff),
          onOpenInventory: () => _selectDestination(AppDestination.inventory),
          onOpenDepartments: () =>
              _selectDestination(AppDestination.departments),
        ),
      ),
      AppDestination.upgrades => UpgradesScreen(controller: game),
      AppDestination.staff => StaffScreen(controller: game),
      AppDestination.departments => DepartmentsScreen(controller: game),
      AppDestination.inventory => InventoryScreen(controller: game),
      AppDestination.quests => QuestsScreen(controller: game),
      AppDestination.achievements => AchievementsScreen(controller: game),
      AppDestination.shop => ShopScreen(controller: game),
      AppDestination.settings => PrimaryScrollController(
        controller: _settingsScrollController,
        scrollDirection: Axis.vertical,
        automaticallyInheritForPlatforms: TargetPlatform.values.toSet(),
        child: PrivacySettingsLauncher(
          settings: widget.settings,
          child: SettingsScreen(controller: game, settings: widget.settings),
        ),
      ),
    };
  }

  static IconData _iconFor(AppDestination destination) => switch (destination) {
    AppDestination.market => Icons.storefront_rounded,
    AppDestination.upgrades => Icons.trending_up_rounded,
    AppDestination.staff => Icons.groups_2_rounded,
    AppDestination.departments => Icons.store_mall_directory_rounded,
    AppDestination.inventory => Icons.inventory_2_rounded,
    AppDestination.quests => Icons.flag_circle_rounded,
    AppDestination.achievements => Icons.emoji_events_rounded,
    AppDestination.shop => Icons.shopping_bag_rounded,
    AppDestination.settings => Icons.tune_rounded,
  };

  static String _labelFor(AppDestination destination, AppLocalizations loc) =>
      switch (destination) {
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

class _CommandBadges {
  const _CommandBadges({
    required this.upgrades,
    required this.staff,
    required this.inventory,
  });

  factory _CommandBadges.from(GameController game) => _CommandBadges(
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
    AppDestination.staff => staff,
    AppDestination.inventory => inventory,
    _ => false,
  };
}
