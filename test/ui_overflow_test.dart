import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:retro_tv/models/episode.dart';
import 'package:retro_tv/models/schedule.dart';
import 'package:retro_tv/models/tv_style.dart';
import 'package:retro_tv/models/up_next.dart';
import 'package:retro_tv/widgets/tv/fullscreen_tv_view.dart';
import 'package:retro_tv/services/scheduling_timezone.dart';
import 'package:retro_tv/services/tv_state.dart';
import 'package:retro_tv/widgets/tv/crt_tv_frame.dart';
import 'package:retro_tv/widgets/tv/next_up_card.dart';
import 'package:retro_tv/widgets/tv/tv_controls.dart';

/// Regression guard against horizontal overflow ("RIGHT OVERFLOWED BY N
/// PIXELS") in every widget shown while a channel is playing, across small
/// viewport widths and large text scales. Any RenderFlex overflow surfaces
/// as a test failure via [WidgetTester.takeException].
void main() {
  final widths = <double>[280, 320, 360, 480];
  final scales = <double>[1.0, 1.3];

  setUpAll(() {
    SchedulingClock.debugSetZoneForTesting('Asia/Karachi');
  });

  TvStyle buildStyle() => TvStyle(
    id: 's1',
    name: 'Classic Walnut',
    slug: 'classic-walnut',
    description: null,
    era: '1970s',
    previewImage: null,
    themeConfig: const {
      'bodyColor': '#5A3928',
      'bezelColor': '#261A15',
      'screenTint': '#DCEEFF',
      'accentColor': '#E0A83E',
      'knobColor': '#17110E',
      'glow': '#8AD0FF',
      'grain': true,
      'scanlineOpacity': 0.22,
      'curvature': 0.16,
    },
    screenAspectRatio: '4:3',
    defaultVolume: 50,
    enabled: true,
    sortOrder: 0,
  );

  Episode buildEpisode() => Episode(
    id: 'e1',
    channelId: 'c1',
    seasonNumber: 1,
    title: 'A Very Long Program Title That Wraps Around For Testing',
    youtubeVideoId: 'dQw4w9WgXcQ',
    status: 'published',
    enabled: true,
    sortOrder: 0,
  );

  Future<Object?> pumpBoxed(
    WidgetTester tester, {
    required Widget child,
    required double width,
    required double textScale,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: Scaffold(
            backgroundColor: Colors.black,
            body: Center(
              child: SizedBox(width: width, height: 700, child: child),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final e = tester.takeException();
    return e;
  }

  void expectNoLayoutOverflow(
    Object? e, {
    required double width,
    required double textScale,
    required String label,
  }) {
    expect(
      e,
      isNull,
      reason: 'Overflow detected in $label at width=$width, scale=$textScale',
    );
  }

  testWidgets('NextUpCard scheduled announcement never overflows', (
    tester,
  ) async {
    final announcement = <String, dynamic>{
      'title': 'The Longest Running Retro Show Ever Broadcast On Channel One',
      'youtube_video_id': 'dQw4w9WgXcQ',
      'thumbnail_url': '',
      'channel_number': 1,
      'channel_name': 'RETRO CLASSIC TV',
      'recurring': true,
      'day_of_week': 1,
      'start_time': DateTime.utc(2026, 9, 14, 19, 30),
    };
    for (final w in widths) {
      for (final s in scales) {
        expectNoLayoutOverflow(
          await pumpBoxed(
            tester,
            width: w,
            textScale: s,
            child: NextUpCard(
              accentColor: const Color(0xFFE0A83E),
              announcement: announcement,
            ),
          ),
          width: w,
          textScale: s,
          label: 'NextUpCard scheduled announcement',
        );
      }
    }
  });

  testWidgets('NextUpCard one-off announcement and loop entry never overflow', (
    tester,
  ) async {
    final announcement = <String, dynamic>{
      'title': 'One-Off Anniversary Special With A Generous Description Text',
      'youtube_video_id': 'dQw4w9WgXcQ',
      'thumbnail_url': '',
      'channel_number': 2,
      'channel_name': 'FILM GREATS',
      'recurring': false,
      'day_of_week': null,
      'start_time': DateTime.utc(2026, 9, 25, 22, 0),
    };
    final loop = UpNext(
      episode: buildEpisode(),
      schedule: ScheduleEntry(
        id: 's1',
        channelId: 'c1',
        episodeId: 'e1',
        startTime: DateTime.utc(2026, 9, 16, 20, 15),
        dayOfWeek: 3,
        priority: 0,
        enabled: true,
      ),
    );
    for (final w in widths) {
      for (final s in scales) {
        expectNoLayoutOverflow(
          await pumpBoxed(
            tester,
            width: w,
            textScale: s,
            child: NextUpCard(
              accentColor: const Color(0xFFE0A83E),
              announcement: announcement,
              upNext: loop,
            ),
          ),
          width: w,
          textScale: s,
          label: 'NextUpCard one-off announcement',
        );
        expectNoLayoutOverflow(
          await pumpBoxed(
            tester,
            width: w,
            textScale: s,
            child: NextUpCard(
              accentColor: const Color(0xFFE0A83E),
              upNext: loop,
            ),
          ),
          width: w,
          textScale: s,
          label: 'NextUpCard loop entry',
        );
      }
    }
  });

  testWidgets('CrtTvFrame playing view never overflows', (tester) async {
    for (final w in widths) {
      for (final s in scales) {
        expectNoLayoutOverflow(
          await pumpBoxed(
            tester,
            width: w,
            textScale: s,
            child: CrtTvFrame(
              style: buildStyle(),
              screenChild: const ColoredBox(color: Colors.black),
              poweredOn: true,
              startingUp: false,
              channelChanging: false,
              reduceEffects: false,
              channelNumber: 1,
              channelName: 'RETRO CLASSIC TV',
              volume: 56,
              muted: false,
              showVolumeOsd: true,
            ),
          ),
          width: w,
          textScale: s,
          label: 'CrtTvFrame',
        );
      }
    }
  });

  testWidgets('TvControls remote panel never overflows', (tester) async {
    final tv = TvState();
    for (final w in widths) {
      for (final s in scales) {
        expectNoLayoutOverflow(
          await pumpBoxed(
            tester,
            width: w,
            textScale: s,
            child: TvControls(
              tv: tv,
              accentColor: const Color(0xFFE0A83E),
              onGuide: () {},
              onFullscreen: () {},
            ),
          ),
          width: w,
          textScale: s,
          label: 'TvControls',
        );
      }
    }
  });

  testWidgets('Full screen TV view never overflows', (tester) async {
    for (final w in widths) {
      for (final s in scales) {
        tester.view.physicalSize = Size(w, 480);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(
                textScaler: TextScaler.linear(s),
                size: Size(w, 480),
              ),
              child: FullscreenTvView(
                tv: TvState(),
                screen: const ColoredBox(color: Colors.black),
                onExit: () {},
              ),
            ),
          ),
        );
        await tester.pump();
        expect(
          tester.takeException(),
          isNull,
          reason: 'Fullscreen overflow detected at width=$w, scale=$s',
        );
      }
    }
  });
}
