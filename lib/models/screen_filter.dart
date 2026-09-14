import 'package:flutter/material.dart';

const List<double> _kGrayscaleMatrix = [
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0, //
  0, 0, 0, 1, 0,
];

const List<double> _kSepiaMatrix = [
  0.393, 0.769, 0.189, 0, 0, //
  0.349, 0.686, 0.168, 0, 0, //
  0.272, 0.534, 0.131, 0, 0, //
  0, 0, 0, 1, 0,
];

const List<double> _kAmberMatrix = [
  0.400, 0.600, 0.000, 0, 0, //
  0.220, 0.420, 0.100, 0, 0, //
  0.060, 0.160, 0.040, 0, 0, //
  0, 0, 0, 1, 0,
];

const List<double> _kGreenMatrix = [
  0.000, 0.300, 0.000, 0, 0, //
  0.100, 0.600, 0.100, 0, 0, //
  0.000, 0.150, 0.000, 0, 0, //
  0, 0, 0, 1, 0,
];

const List<double> _kCoolMatrix = [
  0.85, 0.00, 0.00, 0, 0, //
  0.00, 0.92, 0.00, 0, 0, //
  0.00, 0.00, 1.15, 0, 0, //
  0, 0, 0, 1, 0,
];

const List<double> _kNeonMatrix = [
  1.35, -0.18, -0.18, 0, 0, //
  -0.18, 1.35, -0.18, 0, 0, //
  -0.18, -0.18, 1.35, 0, 0, //
  0, 0, 0, 1, 0,
];

/// A user-selectable picture filter for the TV screen, giving the
/// screen "real TV vibes" (scanlines, phosphor shadow mask, VHS
/// tracking, antenna static, amber/green monochrome tubes, etc.).
///
/// The effect is composed of two parts:
///  * [matrix] — an exact color transform applied to the picture widget
///    (effective on content Flutter itself paints; the YouTube iframe on
///    web/Android is an external platform view that Flutter cannot repaint).
///  * [tint]/[tintOpacity] + texture layers — translucent washes and
///    overlays painted on top of the picture, which read as the same
///    vintage grade everywhere (including the iframe on the web build).
enum ScreenFilter {
  none(
    id: 'none',
    label: 'Clear',
    description: 'No picture effects — raw video signal.',
    icon: Icons.highlight_off,
    matrix: null,
    tint: Colors.transparent,
    tintOpacity: 0,
    scanlineFactor: 0,
  ),
  scanlines(
    id: 'scanlines',
    label: 'Scanlines',
    description: 'Classic cathode-ray scanlines with a warm, aged glow.',
    icon: Icons.gradient,
    matrix: null,
    tint: Colors.transparent,
    tintOpacity: 0,
    scanlineFactor: 1.0,
  ),
  dots(
    id: 'dots',
    label: 'Phosphor Dots',
    description: 'Visible RGB phosphor shadow mask (Trinitron look).',
    icon: Icons.blur_circular,
    matrix: null,
    tint: Colors.transparent,
    tintOpacity: 0,
    scanlineFactor: 0.35,
  ),
  vhs(
    id: 'vhs',
    label: 'VHS Retro',
    description: 'Tracking lines, color bleed and a soft magnetic wash.',
    icon: Icons.videocam,
    matrix: null,
    tint: Color(0xFFE8C98F),
    tintOpacity: 0.16,
    scanlineFactor: 0.7,
  ),
  staticNoise(
    id: 'static',
    label: 'TV Static',
    description: 'Antenna signal interference and live broadcast static.',
    icon: Icons.grain,
    matrix: null,
    tint: Colors.transparent,
    tintOpacity: 0,
    scanlineFactor: 0.5,
  ),
  mono(
    id: 'mono',
    label: 'Black & White',
    description: 'Crisp monochrome picture, like early broadcast TV.',
    icon: Icons.contrast,
    matrix: _kGrayscaleMatrix,
    tint: Color(0xFF9A9A9A),
    tintOpacity: 0.10,
    scanlineFactor: 1.0,
  ),
  sepia(
    id: 'sepia',
    label: 'Sepia',
    description: 'Aged photographic wash with a faded, nostalgic grade.',
    icon: Icons.photo_filter,
    matrix: _kSepiaMatrix,
    tint: Color(0xFF8A5A2B),
    tintOpacity: 0.18,
    scanlineFactor: 1.0,
  ),
  amber(
    id: 'amber',
    label: 'Amber Tube',
    description: 'Warm orange monochrome phosphor (radar / terminal look).',
    icon: Icons.wb_incandescent_outlined,
    matrix: _kAmberMatrix,
    tint: Color(0xFFFF9E2E),
    tintOpacity: 0.32,
    scanlineFactor: 1.0,
  ),
  green(
    id: 'green',
    label: 'Green Phosphor',
    description: 'Green monochrome phosphor, like classic computer monitors.',
    icon: Icons.monitor_outlined,
    matrix: _kGreenMatrix,
    tint: Color(0xFF35FF64),
    tintOpacity: 0.28,
    scanlineFactor: 0.85,
  ),
  cool(
    id: 'cool',
    label: 'Cool Blue',
    description: 'Blue-tinted phosphor glow for a cold, moody picture.',
    icon: Icons.ac_unit,
    matrix: _kCoolMatrix,
    tint: Color(0xFF66C6FF),
    tintOpacity: 0.18,
    scanlineFactor: 1.0,
  ),
  neon(
    id: 'neon',
    label: 'Neon Glow',
    description: 'Saturated, high-contrast cyberpunk colors and heavy glow.',
    icon: Icons.auto_awesome,
    matrix: _kNeonMatrix,
    tint: Color(0xFFFF00D4),
    tintOpacity: 0.12,
    scanlineFactor: 1.25,
  );

  final String id;
  final String label;
  final String description;
  final IconData icon;
  final List<double>? matrix;
  final Color tint;
  final double tintOpacity;

  /// How strongly the style's scanlines show through this filter.
  /// 0 disables scanlines for that filter.
  final double scanlineFactor;

  const ScreenFilter({
    required this.id,
    required this.label,
    required this.description,
    required this.icon,
    required this.matrix,
    required this.tint,
    required this.tintOpacity,
    required this.scanlineFactor,
  });

  /// Whether a translucent tint wash should be layered over the picture.
  bool get wantsTint => tintOpacity > 0;

  /// Whether vertical RGB phosphor dots should be rendered.
  bool get wantsDotMask => this == ScreenFilter.dots;

  /// Whether animated antenna static should be layered over the picture.
  bool get wantsStatic => this == ScreenFilter.staticNoise;

  /// Whether VHS tracking / dropout interference lines are rendered.
  bool get wantsVhs => this == ScreenFilter.vhs;

  /// Whether the picture is exact-color-graded (Flutter-rendered content).
  bool get wantsColorGrade => matrix != null;
}