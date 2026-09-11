class ScheduleEntry {
  final String id;
  final String channelId;
  final String episodeId;
  final DateTime startTime;
  final DateTime? endTime;
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
      startTime: DateTime.parse(map['start_time'] as String),
      endTime: map['end_time'] != null
          ? DateTime.tryParse(map['end_time'] as String)
          : null,
      dayOfWeek: (map['day_of_week'] as num?)?.toInt(),
      priority: (map['priority'] as num?)?.toInt() ?? 0,
      enabled: map['enabled'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toInsertMap() => {
    'channel_id': channelId,
    'episode_id': episodeId,
    'start_time': startTime.toIso8601String(),
    'end_time': endTime?.toIso8601String(),
    'day_of_week': dayOfWeek,
    'priority': priority,
    'enabled': enabled,
  };
}
