import 'dart:math';
import 'package:flutter/material.dart';

/// Paints CRT-style visual effects (scanlines, vignette, screen glow,
/// subtle chromatic aberration hint, flicker) over the video content.
///
/// Respects [reduceMotion] (mapped from `prefers-reduced-motion` /
/// the in-app "disable heavy effects" setting) by disabling flicker and
/// dampening animated noise.
class CrtOverlay extends StatefulWidget {
  final double scanlineOpacity;
  final Color glowColor;
  final bool reduceMotion;
  final bool enabled;

  const CrtOverlay({
    super.key,
    this.scanlineOpacity = 0.2,
    this.glowColor = const Color(0xFF8AD0FF),
    this.reduceMotion = false,
    this.enabled = true,
  });

  @override
  State<CrtOverlay> createState() => _CrtOverlayState();
}

class _CrtOverlayState extends State<CrtOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _flickerController;

  @override
  void initState() {
    super.initState();
    _flickerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..repeat();
  }

  @override
  void dispose() {
    _flickerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return const SizedBox.shrink();

    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Scanlines
          CustomPaint(
            painter: _ScanlinePainter(opacity: widget.scanlineOpacity),
          ),
          // Vignette
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.center,
                radius: 1.05,
                colors: [
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.35),
                ],
                stops: const [0.6, 1.0],
              ),
            ),
          ),
          // Screen glow (subtle colored edge glow)
          DecoratedBox(
            decoration: BoxDecoration(
              boxShadow: [
                BoxShadow(
                  color: widget.glowColor.withValues(alpha: 0.15),
                  blurRadius: 40,
                  spreadRadius: -10,
                ),
              ],
            ),
          ),
          if (!widget.reduceMotion)
            AnimatedBuilder(
              animation: _flickerController,
              builder: (context, _) {
                final t = _flickerController.value;
                // Very subtle brightness flicker using a sine wave.
                final flicker = (sin(t * 2 * pi * 6) * 0.015).abs();
                return Container(
                  color: Colors.white.withValues(alpha: flicker),
                );
              },
            ),
        ],
      ),
    );
  }
}

class _ScanlinePainter extends CustomPainter {
  final double opacity;
  const _ScanlinePainter({required this.opacity});

  @override
  void paint(Canvas canvas, Size size) {
    if (opacity <= 0) return;
    final paint = Paint()
      ..color = Colors.black.withValues(alpha: opacity * 0.5);
    const lineHeight = 2.0;
    const gap = 2.0;
    double y = 0;
    while (y < size.height) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, lineHeight), paint);
      y += lineHeight + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _ScanlinePainter oldDelegate) =>
      oldDelegate.opacity != opacity;
}
