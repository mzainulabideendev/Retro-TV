import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:retro_tv/services/tv_state.dart';
import 'package:retro_tv/widgets/window_zoom.dart';

/// Guards the Windows "browser zoom" contract: zooming must resize the WHOLE
/// window (TV picture and remote panel together), not just the picture.
///
/// [WindowZoom.withZoom] is used so the scaling maths is asserted directly
/// instead of booting the entire app, which pulls in Supabase, the CRT
/// animations and a live network stack.
void main() {
  const viewport = Size(800, 600);

  /// A stand-in for the TV + remote layout: its size is what proves the whole
  /// window is being scaled rather than just the picture.
  Widget surface() => const SizedBox.expand(key: ValueKey('surface'));

  /// The zoom is Windows-only, so pretend the test runs on Windows.
  ///
  /// Both the platform override and the view overrides are reset in a
  /// `finally` INSIDE the test body: flutter_test verifies its foundation
  /// debug variables before any tearDown/addTearDown callback runs, so
  /// cleaning up there would still fail every test.
  Future<void> withWindowsViewport(
    WidgetTester tester,
    Future<void> Function() body,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    tester.view.physicalSize = viewport;
    tester.view.devicePixelRatio = 1.0;
    try {
      await body();
    } finally {
      debugDefaultTargetPlatformOverride = null;
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    }
  }

  Future<void> pumpZoom(
    WidgetTester tester, {
    required double zoom,
    required Widget child,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider<TvState>.value(
          value: TvState(),
          child: WindowZoom.withZoom(zoom: zoom, child: child),
        ),
      ),
    );
  }

  Size viewportOf(WidgetTester tester) =>
      MediaQuery.of(tester.element(find.byKey(const ValueKey('surface')))).size;

  testWidgets('at 100% nothing is scaled and the viewport is untouched',
      (WidgetTester tester) async {
    await withWindowsViewport(tester, () async {
      await pumpZoom(tester, zoom: 1.0, child: surface());

      expect(find.byType(FittedBox), findsNothing);

      final size = viewportOf(tester);
      expect(size.width, closeTo(800, 0.5));
      expect(size.height, closeTo(600, 0.5));
    });
  });

  testWidgets(
      'zooming in shrinks the logical viewport so the whole UI grows',
      (WidgetTester tester) async {
    await withWindowsViewport(tester, () async {
      await pumpZoom(tester, zoom: 1.0, child: surface());
      final base = viewportOf(tester);

      await pumpZoom(tester, zoom: 1.5, child: surface());

      // Layout now happens in a viewport 1.5x smaller...
      final zoomed = viewportOf(tester);
      expect(zoomed.width, closeTo(base.width / 1.5, 0.5));
      expect(zoomed.height, closeTo(base.height / 1.5, 0.5));

      // ...and is then rendered 1.5x larger, so the window is still filled
      // and the TV picture and the remote panel both grew.
      expect(find.byType(FittedBox), findsOneWidget);
      final fitted = tester.widget<FittedBox>(find.byType(FittedBox));
      expect(fitted.fit, BoxFit.scaleDown);
      expect(fitted.alignment, Alignment.topLeft);
    });
  });

  testWidgets(
      'zooming out enlarges the logical viewport so the whole UI shrinks',
      (WidgetTester tester) async {
    await withWindowsViewport(tester, () async {
      await pumpZoom(tester, zoom: 0.5, child: surface());

      final size = viewportOf(tester);
      expect(size.width, closeTo(1600, 0.5));
      expect(size.height, closeTo(1200, 0.5));
      expect(find.byType(FittedBox), findsOneWidget);
    });
  });

  testWidgets('the zoom is clamped to the supported browser range',
      (WidgetTester tester) async {
    // TvState persists the zoom through SharedPreferences; without this mock
    // the platform channel call never completes and the awaits hang forever.
    SharedPreferences.setMockInitialValues(<String, Object>{});

    final tv = TvState();
    expect(tv.zoom, 1.0);

    for (var i = 0; i < 20; i++) {
      await tv.zoomIn();
    }
    expect(tv.zoom, TvState.maxZoom);
    expect(tv.canZoomIn, isFalse);

    for (var i = 0; i < 30; i++) {
      await tv.zoomOut();
    }
    expect(tv.zoom, TvState.minZoom);
    expect(tv.canZoomOut, isFalse);

    await tv.resetZoom();
    expect(tv.zoom, 1.0);
  });
}
