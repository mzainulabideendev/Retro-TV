/// Utilities for validating and normalizing YouTube URLs/IDs.
///
/// Mirrors the server-side `normalize_youtube_id()` Postgres function so
/// the admin UI gives immediate feedback, while the database function
/// remains the authoritative/defensive check (never trust client input).
class YoutubeUtils {
  static final List<RegExp> _patterns = [
    RegExp(r'watch\?v=([A-Za-z0-9_-]{6,})'),
    RegExp(r'youtu\.be/([A-Za-z0-9_-]{6,})'),
    RegExp(r'embed/([A-Za-z0-9_-]{6,})'),
    RegExp(r'shorts/([A-Za-z0-9_-]{6,})'),
  ];

  static final RegExp _bareId = RegExp(r'^[A-Za-z0-9_-]{6,20}$');

  // Playlist IDs: list=, playlists/ID, /playlist?list=, watch?v=...&list=...
  static final RegExp _listParam = RegExp(r'[?&]list=([A-Za-z0-9_-]{10,})');
  static final RegExp _playlistPath = RegExp(r'playlists?/([A-Za-z0-9_-]{10,})');
  // Bare playlist IDs are at least 13 chars (or an explicit PL-prefixed id),
  // so an 11-char VIDEO id is never mistaken for a playlist.
  static final RegExp _barePlaylistId = RegExp(
    r'^(PL[A-Za-z0-9_-]{11,}|[A-Za-z0-9_-]{13,})$',
  );

  /// Extracts and normalizes a YouTube video ID from any supported URL
  /// format, or returns null if the input is invalid/unsupported.
  ///
  /// A playlist URL (`...?list=PL...`) is NOT a valid "single video" input
  /// and returns null here — use [extractPlaylistId] for that.
  static String? extractVideoId(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;
    // A URL that contains a playlist list= parameter is a playlist link,
    // not a single-video link — reject so admins can't paste a playlist
    // where a single video is required (and vice versa).
    if (_listParam.hasMatch(trimmed) || _playlistPath.hasMatch(trimmed)) {
      return null;
    }

    for (final pattern in _patterns) {
      final match = pattern.firstMatch(trimmed);
      if (match != null) {
        return match.group(1);
      }
    }

    if (_bareId.hasMatch(trimmed)) {
      return trimmed;
    }

    return null;
  }

  /// Returns true if [input] is a valid, supported YouTube URL or bare ID.
  static bool isValid(String input) => extractVideoId(input) != null;

  /// Extracts a YouTube playlist ID from a playlist URL or bare playlist ID,
  /// or returns null if the input is not a valid playlist identifier.
  static String? extractPlaylistId(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;

    final listMatch = _listParam.firstMatch(trimmed);
    if (listMatch != null) {
      final id = listMatch.group(1);
      if (id != null && isValidPlaylistId(id)) return id;
      return null;
    }

    final pathMatch = _playlistPath.firstMatch(trimmed);
    if (pathMatch != null) {
      final id = pathMatch.group(1);
      if (id != null && isValidPlaylistId(id)) return id;
      return null;
    }

    if (_barePlaylistId.hasMatch(trimmed)) {
      return trimmed;
    }
    return null;
  }

  /// Returns true if [input] looks like a (syntactically) valid playlist.
  static bool isPlaylistUrl(String input) => extractPlaylistId(input) != null;

  static bool isValidPlaylistId(String id) => _barePlaylistId.hasMatch(id);

  static String thumbnailUrl(String videoId) =>
      'https://img.youtube.com/vi/$videoId/hqdefault.jpg';

  /// Canonical playlist URL for a playlist ID.
  static String playlistUrl(String playlistId) =>
      'https://www.youtube.com/playlist?list=$playlistId';
}
