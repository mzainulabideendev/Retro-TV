import 'package:flutter_test/flutter_test.dart';
import 'package:retro_tv/models/schedule.dart';
import 'package:retro_tv/services/scheduling_timezone.dart';

void main() {
  setUpAll(() async {
    // Resolves the scheduling timezone from the (unavailable) network,
    // gracefully falling back to UTC — which keeps these tests hermetic.
    await SchedulingClock.init();
  });

  ScheduleEntry oneOff({
    String id = 's1',
    String start = '2026-09-15T20:45:00+00:00',
    String? end,
  }) {
    return ScheduleEntry(
      id: id,
      channelId: 'ch1',
      episodeId: 'ep1',
      startTime: DateTime.parse(start).toUtc(),
      endTime: end != null ? DateTime.parse(end).toUtc() : null,
      dayOfWeek: null,
      priority: 0,
      enabled: true,
    );
  }

  group('ScheduleEntry.fromMap', () {
    test('parses timestamptz to a UTC instant', () {
      final entry = ScheduleEntry.fromMap({
        'id': 's1',
        'channel_id': 'ch1',
        'episode_id': 'ep1',
        // PostgREST commonly returns +00:00 / Z suffixed timestamps
        'start_time': '2026-09-15T20:45:00+00:00',
        'end_time': null,
        'day_of_week': null,
        'priority': 0,
        'enabled': true,
      });
      expect(entry.startTime.isUtc, isTrue);
      expect(entry.startTime.hour, 20);
      expect(entry.startTime.minute, 45);
      expect(entry.statusAt(DateTime.utc(2026, 9, 15, 19)), ScheduleStatus.scheduled);
    });

    test('preserves wall-clock interpretation of a +05:30 offset', () {
      final entry = ScheduleEntry.fromMap({
        'id': 's1',
        'channel_id': 'ch1',
        'episode_id': 'ep1',
        'start_time': '2026-09-15T20:45:00+05:30',
        'end_time': null,
        'day_of_week': null,
        'priority': 0,
        'enabled': true,
      });
      // 20:45 IST == 15:15 UTC — the stored instant must be 15:15Z.
      expect(entry.startTime, DateTime.utc(2026, 9, 15, 15, 15));
    });
  });

  group('ScheduleEntry.statusAt', () {
    final now = DateTime.utc(2026, 9, 15, 12, 0);

    test('future one-off -> scheduled', () {
      expect(
        oneOff(start: '2026-09-15T13:00:00+00:00').statusAt(now),
        ScheduleStatus.scheduled,
      );
    });

    test('currently airing -> live', () {
      expect(
        oneOff(
          start: '2026-09-15T11:00:00+00:00',
          end: '2026-09-15T13:30:00+00:00',
        ).statusAt(now),
        ScheduleStatus.live,
      );
    });

    test('past -> completed', () {
      expect(
        oneOff(
          start: '2026-09-15T10:00:00+00:00',
          end: '2026-09-15T11:00:00+00:00',
        ).statusAt(now),
        ScheduleStatus.completed,
      );
    });

    test('recurring template -> recurring', () {
      final entry = ScheduleEntry(
        id: 's1',
        channelId: 'ch1',
        episodeId: 'ep1',
        startTime: DateTime.utc(2026, 9, 14, 20, 45), // Monday
        endTime: null,
        dayOfWeek: 1,
        priority: 0,
        enabled: true,
      );
      expect(entry.statusAt(now), ScheduleStatus.recurring);
      expect(entry.displayStart, contains('Mon'));
    });
  });
}