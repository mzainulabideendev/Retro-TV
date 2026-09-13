/// Outcome of importing a single video from a YouTube playlist.
class PlaylistImportResult {
  final String? episodeId;
  final String? youtubeVideoId;
  final String? title;
  final bool inserted;
  final String? error;

  const PlaylistImportResult({
    this.episodeId,
    this.youtubeVideoId,
    this.title,
    required this.inserted,
    this.error,
  });

  factory PlaylistImportResult.fromMap(Map<String, dynamic> map) {
    return PlaylistImportResult(
      episodeId: map['episode_id'] as String?,
      youtubeVideoId: map['youtube_video_id'] as String?,
      title: map['title'] as String?,
      inserted: map['inserted'] as bool? ?? false,
      error: map['error'] as String?,
    );
  }

  bool get ok => episodeId != null && error == null;
}