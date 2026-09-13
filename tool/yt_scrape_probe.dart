// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

String? extractJsonObject(String html, String name) {
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

String? initialDataText(Object? value) {
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
    if (simple is String && simple.trim().isNotEmpty) return simple.trim();
  }
  return null;
}

String? initialDataThumb(Object? value) {
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

List<Map<String, dynamic>> parseYtInitialData(String html, String playlistId) {
  final jsonText = extractJsonObject(html, 'ytInitialData');
  if (jsonText == null) throw Exception('no ytInitialData marker');
  print('jsonText length: ${jsonText.length}');
  final Map<String, dynamic> data;
  try {
    data = jsonDecode(jsonText) as Map<String, dynamic>;
  } catch (e) {
    throw Exception('jsonDecode failed: $e');
  }

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
    throw Exception('no playlistVideoListRenderer');
  }
  final r0 = renderer!;

  final items = <Map<String, dynamic>>[];
  final contents = r0['contents'];
  if (contents is List) {
    var position = 1;
    for (final c in contents) {
      if (c is! Map) continue;
      final p = c['playlistVideoRenderer'];
      if (p is! Map) continue;
      final videoId = p['videoId'];
      if (videoId is! String || videoId.trim().isEmpty) continue;
      items.add({
        'youtube_video_id': videoId.trim(),
        'title': initialDataText(p['title']) ?? 'Untitled',
        'description': null,
        'thumbnail_url': initialDataThumb(p['thumbnail']),
        'playlist_position': position++,
      });
    }
  }
  return items;
}

Future<void> main() async {
  final playlistId = Platform.environment['PLAYLIST_ID'] ?? 'PLDfmn4VJL6ZCEfUfZbOCuCcc-8LcjrM6s';
  final client = HttpClient();
  final req = await client.getUrl(Uri.parse('https://www.youtube.com/playlist?list=$playlistId'));
  req.headers.set('User-Agent', 'Mozilla/5.0');
  final res = await req.close();
  final body = await res.transform(utf8.decoder).join();
  print('status ${res.statusCode} body length ${body.length}');
  print('looksLikeXml: ${body.trimLeft().startsWith('<?xml') || body.contains('<entry')}');
  final items = parseYtInitialData(body, playlistId);
  print('parsed items: ${items.length}');
  for (final i in items.take(3)) {
    print('  #${i['playlist_position']} ${i['youtube_video_id']} "${i['title']}" thumb=${i['thumbnail_url']}');
  }
  client.close(force: true);
}