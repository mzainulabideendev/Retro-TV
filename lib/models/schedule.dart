import '../services/scheduling_timezone.dart';

/// A single program slot on a channel.
///
/// TIMEZONE RULE: [startTime] / [endTime] are ALWAYS UTC instants
/// (matching the `timestamptz` database columns). The class normalizes
/// everything read from PostgREST to UTC via [toUtc] and provides
/// wall-clock display helpers that render in the configured
/// [SchedulingClock] timezone — the exact same zone the admin scheduled in.
class ScheduleEntry {
  final String id;
  final String channelId;
  final String episodeId;
  final DateTime startTime; // UTC
  final DateTime? endTime; // UTC
  final int? dayOfWeek; // 0=Sunday..6=Saturday, null=one-off dated
  final int priority;
  final bool enabled;

  ScheduleEntry({
    required this.id,
    required this.channelId,
    required this.episodeId,
    required this.startTime,
    this.endTime,
    this.dayOfWeek,
    required this.priority,
    required this.enabled,
  });

  factory ScheduleEntry.fromMap(Map<String, dynamic> map) {
    return ScheduleEntry(
      id: map['id'] as String,
      channelId: map['channel_id'] as String,
      episodeId: map['episode_id'] as String,
      startTime: _parseUtc(map['start_time']),
      endTime: map['end_time'] != null ? _parseUtc(map['end_time']) : null,
      dayOfWeek: (map['day_of_week'] as num?)?.toInt(),
      priority: (map['priority'] as num?)?.toInt() ?? 0,
      enabled: map['enabled'] as bool? ?? true,
    );
  }

  /// PostgREST returns timestamptz either as `...Z`, `...+00:00` or
  /// (rarely) with no suffix. We always normalize to a UTC instant so the
  /// rest of the app can rely on pure-UTC comparisons.
  static DateTime _parseUtc(Object? raw) {
    if (raw is String) {
      final parsed = DateTime.tryParse(raw);
      if (parsed != null) return parsed.toUtc();
    }
    return DateTime.fromMillisecondsSinceEpoch(0).toUtc();
  }

  Map<String, dynamic> toInsertMap() => {
    'channel_id': channelId,
    'episode_id': episodeId,
    'start_time': startTime.toUtc().toIso8601String(),
    'end_time': endTime?.toUtc().toIso8601String(),
    'day_of_week': dayOfWeek,
    'priority': priority,
    'enabled': enabled,
  };

  /// Lifecycle status of the slot relative to the current UTC instant.
  ScheduleStatus statusAt(DateTime utcNow) {
    if (!enabled) return ScheduleStatus.cancelled;
    if (dayOfWeek != null) return ScheduleStatus.recurring;
    if (!startTime.isAfter(utcNow)) {
      final end = endTime;
      if (end == null || end.isAfter(utcNow)) return ScheduleStatus.live;
      return ScheduleStatus.completed;
    }
    return ScheduleStatus.scheduled;
  }

  /// Wall-clock start/end rendered in the configured scheduling timezone.
  ///
  /// One-off entries show the full date + time; recurring weekly entries
  /// show the weekday + time (the stored start_time is a canonical UTC
  /// anchor whose *time-of-day* is the real air time in the scheduling
  /// zone after round-tripping through [SchedulingClock.toWallClock]).
  String get displayStart {
    if (dayOfWeek != null) {
      final day = dayOfWeek!;
      final safe = day >= 0 && day <= 6 ? _weekdayShort[day] : '?';
      return 'Every $safe · ${_fmtTime(startTime)}';
    }
    return _fmtFull(startTime);
  }

  String get displayEnd {
    if (endTime == null) return '—';
    if (dayOfWeek != null) return _fmtTime(endTime!);
    return _fmtFull(endTime!);
  }

  static const _weekdayShort = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

  static String _fmtTime(DateTime utc) {
    final w = SchedulingClock.toWallClock(utc);
    final h = w.hour;
    final period = h >= 12 ? 'PM' : 'AM';
    final hour = h % 12 == 0 ? 12 : h % 12;
    return '$hour:${w.minute.toString().padLeft(2, '0')} $period';
  }

  static String _fmtFull(DateTime utc) {
    final w = SchedulingClock.toWallClock(utc);
    final h = w.hour;
    final period = h >= 12 ? 'PM' : 'AM';
    final hour = h % 12 == 0 ? 12 : h % 12;
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[w.month - 1]} ${w.day.toString().padLeft(2, '0')}, ${w.year} '
        '$hour:${w.minute.toString().padLeft(2, '0')} $period';
  }
}

enum ScheduleStatus {
  scheduled, // airing in the future
  live, // currently airing
  completed, // finished
  cancelled, // disabled
  recurring, // weekly template
}

ScheduleStatus scheduleStatusFromString(String? s) {
  switch (s) {
    case 'scheduled':
      return ScheduleStatus.scheduled;
    case 'live':
      return ScheduleStatus.live;
    case 'completed':
      return ScheduleStatus.completed;
    case 'cancelled':
      return ScheduleStatus.cancelled;
    default:
      return ScheduleStatus.recurring;
  }
}

String scheduleStatusLabel(ScheduleStatus s) {
  switch (s) {
    case ScheduleStatus.scheduled:
      return 'Scheduled';
    case ScheduleStatus.live:
      return 'Live / Airing';
    case ScheduleStatus.completed:
      return 'Completed';
    case ScheduleStatus.cancelled:
      return 'Cancelled';
    case ScheduleStatus.recurring:
      return 'Recurring';
  }
}