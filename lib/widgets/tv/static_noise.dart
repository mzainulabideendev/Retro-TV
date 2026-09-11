import 'dart:math';
import 'package:flutter/material.dart';

/// Animated TV static/noise effect used during power-on and channel
/// switching transitions.
class StaticNoise extends StatefulWidget {
  final bool active;
  const StaticNoise({super.key, required this.active});

  @override
  State<StaticNoise> createState() => _StaticNoiseState();
}

class _StaticNoiseState extends State<StaticNoise>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 80),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return CustomPaint(
          painter: _NoisePainter(seed: DateTime.now().millisecondsSinceEpoch),
          child: Container(color: Colors.black),
        );
      },
    );
  }
}

class _NoisePainter extends CustomPainter {
  final int seed;
  const _NoisePainter({required this.seed});

  @override
  void paint(Canvas canvas, Size size) {
    final rng = Random(seed);
    final paint = Paint();
    const cell = 4.0;
    for (double y = 0; y < size.height; y += cell) {
      for (double x = 0; x < size.width; x += cell) {
        final v = rng.nextDouble();
        final gray = (v * 255).toInt();
        paint.color = Color.fromARGB(255, gray, gray, gray);
        canvas.drawRect(Rect.fromLTWH(x, y, cell, cell), paint);
      }
    }
    // Horizontal glitch bars
    for (int i = 0; i < 4; i++) {
      final y = rng.nextDouble() * size.height;
      final h = rng.nextDouble() * 8 + 2;
      paint.color = Colors.white.withValues(alpha: 0.15);
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, h), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _NoisePainter oldDelegate) => true;
}
