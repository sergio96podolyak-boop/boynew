import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

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
    if (widget.controlMode == ControlMode.joystick) {
      return _JoystickArea(
        game: widget.game,
        onChanged: widget.game.setMovement,
      );
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (details) {
        if (_isUIWidget(details.localPosition)) {
          return;
        }
        _dragStart = details.localPosition;
        _handleTap(details.localPosition);
      },
      onPanStart: (details) {
        if (_isUIWidget(details.localPosition)) {
          return;
        }
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
      child: Container(
        color: Colors.transparent,
        child: const Center(
          child: Text(
            'Tap or drag to move',
            style: TextStyle(
              color: Color(0xFF315F4A),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  bool _isUIWidget(Offset localPosition) {
    final size = context.size;
    if (size == null) {
      return false;
    }
    final bottomNavHeight = kBottomNavigationBarHeight +
        MediaQuery.of(context).padding.bottom;
    if (localPosition.dy > size.height - bottomNavHeight - 60) {
      return true;
    }
    return false;
  }

  void _handleTap(Offset localPosition) {
    final size = context.size;
    if (size == null) {
      return;
    }
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) {
      return;
    }
    final local = renderBox.globalToLocal(localPosition);
    final normalized = Offset(
      (local.dx / size.width).clamp(0.06, 0.94),
      (local.dy / size.height).clamp(0.09, 0.94),
    );
    final target = normalized - widget.game.playerPosition;
    if (target.distance > 0.02) {
      widget.game.setMovement(target / target.distance);
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          widget.game.setMovement(Offset.zero);
        }
      });
    }
  }

  void _updateMovement(Offset localPosition) {
    final size = context.size;
    if (size == null || _dragStart == null) {
      return;
    }
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) {
      return;
    }
    final local = renderBox.globalToLocal(localPosition);
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
  const _JoystickArea({
    required this.game,
    required this.onChanged,
  });

  final GameController game;
  final ValueChanged<Offset> onChanged;

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
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (details) => _update(details.localPosition),
      onPanUpdate: (details) => _update(details.localPosition),
      onPanEnd: (_) => _release(),
      onPanCancel: _release,
      child: Container(
        color: Colors.transparent,
        child: Center(
          child: CustomPaint(
            size: Size.square(context.size?.shortestSide ?? 120),
            painter: _JoystickPainter(knob: _knob),
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