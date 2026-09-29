import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/tv_state.dart';

/// Applies the Windows "browser zoom" to the whole application.
///
/// On Windows the zoom buttons and the Ctrl + / - shortcuts behave like a
/// browser's zoom, so the ENTIRE window is minimised or maximised - the TV
/// picture, the remote panel, the channel guide and every dialog scale
/// together. That is achieved in two coordinated steps:
///
///  1. The logical viewport handed to [child] is divided by [zoom], so
///     layout really does happen in a proportionally smaller space (which is
///     what makes widgets shrink instead of just being stretched).
///  2. The result is rendered [zoom] times larger again, anchored to the
///     top-left, so the window is completely filled exactly as before.
///
/// Splitting it this way is what lets a single zoom value control the TV and
/// the remote at once, and it is why the old picture-only `Transform.scale`
/// (which cropped the CRT screen) is no longer needed.
///
/// On non-Windows platforms [zoom] is always 1.0 and this is a pass-through
/// that only keeps the font-scale cap.
class WindowZoom extends StatelessWidget {
  final Widget child;

  const WindowZoom({super.key, required this.child}) : _zoomOverride = null;

  /// Exposed for tests: applies a fixed zoom to [child] without needing the
  /// full app shell, so the scaling maths can be asserted directly.
  const WindowZoom.withZoom({
    super.key,
    required this.child,
    required double zoom,
  }) : _zoomOverride = zoom;

  final double? _zoomOverride;

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final zoom = _zoomOverride ??
        (isWindowsDesktop
            ? context.select<TvState, double>((tv) => tv.zoom)
            : 1.0);

    // Always cap system font scaling so no screen overflows.
    Widget result = MediaQuery(
      data: mediaQuery.copyWith(
        textScaler: mediaQuery.textScaler.clamp(maxScaleFactor: 1.3),
        size: zoom == 1.0
            ? mediaQuery.size
            : Size(
                mediaQuery.size.width / zoom,
                mediaQuery.size.height / zoom,
              ),
      ),
      child: child,
    );

    if (zoom == 1.0) return result;

    return LayoutBuilder(
      builder: (context, constraints) => ClipRect(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: constraints.maxWidth / zoom,
            height: constraints.maxHeight / zoom,
            child: result,
          ),
        ),
      ),
    );
  }
}
