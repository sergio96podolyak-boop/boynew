import 'dart:math';

import 'package:flutter/material.dart';

import '../../game/game_controller.dart';
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

  @override
  State<TouchMovement> createState() => _TouchMovementState();
}

class _TouchMovementState extends State<TouchMovement> {
  Offset? _dragStart;
  bool _isDragging = false;

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
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (details) {
        _handleTap(details.localPosition);
      },
      onPanStart: (details) {
        _dragStart = details.localPosition;
        _isDragging = true;
        _updateMovement(details.localPosition);
      },
      onPanUpdate: (details) {
        if (!_isDragging || _dragStart == null) {
          return;
        }
        _updateMovement(details.localPosition);
      },
      onPanEnd: (_) {
        _isDragging = false;
        _dragStart = null;
        widget.game.setMovement(Offset.zero);
      },
      onPanCancel: () {
        _isDragging = false;
        _dragStart = null;
        widget.game.setMovement(Offset.zero);
      },
      child: const SizedBox.expand(),
    );
  }

  void _handleTap(Offset localPosition) {
    final size = context.size;
    if (size == null) {
      return;
    }
    final local = localPosition;
    final normalized = Offset(
      (local.dx / size.width).clamp(0.06, 0.94),
      (local.dy / size.height).clamp(0.09, 0.94),
    );
    final target = normalized - widget.game.playerPosition;
    if (target.distance > 0.02) {
      widget.game.moveTo(normalized);
      widget.onTap();
    }
  }

  void _updateMovement(Offset localPosition) {
    final size = context.size;
    if (size == null || _dragStart == null) {
      return;
    }
    final local = localPosition;
    final normalized = Offset(
      (local.dx / size.width).clamp(0.06, 0.94),
      (local.dy / size.height).clamp(0.09, 0.94),
    );
    final target = normalized - widget.game.playerPosition;
    if (target.distance > 0.02) {
      widget.game.setMovement(target / target.distance);
    } else {
      widget.game.setMovement(Offset.zero);
    }
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
    return Align(
      alignment: widget.alignment,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: SizedBox.square(
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
