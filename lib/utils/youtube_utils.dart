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

  /// Extracts and normalizes a YouTube video ID from any supported URL
  /// format, or returns null if the input is invalid/unsupported.
  static String? extractVideoId(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;

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

  static String thumbnailUrl(String videoId) =>
      'https://img.youtube.com/vi/$videoId/hqdefault.jpg';
}
