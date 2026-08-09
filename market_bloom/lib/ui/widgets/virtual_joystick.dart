import 'dart:math';

import 'package:flutter/material.dart';

class VirtualJoystick extends StatefulWidget {
  const VirtualJoystick({super.key, required this.onChanged, this.size = 112});

  final ValueChanged<Offset> onChanged;
  final double size;

  @override
  State<VirtualJoystick> createState() => _VirtualJoystickState();
}

class _VirtualJoystickState extends State<VirtualJoystick> {
  Offset _knob = Offset.zero;

  void _update(Offset localPosition) {
    final center = Offset(widget.size / 2, widget.size / 2);
    var delta = localPosition - center;
    final maxDistance = widget.size * 0.29;
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
      label: 'Movement joystick',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (details) => _update(details.localPosition),
        onPanUpdate: (details) => _update(details.localPosition),
        onPanEnd: (_) => _release(),
        onPanCancel: _release,
        child: SizedBox.square(
          dimension: widget.size,
          child: CustomPaint(painter: _JoystickPainter(knob: _knob)),
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
