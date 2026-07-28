import 'dart:math';

import 'package:flutter/material.dart';

import '../../game/game_controller.dart';
import '../../services/app_localizations.dart';
import '../../services/app_settings.dart';

class TouchMovement extends StatefulWidget {
  const TouchMovement({
    super.key,
    required this.game,
    required this.onTap,
    this.controlMode = ControlMode.directTouch,
  });

  final GameController game;
  final VoidCallback onTap;
  final ControlMode controlMode;

  static Rect marketRectFor(Size size) {
    return Rect.fromLTWH(
      8,
      6,
      max(0.0, size.width - 16),
      max(0.0, size.height - 12),
    );
  }

  static Offset worldToLocal(Offset worldPosition, Size size) {
    final market = marketRectFor(size);
    return Offset(
      market.left + market.width * worldPosition.dx,
      market.top + market.height * worldPosition.dy,
    );
  }

  static Offset localToWorld(Offset localPosition, Size size) {
    final market = marketRectFor(size);
    if (market.width <= 0 || market.height <= 0) {
      return const Offset(0.5, 0.72);
    }
    return clampWorldTarget(
      Offset(
        (localPosition.dx - market.left) / market.width,
        (localPosition.dy - market.top) / market.height,
      ),
    );
  }

  static Offset clampWorldTarget(Offset target) {
    return Offset(target.dx.clamp(0.06, 0.94), target.dy.clamp(0.09, 0.94));
  }

  static Offset snapToInteractionPoint(Offset target) {
    const stations = <Offset>[
      GameController.stockZone,
      GameController.shelfZone,
      GameController.checkoutZone,
      Offset(0.78, 0.76),
    ];
    var nearest = target;
    var nearestDistance = 0.12;
    for (final station in stations) {
      final distance = (target - station).distance;
      if (distance < nearestDistance) {
        nearest = station;
        nearestDistance = distance;
      }
    }
    return nearest;
  }

  @override
  State<TouchMovement> createState() => _TouchMovementState();
}

class _TouchMovementState extends State<TouchMovement> {
  bool _isDragging = false;

  @override
  void didUpdateWidget(covariant TouchMovement oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controlMode != widget.controlMode) {
      _stopMovement();
    }
  }

  @override
  void dispose() {
    widget.game.clearMovementTarget();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.controlMode != ControlMode.directTouch) {
      return _JoystickArea(
        onChanged: widget.game.setMovement,
        alignment: widget.controlMode == ControlMode.leftJoystick
            ? Alignment.bottomLeft
            : Alignment.bottomRight,
      );
    }
    return Semantics(
      label: AppLocalizations.of(context).directTouchInstruction,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (details) => _handleTap(details.localPosition),
        onPanStart: (details) {
          final size = context.size;
          if (size == null || !_startsNearPlayer(details.localPosition, size)) {
            return;
          }
          _isDragging = true;
          _updateMovement(details.localPosition);
        },
        onPanUpdate: (details) {
          if (_isDragging) {
            _updateMovement(details.localPosition);
          }
        },
        onPanEnd: (_) => _stopMovement(),
        onPanCancel: _stopMovement,
        child: const SizedBox.expand(),
      ),
    );
  }

  void _handleTap(Offset localPosition) {
    final size = context.size;
    if (size == null) {
      return;
    }
    final normalized = TouchMovement.snapToInteractionPoint(
      TouchMovement.localToWorld(localPosition, size),
    );
    final target = normalized - widget.game.playerPosition;
    if (target.distance > 0.02) {
      widget.game.moveTo(normalized);
      widget.onTap();
    }
  }

  void _updateMovement(Offset localPosition) {
    final size = context.size;
    if (size == null) {
      return;
    }
    final normalized = TouchMovement.localToWorld(localPosition, size);
    final target = normalized - widget.game.playerPosition;
    if (target.distance > 0.02) {
      widget.game.moveTo(normalized);
    } else {
      widget.game.clearMovementTarget();
    }
  }

  bool _startsNearPlayer(Offset localPosition, Size size) {
    final playerLocal = TouchMovement.worldToLocal(
      widget.game.playerPosition,
      size,
    );
    final radius = max(44.0, size.shortestSide * 0.08);
    return (localPosition - playerLocal).distance <= radius;
  }

  void _stopMovement() {
    _isDragging = false;
    widget.game.clearMovementTarget();
  }
}

class _JoystickArea extends StatefulWidget {
  const _JoystickArea({required this.onChanged, required this.alignment});

  final ValueChanged<Offset> onChanged;
  final Alignment alignment;

  @override
  State<_JoystickArea> createState() => _JoystickAreaState();
}

class _JoystickAreaState extends State<_JoystickArea> {
  Offset _knob = Offset.zero;

  void _update(Offset localPosition) {
    final size = context.size;
    if (size == null) {
      return;
    }
    final center = Offset(size.width / 2, size.height / 2);
    var delta = localPosition - center;
    final maxDistance = size.shortestSide * 0.22;
    if (delta.distance > maxDistance) {
      delta = delta / delta.distance * maxDistance;
    }
    setState(() => _knob = delta);
    widget.onChanged(delta / maxDistance);
  }

  void _release() {
    setState(() => _knob = Offset.zero);
    widget.onChanged(Offset.zero);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: AppLocalizations.of(context).floatingJoystickInstruction,
      child: Align(
        alignment: widget.alignment,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: SizedBox.square(
            key: const ValueKey('movement-joystick'),
            dimension: 132,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: (details) => _update(details.localPosition),
              onPanUpdate: (details) => _update(details.localPosition),
              onPanEnd: (_) => _release(),
              onPanCancel: _release,
              child: CustomPaint(painter: _JoystickPainter(knob: _knob)),
            ),
          ),
        ),
      ),
    );
  }
}

class _JoystickPainter extends CustomPainter {
  const _JoystickPainter({required this.knob});

  final Offset knob;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width, size.height) / 2;
    canvas.drawCircle(center, radius, Paint()..color = const Color(0xCCFFFFFF));
    canvas.drawCircle(
      center,
      radius - 3,
      Paint()
        ..color = const Color(0x22315F4A)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    canvas.drawCircle(
      center + knob,
      radius * 0.43,
      Paint()..color = const Color(0xFF315F4A),
    );
    canvas.drawCircle(
      center + knob - const Offset(4, 5),
      radius * 0.18,
      Paint()..color = const Color(0x334FFFFF),
    );
  }

  @override
  bool shouldRepaint(covariant _JoystickPainter oldDelegate) {
    return oldDelegate.knob != knob;
  }
}
