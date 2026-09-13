import '../models/episode.dart';

/// Pure, testable helpers for the continuous channel playback loop.
///
/// The Retro TV channel player runs an infinite loop over a channel's
/// currently ELIGIBLE episodes. "Eligible" = the canonical ordered queue
/// returned by the server's `get_channel_program_queue` function (which
/// already excludes episodes reserved by a future one-off schedule slot,
/// so a scheduled premiere never plays early). This class applies the
/// remaining client-side rules on top of that server list.
class ProgramQueue {
  /// Canonical playback order: sort_order -> playlist_position ->
  /// episode_number -> stable fallback (created_at is the server default).
  ///
  /// The server already returns episodes in this order; this normalizes
  /// any list defensively (e.g. lists loaded through other admin query
  /// paths used by the player fallback).
  static List<Episode> canonicalOrder(List<Episode> episodes) {
    final sorted = [...episodes];
    sorted.sort((a, b) {
      final bySort = a.sortOrder.compareTo(b.sortOrder);
      if (bySort != 0) return bySort;
      final byPos = (a.playlistPosition ?? 1 << 30)
          .compareTo(b.playlistPosition ?? 1 << 30);
      if (byPos != 0) return byPos;
      final byNum = (a.episodeNumber ?? 1 << 30)
          .compareTo(b.episodeNumber ?? 1 << 30);
      if (byNum != 0) return byNum;
      // keep relative order stable for equal entries
      return episodes.indexOf(a).compareTo(episodes.indexOf(b));
    });
    return sorted;
  }

  /// Filters to episodes that can actually be played, excluding any that
  /// the session has temporarily skipped (e.g. embed-blocked videos).
  static List<Episode> playable(
    List<Episode> episodes, {
    Set<String> excludedIds = const {},
  }) {
    return episodes.where((e) {
      final id = e.youtubeVideoId.trim();
      return id.isNotEmpty && !excludedIds.contains(e.id);
    }).toList();
  }

  /// Returns the episode that should play AFTER [currentId] in the loop.
  ///
  /// * Empty queue -> null.
  /// * [currentId] not found (or null) -> the first episode (loop start).
  /// * [currentId] is the LAST episode -> the FIRST episode (wrap-around,
  ///   the "infinite loop" behavior the channels are required to have).
  static Episode? nextAfter(List<Episode> queue, String? currentId) {
    if (queue.isEmpty) return null;
    if (currentId == null) return queue.first;
    final idx = queue.indexWhere((e) => e.id == currentId);
    if (idx < 0) return queue.first;
    return queue[(idx + 1) % queue.length];
  }

  /// Returns the episode that plays BEFORE [currentId] (reverse of
  /// [nextAfter]) for previews; wraps FIRST -> LAST.
  static Episode? previousBefore(List<Episode> queue, String? currentId) {
    if (queue.isEmpty) return null;
    if (currentId == null) return queue.last;
    final idx = queue.indexWhere((e) => e.id == currentId);
    if (idx < 0) return queue.last;
    return queue[(idx - 1 + queue.length) % queue.length];
  }

  /// True when [queue] would loop back to the start after [currentId]
  /// (i.e. the current program is the final episode in the loop).
  static bool loopsToStart(List<Episode> queue, String? currentId) {
    if (queue.isEmpty) return false;
    final idx = queue.indexWhere((e) => e.id == currentId);
    return idx == queue.length - 1;
  }
}