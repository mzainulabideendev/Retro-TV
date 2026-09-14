import 'dart:math';
import 'package:flutter/material.dart';
import '../../models/screen_filter.dart';

/// Paints CRT-style visual effects over the video content. The exact
/// combination of layers follows the current [ScreenFilter]:
///
///   * scanlines / phosphor dots / VHS tracking / antenna static / color
///     tinting (amber, green, sepia, cool, neon, monochrome wash) — each
///     filter composes its own stack, so the picture reads as a
///     believable real TV.
///
/// Respects [reduceMotion] (mapped from `prefers-reduced-motion` /
/// the in-app "disable heavy effects" setting) by disabling flicker and
/// dampening animated noise.
class CrtOverlay extends StatefulWidget {
  final double scanlineOpacity;
  final Color glowColor;
  final bool reduceMotion;
  final bool enabled;
  final ScreenFilter filter;

  const CrtOverlay({
    super.key,
    this.scanlineOpacity = 0.2,
    this.glowColor = const Color(0xFF8AD0FF),
    this.reduceMotion = false,
    this.enabled = true,
    this.filter = ScreenFilter.scanlines,
  });

  @override
  State<CrtOverlay> createState() => _CrtOverlayState();
}

class _CrtOverlayState extends State<CrtOverlay>
    with TickerProviderStateMixin {
  late AnimationController _flickerController;
  late AnimationController _fxController;

  @override
  void initState() {
    super.initState();
    _flickerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..repeat();
    _fxController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 90),
    )..repeat();
  }

  @override
  void dispose() {
    _flickerController.dispose();
    _fxController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled || widget.filter == ScreenFilter.none) {
      return const SizedBox.shrink();
    }

    return IgnorePointer(
      child: AnimatedBuilder(
        animation: Listenable.merge(
          [_flickerController, _fxController],
        ),
        builder: (context, _) {
          return Stack(
            fit: StackFit.expand,
            children: _buildLayers(),
          );
        },
      ),
    );
  }

  List<Widget> _buildLayers() {
    final f = widget.filter;
    final styleOpacity = widget.scanlineOpacity;
    final scanlineOpacity = (styleOpacity * f.scanlineFactor).clamp(0.0, 1.0);
    final t = _flickerController.value;
    final fx = _fxController.value;
    final layers = <Widget>[];

    // Phosphor shadow-mask dot grid (Trinitron feel).
    if (f.wantsDotMask) {
      layers.add(
        CustomPaint(painter: const _DotMaskPainter()),
      );
    }

    // Scanlines (skipped by filters that opt out entirely).
    if (scanlineOpacity > 0) {
      layers.add(
        CustomPaint(painter: _ScanlinePainter(opacity: scanlineOpacity)),
      );
    }

    // Vignette — heavier for cinematic / VHS filters.
    final vignetteStrength = f.wantsVhs ? 0.5 : 0.35;
    layers.add(
      DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.center,
            radius: 1.05,
            colors: [
              Colors.transparent,
              Colors.black.withValues(alpha: vignetteStrength),
            ],
            stops: const [0.6, 1.0],
          ),
        ),
      ),
    );

    // Screen glow (subtle colored edge glow from the phosphor).
    final glowBoost = f.wantsStatic ? 0.1 : (f == ScreenFilter.neon ? 0.28 : 0.15);
    if (glowBoost > 0) {
      layers.add(
        DecoratedBox(
          decoration: BoxDecoration(
            boxShadow: [
              BoxShadow(
                color: widget.glowColor.withValues(alpha: glowBoost),
                blurRadius: 40,
                spreadRadius: -10,
              ),
            ],
          ),
        ),
      );
    }

    // Vintage warm grade (scanline / VHS filters).
    if (f == ScreenFilter.scanlines || f.wantsVhs) {
      layers.add(
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment.center,
              radius: 1.1,
              colors: [
                const Color(0xFFE8C98F).withValues(alpha: 0.035),
                const Color(0xFF5C3D1E).withValues(alpha: 0.09),
              ],
              stops: const [0.45, 1.0],
            ),
          ),
        ),
      );
    }

    // Translucent tint wash — the picture-equivalent of an exact color
    // grade, layered so it reads on top of the YouTube iframe too.
    if (f.wantsTint) {
      layers.add(
        _buildTintWash(f.tint, f.tintOpacity),
      );
    }

    // Coarse phosphor grain (subtle, static speckle).
    layers.add(
      CustomPaint(painter: _GrainPainter(opacity: 0.05 * f.scanlineFactor)),
    );

    // Animated antenna static (low opacity so the program stays watchable).
    if (f.wantsStatic) {
      layers.add(
        CustomPaint(
          painter: _StaticOverlayPainter(seed: (fx * 1e9).round()),
        ),
      );
    }

    // VHS tracking / dropout interference lines.
    if (f.wantsVhs) {
      layers.add(
        CustomPaint(
          painter: _VhsTrackingPainter(trackY: fx),
        ),
      );
    }

    // Very subtle brightness flicker using a sine wave.
    if (!widget.reduceMotion) {
      final flicker = (sin(t * 2 * pi * 6) * 0.015).abs();
      layers.add(
        Container(color: Colors.white.withValues(alpha: flicker)),
      );
    }

    return layers;
  }

  /// A radial tint that stays clear in the center and shows the phosphor
  /// wash mostly toward the edges — mimicking an aged, uneven tube.
  Widget _buildTintWash(Color tint, double strength) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.center,
          radius: 1.0,
          colors: [
            tint.withValues(alpha: strength * 0.25),
            tint.withValues(alpha: strength),
          ],
          stops: const [0.55, 1.0],
        ),
      ),
    );
  }
}

