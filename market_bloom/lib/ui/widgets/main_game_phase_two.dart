import 'package:flutter/material.dart';

import '../../game/game_controller.dart';
import '../../services/app_settings.dart';
import '../vertical_slice_world_painter.dart';

/// Compatibility wrapper for the market destination.
///
/// The world itself is painted only inside GameScreen's real market-board.
class MainGamePhaseTwo extends StatelessWidget {
  const MainGamePhaseTwo({
    super.key,
    required this.game,
    required this.settings,
    required this.child,
  });

  final GameController game;
  final AppSettings settings;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    VerticalSliceRenderSettings.reducedMotion =
        settings.reducedMotion || MediaQuery.disableAnimationsOf(context);
    return child;
  }
}
