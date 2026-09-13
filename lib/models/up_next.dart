import 'episode.dart';
import 'schedule.dart';

/// Describes the program the viewer should expect next — either the next
/// entry in the channel's continuous loop, or an explicitly scheduled
/// program with an exact air date/time (the "Up Next" announcement card).
class UpNext {
  final Episode episode;
  final ScheduleEntry? schedule;

  UpNext({required this.episode, this.schedule});

  /// True when the next program is driven by an explicit schedule entry
  /// (one-off or recurring) rather than just the continuous loop.
  bool get isScheduled => schedule != null;

  DateTime? get startUtc => schedule?.startTime;
  DateTime? get endUtc => schedule?.endTime;
  int? get dayOfWeek => schedule?.dayOfWeek;

  String? get channelId => episode.channelId;
}