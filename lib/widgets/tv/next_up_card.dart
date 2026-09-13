import 'package:flutter/material.dart';

import '../../models/up_next.dart';
import '../../services/scheduling_timezone.dart';
import '../../utils/youtube_utils.dart';

const _weekdays = [
  'Sunday',
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
];

/// The "Up Next / announcement" card shown on the TV home screen.
///
/// It surfaces the next program the viewer should expect in one of two
/// forms:
///   1. ANNOUNCEMENT — the channel's soonest upcoming *scheduled* program
///      (one-off or weekly recurrence) with its exact air date/time and
///      channel number (from `get_next_scheduled_program`).
///   2. LOOP — the next episode in the channel's continuous playback loop
///      (wraps last -> first), still carrying its precise air time when it
///      has an explicit schedule entry.
///
/// Every date/time is rendered through [SchedulingClock] — the configured
/// scheduling timezone — so the viewer sees the same wall-clock time the
/// admin scheduled.
class NextUpCard extends StatelessWidget {
  final UpNext? upNext;
  final Map<String, dynamic>? announcement;
  final Color accentColor;

  const NextUpCard({
    super.key,
    this.upNext,
    this.announcement,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final upcoming = _UpcomingView.from(
      upNext: upNext,
      announcement: announcement,
    );
    if (upcoming == null) return const SizedBox.shrink();

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 640),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFF14141A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: accentColor.withValues(alpha: 0.45)),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 112,
                height: 64,
                child: upcoming.thumbnailUrl.isNotEmpty
                    ? Image.network(
                        upcoming.thumbnailUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            _thumbFallback(accentColor),
                      )
                    : _thumbFallback(accentColor),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.play_circle_outline,
                        size: 13,
                        color: accentColor,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          upcoming.isScheduled
                              ? 'UP NEXT — SCHEDULED'
                              : 'UP NEXT',
                          style: TextStyle(
                            color: accentColor,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.1,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    upcoming.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    upcoming.subtitle,
                    style: const TextStyle(color: Colors.white54, fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            if (upcoming.showTime) ...[
              // The time column is flexible: its contents (air time + date/
              // zone label) must never be able to push the card beyond its
              // available width on narrow displays or large text scales.
              // Loose fit lets the column shrink and wrap instead of
              // overflowing the Row to the right.
              Flexible(
                fit: FlexFit.loose,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      upcoming.timeBig,
                      style: TextStyle(
                        color: accentColor,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      upcoming.dateSmall,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 10,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _thumbFallback(Color accentColor) {
    return Container(
      color: const Color(0xFF0E0E14),
      alignment: Alignment.center,
      child: Icon(
        Icons.live_tv,
        color: accentColor.withValues(alpha: 0.6),
        size: 22,
      ),
    );
  }
}

class _UpcomingView {
  final String title;
  final String thumbnailUrl;
  final String subtitle;
  final bool isScheduled;
  final bool showTime;
  final String timeBig;
  final String dateSmall;

  _UpcomingView({
    required this.title,
    required this.thumbnailUrl,
    required this.subtitle,
    required this.isScheduled,
    required this.showTime,
    required this.timeBig,
    required this.dateSmall,
  });

  static _UpcomingView? from({
    UpNext? upNext,
    Map<String, dynamic>? announcement,
  }) {
    // 1) Explicitly scheduled announcement wins (exact time/date + channel).
    if (announcement != null) {
      final title = announcement['title'] as String? ?? 'Untitled episode';
      final videoId = announcement['youtube_video_id'] as String? ?? '';
      var thumb = announcement['thumbnail_url'] as String? ?? '';
      if (thumb.isEmpty && videoId.isNotEmpty) {
        thumb = YoutubeUtils.thumbnailUrl(videoId);
      }
      final channelNumber = announcement['channel_number'] as int? ?? 0;
      final channelName = announcement['channel_name'] as String? ?? '';
      final recurring = announcement['recurring'] as bool? ?? false;
      final dayOfWeek = (announcement['day_of_week'] as num?)?.toInt();
      final start = announcement['start_time'] as DateTime?;
      return _fromSchedule(
        title: title,
        thumbnailUrl: thumb,
        channelLabel: '$channelNumber · $channelName',
        start: start,
        recurring: recurring,
        dayOfWeek: dayOfWeek,
      );
    }

    // 2) Loop: the very next episode that will play automatically.
    if (upNext != null) {
      final ep = upNext.episode;
      var thumb = ep.thumbnailUrl ?? '';
      if (thumb.isEmpty) thumb = YoutubeUtils.thumbnailUrl(ep.youtubeVideoId);
      final schedule = upNext.schedule;
      return _fromSchedule(
        title: ep.title,
        thumbnailUrl: thumb,
        channelLabel: 'Plays next on this channel',
        start: schedule?.startTime,
        recurring: schedule?.dayOfWeek != null,
        dayOfWeek: schedule?.dayOfWeek,
      );
    }

    return null;
  }

  static _UpcomingView _fromSchedule({
    required String title,
    required String thumbnailUrl,
    required String channelLabel,
    DateTime? start,
    required bool recurring,
    int? dayOfWeek,
  }) {
    final utc = start;
    if (utc == null) {
      return _UpcomingView(
        title: title,
        thumbnailUrl: thumbnailUrl,
        subtitle: channelLabel,
        isScheduled: false,
        showTime: false,
        timeBig: '',
        dateSmall: 'Plays after this program ends',
      );
    }
    final wall = SchedulingClock.toWallClock(utc);
    final period = wall.hour >= 12 ? 'PM' : 'AM';
    final hour = wall.hour % 12 == 0 ? 12 : wall.hour % 12;
    final mm = wall.minute.toString().padLeft(2, '0');
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
    final weekdayName = dayOfWeek != null && dayOfWeek >= 0 && dayOfWeek <= 6
        ? _weekdays[dayOfWeek]
        : null;
    return _UpcomingView(
      title: title,
      thumbnailUrl: thumbnailUrl,
      subtitle: recurring
          ? '$channelLabel · every ${weekdayName ?? 'week'}'
          : channelLabel,
      isScheduled: true,
      showTime: true,
      timeBig: '$hour:$mm $period',
      dateSmall: recurring
          ? '${weekdayName ?? 'Weekly'} · ${SchedulingClock.zoneName}'
          : '${months[wall.month - 1]} ${wall.day.toString().padLeft(2, '0')}, ${wall.year}',
    );
  }
}
