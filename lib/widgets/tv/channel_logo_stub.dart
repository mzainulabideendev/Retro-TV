import 'package:flutter/material.dart';

/// Non-web implementation: a normal network image.
Widget buildChannelLogo({
  required String channelId,
  required String url,
  required double width,
  required double height,
  required double borderRadius,
}) {
  return ClipRRect(
    borderRadius: BorderRadius.circular(borderRadius),
    child: Image.network(
      url,
      width: width,
      height: height,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) =>
          const Icon(Icons.broken_image_outlined, color: Colors.white54),
    ),
  );
}
