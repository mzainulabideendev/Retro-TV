import 'package:flutter/material.dart';

/// A selectable retro TV visual style/skin.
class TvStyle {
  final String id;
  final String name;
  final String slug;
  final String? description;
  final String? era;
  final String? previewImage;
  final Map<String, dynamic> themeConfig;
  final String screenAspectRatio;
  final int defaultVolume;
  final String? defaultChannelNumber;
  final bool enabled;
  final int sortOrder;

  TvStyle({
    required this.id,
    required this.name,
    required this.slug,
    this.description,
    this.era,
    this.previewImage,
    required this.themeConfig,
    required this.screenAspectRatio,
    required this.defaultVolume,
    this.defaultChannelNumber,
    required this.enabled,
    required this.sortOrder,
  });

  factory TvStyle.fromMap(Map<String, dynamic> map) {
    return TvStyle(
      id: map['id'] as String,
      name: map['name'] as String? ?? 'Unnamed Style',
      slug: map['slug'] as String? ?? '',
      description: map['description'] as String?,
      era: map['era'] as String?,
      previewImage: map['preview_image'] as String?,
      themeConfig: (map['theme_config'] as Map?)?.cast<String, dynamic>() ?? {},
      screenAspectRatio: map['screen_aspect_ratio'] as String? ?? '4:3',
      defaultVolume: (map['default_volume'] as num?)?.toInt() ?? 50,
      defaultChannelNumber: map['default_channel_number']?.toString(),
      enabled: map['enabled'] as bool? ?? true,
      sortOrder: (map['sort_order'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toInsertMap() => {
    'name': name,
    'slug': slug,
    'description': description,
    'era': era,
    'preview_image': previewImage,
    'theme_config': themeConfig,
    'screen_aspect_ratio': screenAspectRatio,
    'default_volume': defaultVolume,
    'enabled': enabled,
    'sort_order': sortOrder,
  };

  Color _colorFromHex(String? hex, Color fallback) {
    if (hex == null || hex.isEmpty) return fallback;
    var h = hex.replaceAll('#', '');
    if (h.length == 6) h = 'FF$h';
    try {
      return Color(int.parse(h, radix: 16));
    } catch (_) {
      return fallback;
    }
  }

  Color get bodyColor => _colorFromHex(
    themeConfig['bodyColor'] as String?,
    const Color(0xFF4A4A52),
  );
  Color get bezelColor => _colorFromHex(
    themeConfig['bezelColor'] as String?,
    const Color(0xFF33333A),
  );
  Color get screenTint => _colorFromHex(
    themeConfig['screenTint'] as String?,
    const Color(0xFFE6F0FF),
  );
  Color get accentColor => _colorFromHex(
    themeConfig['accentColor'] as String?,
    const Color(0xFFFF5F6D),
  );
  Color get knobColor => _colorFromHex(
    themeConfig['knobColor'] as String?,
    const Color(0xFF20202A),
  );
  Color get glowColor =>
      _colorFromHex(themeConfig['glow'] as String?, const Color(0xFF8AD0FF));
  bool get hasGrain => themeConfig['grain'] as bool? ?? true;
  double get scanlineOpacity =>
      (themeConfig['scanlineOpacity'] as num?)?.toDouble() ?? 0.2;
  double get curvature =>
      (themeConfig['curvature'] as num?)?.toDouble() ?? 0.14;
  bool get isPlayful => themeConfig['playful'] as bool? ?? false;
  bool get isNeon => themeConfig['neon'] as bool? ?? false;
}
