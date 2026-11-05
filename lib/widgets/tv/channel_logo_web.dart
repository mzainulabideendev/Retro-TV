import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/rendering.dart' show PlatformViewHitTestBehavior;
import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

/// View types already registered with the platform-view registry.
///
/// Registration is global and must happen exactly once per view type, but the
/// factory itself can be called many times (each call creates a fresh `<img>`).
final Set<String> _registeredViewTypes = <String>{};

String _viewTypeFor(String channelId, String url) {
  final digest = url.hashCode.toUnsigned(32).toRadixString(16);
  return 'rtv-channel-logo-$channelId-$digest';
}

/// Web implementation: a channel-specific `<img>` platform view.
Widget buildChannelLogo({
  required String channelId,
  required String url,
  required double width,
  required double height,
  required double borderRadius,
}) {
  final viewType = _viewTypeFor(channelId, url);
  if (_registeredViewTypes.add(viewType)) {
    ui_web.platformViewRegistry.registerViewFactory(viewType, (int viewId) {
      final img = web.document.createElement('img') as web.HTMLImageElement;
      img.src = url;
      img.alt = '';
      img.draggable = false;
      img.style
        ..width = '100%'
        ..height = '100%'
        ..objectFit = 'contain'
        ..borderRadius = '${borderRadius}px'
        ..pointerEvents = 'none';
      img.onerror = ((web.Event _) {
        // Hide broken images entirely instead of the browser's error glyph.
        img.style.display = 'none';
      }).toJS;
      return img;
    });
  }

  return SizedBox(
    width: width,
    height: height,
    child: HtmlElementView(
      // Unique per channel + URL: the platform view can never inherit another
      // channel's <img> when the guide list is filtered or reordered.
      viewType: viewType,
      hitTestBehavior: PlatformViewHitTestBehavior.transparent,
    ),
  );
}