/// Paints the scanline bars.
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

/// Paints the RGB phosphor shadow-mask dot grid. Alternate rows are
/// staggered so the dots form the classic triangular aperture-grille
/// pattern of a color CRT.
class _DotMaskPainter extends CustomPainter {
  const _DotMaskPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const cell = 6.0;
    const radius = 1.4;
    final rPaint = Paint()
      ..color = const Color(0xFFE63B3B).withValues(alpha: 0.55);
    final gPaint = Paint()
      ..color = const Color(0xFF2FD55E).withValues(alpha: 0.55);
    final bPaint = Paint()
      ..color = const Color(0xFF3B7BFF).withValues(alpha: 0.55);

    var row = 0;
    for (double y = 0; y < size.height; y += cell / 2) {
      final isEvenRow = row.isEven;
      var col = 0;
      for (double x = (isEvenRow ? 0.0 : cell / 2);
          x < size.width;
          x += cell) {
        final paint = col % 3 == 0
            ? rPaint
            : col % 3 == 1
            ? gPaint
            : bPaint;
        canvas.drawCircle(Offset(x, y), radius, paint);
        col++;
      }
      row++;
    }
  }

  @override
  bool shouldRepaint(covariant _DotMaskPainter oldDelegate) => false;
}

/// Paints fine static phosphor grain over the picture for a decayed
/// vintage-TV texture.
class _GrainPainter extends CustomPainter {
  final double opacity;
  const _GrainPainter({required this.opacity});

  @override
  void paint(Canvas canvas, Size size) {
    if (opacity <= 0) return;
    final rng = Random(0xC0FFEE);
    final paint = Paint()
      ..color = Colors.black.withValues(alpha: opacity);
    final count =
        (size.width * size.height * 0.015).clamp(120, 3000).toInt();
    for (var i = 0; i < count; i++) {
      final x = rng.nextDouble() * size.width;
      final y = rng.nextDouble() * size.height;
      canvas.drawCircle(
        Offset(x, y),
        1.0 + rng.nextDouble(),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _GrainPainter oldDelegate) =>
      oldDelegate.opacity != opacity;
}

/// Fine animated antenna speckle layered LOW over the picture so the
/// program stays visible while the screen buzzes with interference.
class _StaticOverlayPainter extends CustomPainter {
  final int seed;
  const _StaticOverlayPainter({required this.seed});

  @override
  void paint(Canvas canvas, Size size) {
    final rng = Random(seed);
    final dark = Paint()
      ..color = Colors.black.withValues(alpha: 0.35);
    final light = Paint()
      ..color = Colors.white.withValues(alpha: 0.18);
    final count =
        (size.width * size.height * 0.008).clamp(80, 1600).toInt();
    for (var i = 0; i < count; i++) {
      final x = rng.nextDouble() * size.width;
      final y = rng.nextDouble() * size.height;
      final lightSpot = rng.nextDouble() > 0.72;
      canvas.drawCircle(
        Offset(x, y),
        1.0 + rng.nextDouble() * 2,
        lightSpot ? light : dark,
      );
    }
    // Occasional horizontal glitch band.
    if (rng.nextDouble() > 0.92) {
      final y = rng.nextDouble() * size.height;
      final h = 2.0 + rng.nextDouble() * 6;
      canvas.drawRect(
        Rect.fromLTWH(0, y, size.width, h),
        Paint()..color = Colors.white.withValues(alpha: 0.08),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _StaticOverlayPainter oldDelegate) =>
      oldDelegate.seed != seed;
}

/// Moving VHS tracking bar plus a few dropout lines, for the washed-out
/// magnetic-tape look.
class _VhsTrackingPainter extends CustomPainter {
  final double trackY;
  const _VhsTrackingPainter({required this.trackY});

  @override
  void paint(Canvas canvas, Size size) {
    final rng = Random(0x5A17);

    // Tracking band that slowly scrolls down the screen.
    final bandY = trackY * size.height * 0.9 + 0.05 * size.height;
    final band = Paint()
      ..color = Colors.white.withValues(alpha: 0.07);
    canvas.drawRect(
      Rect.fromLTWH(0, bandY, size.width, 14),
      band,
    );
    canvas.drawRect(
      Rect.fromLTWH(0, bandY + 16, size.width, 2),
      Paint()..color = Colors.black.withValues(alpha: 0.12),
    );

    // Static dropout lines.
    for (var i = 0; i < 6; i++) {
      final y = rng.nextDouble() * size.height;
      final paint = Paint()
        ..color = Colors.black.withValues(alpha: 0.06 + rng.nextDouble() * 0.05);
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, 1), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _VhsTrackingPainter oldDelegate) =>
      oldDelegate.trackY != trackY;
}