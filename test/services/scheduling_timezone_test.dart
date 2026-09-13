import 'package:flutter_test/flutter_test.dart';
import 'package:retro_tv/services/scheduling_timezone.dart';

void main() {
  setUpAll(() async {
    // Network is unavailable in tests; init must fall back to UTC safely.
    await SchedulingClock.init();
    expect(SchedulingClock.isInitialized, isTrue);
  });

  test('falls back to UTC and exposes a valid location', () {
    expect(SchedulingClock.zoneName, 'UTC');
    expect(() => SchedulingClock.location, returnsNormally);
  });

  test('wall-clock -> UTC is identity for UTC zone', () {
    final utc = SchedulingClock.toUtcFromWallClock(
      DateTime(2026, 9, 15, 20, 30),
    );
    expect(utc, DateTime.utc(2026, 9, 15, 20, 30));
  });

  test('wall-clock -> UTC -> wall-clock round-trips exactly', () {
    final naive = DateTime(2026, 9, 15, 8, 5, 0);
    final utc = SchedulingClock.toUtcFromWallClock(naive);
    final back = SchedulingClock.toWallClock(utc);
    expect(back, DateTime(2026, 9, 15, 8, 5, 0));
  });

  test('format outputs a readable local string', () {
    final s = SchedulingClock.format(DateTime.utc(2026, 9, 15, 20, 30));
    expect(s, contains('Sep'));
    expect(s, contains('2026'));
    expect(s, contains('8:30 PM'));
  });
}