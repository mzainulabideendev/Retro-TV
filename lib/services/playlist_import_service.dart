import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';
import '../config.dart';
import 'supabase_service.dart';

/// Fetches the videos of a YouTube playlist for the Episodes panel.
///
/// Two sources, in order:
///   1. The `import-youtube-playlist` Supabase Edge Function — the secure
///      path that uses the YouTube Data API SERVER-SIDE (pagination,
///      full item metadata, API key never shipped to the device). The
///      caller's Supabase JWT is forwarded so the function can confirm the
///      user is an admin/content-manager. Works once deployed; the fallback
///      keeps the feature usable in the meantime.
///   2. The keyless YouTube public RSS feed
///      (`https://www.youtube.com/feeds/videos.xml?playlist_id=...`) — no
///      API key required, capped by YouTube at roughly 15-50 entries per
///      playlist. Used automatically when the Edge Function is unreachable.
///
/// The returned items are persisted by `ContentService.importPlaylistVideos`
/// (the DB-side `import_playlist_videos` RPC, which is itself gated to
/// content managers and deduplicates on playlist_id + video_id).
class PlaylistImportService {
  static const int maxItems = 300;

  static Future<List<Map<String, dynamic>>> fetchPlaylist(
    String playlistId,
  ) async {
    // FREE keyless method only — no YouTube API key, no Google setup. The
    // Supabase Edge Function fetches server-side first; if it is unreachable
    // (not deployed, timeout, …) the client tries the keyless RSS / page-scrape
    // fallback below, which YouTube blocks intermittently (hence the retries).
    // Hard ceilings keep the spinner honest: edge fn 8s, fallback 60s max.
    try {
      return await _viaEdgeFunction(playlistId);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('PlaylistImportService: edge fn fallback -> RSS: $e');
      }
      return _viaRss(playlistId).timeout(const Duration(seconds: 60));
    }
  }

  // ---------------------------------------------------------------
  // Primary: Supabase Edge Function (free keyless RSS fetch, server-side)
  // ---------------------------------------------------------------
  // All imports in this app session hit the same Supabase project, so once
  // the Edge Function proves missing (HTTP 404/5xx or auth failure) we skip
  // it for the rest of the session and go straight to the keyless fallback —
  // otherwise every import pays an extra up-to-8s timeout on a dead end.
  static bool _edgeUnavailable = false;

  static Future<List<Map<String, dynamic>>> _viaEdgeFunction(
    String playlistId,
  ) async {
    if (_edgeUnavailable) {
      throw Exception('Edge function unavailable for this session');
    }
    final session = SupabaseService.client.auth.currentSession;
    final base = AppConfig.supabaseUrl;
    final headers = <String, String>{'Accept': 'application/json'};
    if (session != null) {
      // Forward the admin's JWT — the function verifies the user is an
      // admin/content-manager against the DB.
      headers['Authorization'] = 'Bearer ${session.accessToken}';
    }
    final url = Uri.parse(
      '$base/functions/v1/import-youtube-playlist',
    ).replace(queryParameters: {'playlist_id': playlistId});

    final res = await http
        .get(url, headers: headers)
        .timeout(const Duration(seconds: 8));

    if (res.statusCode != 200) {
      if (res.statusCode == 404 || res.statusCode >= 500) {
        _edgeUnavailable = true;
      }
      // Surface the server's (actionable) error message when present.
      var reason = 'Import service unavailable (HTTP ${res.statusCode})';
      try {
        final decoded = jsonDecode(utf8.decode(res.bodyBytes));
        if (decoded is Map && decoded['error'] is String) {
          reason = decoded['error'] as String;
        }
      } catch (_) {
        // ignore parse errors, keep the HTTP status message
      }
      throw Exception(reason);
    }
    final body = utf8.decode(res.bodyBytes);
    final decoded = jsonDecode(body);
    if (decoded is List) {
      return decoded
          .map((e) => Map<String, dynamic>.from((e as Map)))
          .toList()
          .take(maxItems)
          .toList();
    }
    if (decoded is Map && decoded['items'] is List) {
      return (decoded['items'] as List)
          .map((e) => Map<String, dynamic>.from((e as Map)))
          .toList()
          .take(maxItems)
          .toList();
    }
    throw Exception('Unexpected import response');
  }

  // ---------------------------------------------------------------
  // Fallback: keyless YouTube RSS feed, then HTML-page data scraping
  // (no API key required; capped by YouTube at roughly 15-50 entries per
  // playlist via the RSS endpoint).
  // ---------------------------------------------------------------
  // YouTube only serves the XML feed to requests that look like a real
  // desktop browser. A bare Dart/Flutter User-Agent (and datacenter IPs via
  // the CORS relays) gets an HTML consent/bot-check page back instead —
  // the "RSS feed returned HTML instead of XML" failure.
  static const Map<String, String> _browserHeaders = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36',
    'Accept':
        'text/html,application/xhtml+xml,application/xml;q=0.9,'
            'application/atom+xml;q=0.9,*/*;q=0.8',
    'Accept-Language': 'en-US,en;q=0.9',
    'Cookie': 'CONSENT=YES+cb.20240101-00-p0.en+FX+700',
    'Referer': 'https://www.youtube.com/',
  };

  static const List<String> _relayPrefixes = [
    // Own server-side proxy (served by the same Vercel deployment).
    'https://genspark-cf47c8e7-8d21-4afc-84be-8a.vercel.app/api/rss?url=',
    'https://api.allorigins.win/raw?url=',
    'https://api.codetabs.com/v1/proxy?quest=',
  ];

  static Future<List<Map<String, dynamic>>> _viaRss(
    String playlistId,
  ) async {
    // Free keyless source — no API key. YouTube intermittently blocks the
    // feeds endpoint with bogus 404 / HTML responses during rate-limit
    // windows (a known, time-boxed behaviour), so each source below is
    // retried a few times to catch a working window before giving up.
    final errors = <String>[];

    final feedUrl = Uri.parse(
      'https://www.youtube.com/feeds/videos.xml?playlist_id=$playlistId',
    );

    // Pass 1: RSS feed (with retries).
    for (var attempt = 0; attempt < 2; attempt++) {
      if (attempt > 0) await Future<void>.delayed(const Duration(milliseconds: 800));
      try {
        final body = await _fetchText(feedUrl);
        if (_looksLikeXml(body)) {
          final items = _parseRssXml(body);
          if (items.isNotEmpty) return items;
          errors.add('RSS feed had no video entries');
        } else {
          errors.add('RSS feed returned HTML instead of XML');
          // The feeds URL often serves the playlist HTML page instead of real
          // XML — try parsing its embedded `ytInitialData` before moving on.
          try {
            final items = _parseYtInitialData(body, playlistId);
            if (items.isNotEmpty) return items;
          } catch (_) {
            // ignore — the /playlist?list= page fetch below is next
          }
        }
      } catch (e) {
        errors.add(e.toString());
      }
    }

    final pageUrl = Uri.parse(
      'https://www.youtube.com/playlist?list=$playlistId&hl=en',
    );

    // Pass 2: scrape `ytInitialData` from the playlist HTML page (with
    // retries, since YouTube may serve a consent/bot-check page on the first
    // hit).
    for (var attempt = 0; attempt < 2; attempt++) {
      if (attempt > 0) await Future<void>.delayed(const Duration(milliseconds: 800));
      try {
        final body = await _fetchText(pageUrl);
        return _parseYtInitialData(body, playlistId);
      } catch (e) {
        errors.add(e.toString());
      }
    }

    // Deduplicate the accumulated messages for a clean user-facing error.
    final unique = errors.toSet().toList();
    throw Exception(
      'Could not fetch this playlist (${unique.join(' | ')}). '
      'YouTube intermittently blocks the free playlist feed — wait a few '
      'minutes and retry. If it keeps failing the playlist may be private, '
      'deleted, or empty.',
    );
  }

  /// Fetches [url] directly AND through every CORS relay at the same time,
  /// resolving with the FIRST source that returns. On Flutter Web a direct
  /// browser fetch of YouTube is CORS-blocked (`ClientException: Failed to
  /// fetch`), so the relay list is essential there — and the fastest relay
  /// (the /api/rss proxy on the same Vercel deployment) usually wins in
  /// well under a second.
  static Future<String> _fetchText(Uri url) async {
    // The first relay is the Vercel /api/rss proxy on the same deployment. It
    // is gated to admins, so the caller's Supabase JWT is forwarded (the key
    // never leaves the server; the browser only sends its own session token).
    final auth = _sessionAuthHeader();
    // Build candidates explicitly (keeps the first relay authorized).
    final rebuilt = <Future<String>>[
      _fetchDirect(url),
      _fetchDirect(
        Uri.parse('${_relayPrefixes[0]}${Uri.encodeComponent(url.toString())}'),
        extraHeaders: auth,
      ),
      for (var i = 1; i < _relayPrefixes.length; i++)
        _fetchDirect(
          Uri.parse('${_relayPrefixes[i]}${Uri.encodeComponent(url.toString())}'),
        ),
    ];
    final errors = <String>[];
    final completer = Completer<String>();
    var pending = rebuilt.length;
    for (final candidate in rebuilt) {
      candidate.then((value) {
        if (!completer.isCompleted) completer.complete(value);
      }).catchError((Object e) {
        errors.add(e.toString());
        pending--;
        if (pending == 0 && !completer.isCompleted) {
          completer.completeError(
            Exception(
              errors.isEmpty
                  ? 'All source, relay fetches failed'
                  : errors.first,
            ),
          );
        }
      });
    }
    return completer.future;
  }

  /// The logged-in user's Supabase session JWT, or null when signed out.
  /// Forwarded to the admin-gated relay so playlists can be imported.
  static Map<String, String>? _sessionAuthHeader() {
    final session = SupabaseService.client.auth.currentSession;
    if (session == null) return null;
    return {'Authorization': 'Bearer ${session.accessToken}'};
  }

  static Future<String> _fetchDirect(
    Uri url, {
    Map<String, String>? extraHeaders,
  }) async {
    // On web the browser already sends a real browser User-Agent, and
    // setting the forbidden `User-Agent`/`Cookie` headers via fetch() would
    // throw. Native clients need the browser UA so YouTube returns XML
    // instead of an HTML consent/bot-check page.
    final headers = <String, String>{
      ...(kIsWeb ? const <String, String>{} : _browserHeaders),
      ...?extraHeaders,
    };
    final res = await http
        .get(url, headers: headers)
        .timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) {
      throw Exception(
        'Playlist not found or private (HTTP ${res.statusCode}).',
      );
    }
    return utf8.decode(res.bodyBytes);
  }

  static bool _looksLikeXml(String body) {
    final t = body.trimLeft();
    return t.startsWith('<?xml') ||
        t.startsWith('<feed') ||
        t.startsWith('<rss') ||
        body.contains('<entry') ||
        body.contains('<item');
  }

  static List<Map<String, dynamic>> _parseRssXml(String xml) {
    final doc = XmlDocument.parse(xml);
    final items = <Map<String, dynamic>>[];
    final entries = doc.findAllElements('entry').toList();
    for (var index = 0; index < entries.length; index++) {
      final entry = entries[index];
      // YouTube namespaces the important fields (`yt:videoId`,
      // `media:thumbnail`, …). The `xml` package's `getElement(name)` only
      // matches an element when the *exact* qualified name is given, so a
      // plain local-name lookup returns NULL for every namespaced field and
      // the whole feed was being parsed as "empty" — the root cause of the
      // "No videos found. The playlist may be private or empty." error for
      // perfectly public playlists. Every lookup below is therefore
      // namespace-agnostic (matches on the local name only).
      final videoId =
          _firstLocalText(entry, 'videoId') ??
          _firstLocalText(entry, 'videoid') ??
          _videoIdFromIdElement(entry) ??
          _videoIdFromAlternateLink(entry);
      if (videoId == null || videoId.trim().isEmpty) continue;

      final group = _firstLocalElement(entry, 'group') ?? entry;
      final title = _firstLocalText(group, 'title') ?? 'Untitled';
      final description = _firstLocalText(group, 'description');
      final thumbnail =
          _firstLocalElement(group, 'thumbnail')?.getAttribute('url');
      final positionText = _firstLocalText(entry, 'position');

      items.add({
        'youtube_video_id': videoId.trim(),
        'title': title.trim(),
        'description': description?.trim(),
        'thumbnail_url': thumbnail,
        // YouTube's playlist RSS feed doesn't always include a <position>
        // element — fall back to the 1-based order of the feed.
        'playlist_position':
            int.tryParse(positionText ?? '') ?? (index + 1),
      });
    }
    return items;
  }

  /// Extracts the video list from the `ytInitialData` JSON embedded in a
  /// YouTube playlist page. This keeps the keyless import working even when
  /// YouTube stops serving the XML RSS feed and returns its normal HTML page
  /// instead (which happens increasingly often for playlist URLs).
  static List<Map<String, dynamic>> _parseYtInitialData(
    String html,
    String playlistId,
  ) {
    if (html.contains('consent.youtube.com') ||
        html.contains('google.com/sorry') ||
        html.contains('ServiceLogin')) {
      throw Exception(
        'YouTube blocked this request (consent / bot-check page). '
        'Try again later.',
      );
    }
    final jsonText = _extractJsonObject(html, 'ytInitialData');
    if (jsonText == null) {
      throw Exception(
        'Could not read the playlist page. The playlist may be private or '
        'empty.',
      );
    }
    final Map<String, dynamic> data;
    try {
      data = jsonDecode(jsonText) as Map<String, dynamic>;
    } catch (_) {
      throw Exception('Could not read the playlist page data.');
    }

    // Locate the `playlistVideoListRenderer` subtree; only its entries are
    // the actual playlist items (the sidebar holds unrelated "recommended"
    // videos too, which must not be imported).
    Map<String, dynamic>? renderer;
    bool find(Object? o) {
      if (renderer != null) return true;
      if (o is Map) {
        final r = o['playlistVideoListRenderer'];
        if (r is Map) {
          renderer = r.cast<String, dynamic>();
          return true;
        }
        for (final v in o.values) {
          if (find(v)) return true;
        }
      } else if (o is List) {
        for (final v in o) {
          if (find(v)) return true;
        }
      }
      return false;
    }

    if (!find(data) || renderer == null) {
      throw Exception(
        'No videos found. The playlist may be private or empty.',
      );
    }

    final items = <Map<String, dynamic>>[];
    // `renderer` is assigned inside the [find] closure above, so the static
    // checker cannot promote it — but the guard above guarantees it is not
    // null here (otherwise we threw).
    final contents = renderer!['contents'];
    if (contents is List) {
      var position = 1;
      for (final c in contents) {
        if (c is! Map) continue;
        final p = c['playlistVideoRenderer'];
        if (p is! Map) continue; // continuation ("show more") rows are skipped

        final videoId = p['videoId'];
        if (videoId is! String || videoId.trim().isEmpty) continue;

        items.add({
          'youtube_video_id': videoId.trim(),
          'title': _initialDataText(p['title']) ?? 'Untitled',
          'description': null,
          'thumbnail_url': _initialDataThumb(p['thumbnail']),
          'playlist_position': position++,
        });
      }
    }

    if (items.isEmpty) {
      throw Exception(
        'No videos found. The playlist may be private or empty.',
      );
    }
    return items;
  }

  static String? _initialDataText(Object? value) {
    if (value == null) return null;
    if (value is String) {
      final t = value.trim();
      return t.isEmpty ? null : t;
    }
    if (value is Map) {
      final runs = value['runs'];
      if (runs is List && runs.isNotEmpty) {
        final buffer = StringBuffer();
        for (final r in runs) {
          final text = r is Map ? r['text'] : null;
          if (text is String) buffer.write(text);
        }
        final t = buffer.toString().trim();
        if (t.isNotEmpty) return t;
      }
      final simple = value['simpleText'];
      if (simple is String && simple.trim().isNotEmpty) {
        return simple.trim();
      }
    }
    return null;
  }

  static String? _initialDataThumb(Object? value) {
    if (value is Map) {
      final thumbs = value['thumbnails'];
      if (thumbs is List && thumbs.isNotEmpty) {
        final last = thumbs.last;
        if (last is Map) {
          final url = last['url'];
          if (url is String && url.isNotEmpty) {
            return url.startsWith('//') ? 'https:$url' : url;
          }
        }
      }
    }
    return null;
  }

  /// Extracts the first JSON object assigned to `var <name> =` in a <script>
  /// blurb. Brace-matching is used instead of regex so titles containing
  /// brackets, quotes or semicolons can never truncate the payload.
  static String? _extractJsonObject(String html, String name) {
    final marker = 'var $name =';
    final startIndex = html.indexOf(marker);
    if (startIndex < 0) return null;
    final start = html.indexOf('{', startIndex + marker.length);
    if (start < 0) return null;

    var depth = 0;
    var inString = false;
    var escaped = false;
    for (var i = start; i < html.length; i++) {
      final ch = html[i];
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (ch == r'\') {
          escaped = true;
        } else if (ch == '"') {
          inString = false;
        }
        continue;
      }
      if (ch == '"') {
        inString = true;
      } else if (ch == '{') {
        depth++;
      } else if (ch == '}') {
        depth--;
        if (depth == 0) return html.substring(start, i + 1);
      }
    }
    return null;
  }

  /// First descendant element whose LOCAL name matches [local], regardless
  /// of any XML namespace prefix (e.g. `yt:videoId` → local name `videoId`).
  static XmlElement? _firstLocalElement(XmlElement root, String local) {
    for (final node in root.descendants) {
      if (node is XmlElement && node.name.local == local) return node;
    }
    return null;
  }

  static String? _firstLocalText(XmlElement root, String local) {
    final text = _firstLocalElement(root, local)?.innerText.trim();
    return (text == null || text.isEmpty) ? null : text;
  }

  /// Extracts the video id from the feed's `<id>` element, which looks like
  /// `yt:video:0VH1Lim8gL8` when no `yt:videoId` element is present.
  static String? _videoIdFromIdElement(XmlElement entry) {
    final idText = _firstLocalText(entry, 'id');
    if (idText == null) return null;
    final match = RegExp(r'yt:video:([A-Za-z0-9_-]{6,})').firstMatch(idText);
    return match?.group(1);
  }

  /// Last resort: pull the video id out of the alternate `<link>` href
  /// (`https://www.youtube.com/watch?v=0VH1Lim8gL8`).
  static String? _videoIdFromAlternateLink(XmlElement entry) {
    for (final node in entry.descendants) {
      if (node is! XmlElement || node.name.local != 'link') continue;
      final href = node.getAttribute('href');
      if (href == null) continue;
      final match = RegExp(r'[?&]v=([A-Za-z0-9_-]{6,})').firstMatch(href);
      if (match != null) return match.group(1);
    }
    return null;
  }
}