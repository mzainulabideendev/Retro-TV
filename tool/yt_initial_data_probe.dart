// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

/// Validates the exact parsing logic the app's keyless fallback uses against
/// the LIVE YouTube page, so we can confirm the `ytInitialData` scrape works
/// for a fully public playlist on the day YouTube stops serving XML to our
/// CORS relays. Run with:
///   dart run tool/yt_initial_data_probe.dart PLDfmn4VJL6ZCEfUfZbOCuCcc-8LcjrM6s
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

String? textOf(Object? value) {
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

String? thumbOf(Object? value) {
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

void main(List<String> args) async {
  final playlistId = args.first;
  final client = HttpClient();
  final req = await client.getUrl(
    Uri.parse('https://www.youtube.com/playlist?list=$playlistId'),
  );
  req.headers.set('User-Agent', 'Mozilla/5.0');
  final res = await req.close();
  final body = await res.transform(utf8.decoder).join();
  stdout.writeln('http=${res.statusCode} len=${body.length}');

  final jsonText = extractJsonObject(body, 'ytInitialData');
  if (jsonText == null) {
    stdout.writeln('NO ytInitialData');
    return;
  }
  stdout.writeln('jsonText len=${jsonText.length}');

  final Map<String, dynamic> data;
  try {
    data = jsonDecode(jsonText) as Map<String, dynamic>;
  } catch (e) {
    stdout.writeln('jsonDecode FAILED: $e');
    return;
  }
  stdout.writeln('jsonDecode OK');

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
    stdout.writeln('NO playlistVideoListRenderer');
    return;
  }
  stdout.writeln('renderer keys=${renderer!.keys.join(',')}');

  final contents = renderer!['contents'];
  stdout.writeln('contents type=${contents.runtimeType}');
  if (contents is List) {
    stdout.writeln('contents count=${contents.length}');
    var shown = 0;
    for (final c in contents) {
      if (c is! Map) continue;
      final p = c['playlistVideoRenderer'];
      if (p is! Map) {
        stdout.writeln('  OTHER renderer: ${c.keys.join(',')}');
        continue;
      }
      final videoId = p['videoId'];
      stdout.writeln(
        '  vid=$videoId pos=${textOf(p['index'])} '
        'title="${textOf(p['title'])}" thumb=${thumbOf(p['thumbnail'])}',
      );
      if (++shown >= 4) break;
    }
    stdout.writeln('shown=$shown');
  }
}
