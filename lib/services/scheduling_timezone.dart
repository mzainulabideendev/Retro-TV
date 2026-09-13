import 'package:flutter/foundation.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'content_service.dart';

/// Central scheduling timezone strategy for Retro TV.
///
/// THE STRATEGY (documented here and in supabase/migrations/007):
///
///   1. All schedule timestamps are stored in the database as
///      `timestamptz` (i.e. UTC instants). No device-local wall clocks are
///      ever persisted.
///
///   2. The application has ONE configured scheduling timezone, an IANA
///      name stored in `site_settings.scheduling_timezone` (default
///      `'UTC'`). The admin can change it from the Admin → Settings panel.
///
///   3. INPUT boundary: an admin picks a wall-clock date + time; that wall
///      clock is interpreted as a local time *inside the scheduling
///      timezone* and converted to a UTC instant once ([toUtcFromWallClock]).
///
///   4. COMPARISON boundary: eligibility ("has the scheduled time been
///      reached?") always compares UTC instants (server `now()` vs stored
///      `start_time`, both timestamptz). See `get_channel_program_queue`.
///
///   5. OUTPUT boundary: every date/time the admin or viewer sees is
///      formatted from the stored UTC instant *back into the scheduling
///      timezone* ([format]).
///
/// The same timezone is used on both the admin side and the viewer's
/// "Up Next" card, so a program scheduled for
/// "September 15, 2026 — 08:30 PM" starts at exactly that wall clock in
/// the configured timezone — never a day earlier/later from a conversion
/// mistake.
class SchedulingClock {
  static const String settingKey = 'scheduling_timezone';
  static const String defaultZone = 'UTC';

  static bool _initialized = false;
  static bool _loading = false;
  static String _zoneName = defaultZone;
  static tz.Location? _location;

  /// True once [init] has completed at least once (even with a fallback).
  static bool get isInitialized => _initialized;

  /// IANA name of the configured scheduling timezone (e.g. "Asia/Karachi").
  static String get zoneName => _zoneName;

  /// Resolved timezone [Location]; throws if [init] has not completed.
  static tz.Location get location {
    final l = _location;
    if (l == null) throw StateError('SchedulingClock.init() has not completed');
    return l;
  }

  /// Loads the IANA timezone data + the scheduling_timezone site setting.
  ///
  /// Safe to call multiple times. Any failure falls back to UTC so the app
  /// always boots with a consistent, documented timezone.
  static Future<void> init() async {
    if (_initialized && !_loading) return;
    tzdata.initializeTimeZones();
    _loading = true;
    try {
      final settings = await ContentService.getPublicSettings();
      final raw = settings[settingKey];
      final name = _resolveZoneName(raw);
      if (name != null && _zoneExists(name)) {
        _zoneName = name;
        _location = tz.getLocation(name);
      } else {
        _location = tz.getLocation(defaultZone);
        _zoneName = defaultZone;
      }
    } catch (_) {
      _location = tz.getLocation(defaultZone);
      _zoneName = defaultZone;
    } finally {
      _initialized = true;
      _loading = false;
    }
  }

  static String? _resolveZoneName(Object? raw) {
    if (raw is String && raw.trim().isNotEmpty) {
      return raw.trim().replaceAll('"', '');
    }
    if (raw is Map) {
      final v = raw[settingKey];
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    return null;
  }

  static bool _zoneExists(String name) {
    try {
      tz.getLocation(name);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Current instant in the scheduling timezone (for display headers).
  static tz.TZDateTime now() => tz.TZDateTime.now(location);

  /// Current UTC instant used for eligibility comparisons.
  static DateTime nowUtc() => DateTime.now().toUtc();

  /// Converts a "wall clock" date/time (as picked by an admin, with no
  /// attached timezone) into a UTC instant, interpreting it as local time
  /// inside the scheduling timezone. This is the ONLY place local→UTC
  /// conversion happens for schedules.
  static DateTime toUtcFromWallClock(DateTime wallClock) {
    final local = tz.TZDateTime(
      location,
      wallClock.year,
      wallClock.month,
      wallClock.day,
      wallClock.hour,
      wallClock.minute,
      wallClock.second,
      wallClock.millisecond,
    );
    return local.toUtc();
  }

  /// Converts a stored UTC instant into the scheduling timezone, returned
  /// as a naive wall-clock [DateTime] (for display only — never persisted).
  static DateTime toWallClock(DateTime utc) {
    final local = tz.TZDateTime.from(utc.toUtc(), location);
    return DateTime(
      local.year,
      local.month,
      local.day,
      local.hour,
      local.minute,
      local.second,
      local.millisecond,
    );
  }

  /// Human-readable UTC offset of the configured zone, e.g. "UTC+05:00".
  static String offsetLabel() {
    final offset = now().timeZoneOffset;
    final sign = offset.isNegative ? '-' : '+';
    final abs = offset.abs();
    final hh = abs.inHours.toString().padLeft(2, '0');
    final mm = (abs.inMinutes % 60).toString().padLeft(2, '0');
    return 'UTC$sign$hh:$mm';
  }

  /// Test-only override that pins the scheduling timezone without any
  /// network call. Safe to call from widget tests; never used in shipping
  /// code paths.
  @visibleForTesting
  static void debugSetZoneForTesting(String name) {
    tzdata.initializeTimeZones();
    final location = tz.getLocation(name);
    _zoneName = name;
    _location = location;
    _initialized = true;
    _loading = false;
  }

  /// Formats a stored UTC instant as a wall-clock local date/time in the
  /// scheduling timezone, e.g. "Sep 15, 2026 · 08:30 PM (UTC+00:00)".
  static String format(DateTime utc, {bool includeSeconds = false}) {
    final w = toWallClock(utc);
    final h = w.hour;
    final period = h >= 12 ? 'PM' : 'AM';
    final displayHour = h % 12 == 0 ? 12 : h % 12;
    final mm = w.minute.toString().padLeft(2, '0');
    final ss = includeSeconds ? ':${w.second.toString().padLeft(2, '0')}' : '';
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[w.month - 1]} ${w.day.toString().padLeft(2, '0')}, ${w.year} · '
        '$displayHour:$mm$ss $period';
  }

  /// Compact "time only" format for grid cells, e.g. "08:30 PM".
  static String formatTime(DateTime utc) {
    final w = toWallClock(utc);
    final h = w.hour;
    final period = h >= 12 ? 'PM' : 'AM';
    final displayHour = h % 12 == 0 ? 12 : h % 12;
    return '$displayHour:${w.minute.toString().padLeft(2, '0')} $period';
  }
}
