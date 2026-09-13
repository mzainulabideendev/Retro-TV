import 'package:flutter_test/flutter_test.dart';
import 'package:retro_tv/utils/youtube_utils.dart';

void main() {
  group('YoutubeUtils.extractVideoId', () {
    test('extracts from watch URLs', () {
      expect(
        YoutubeUtils.extractVideoId('https://www.youtube.com/watch?v=dQw4w9WgXcQ'),
        'dQw4w9WgXcQ',
      );
    });

    test('extracts from youtu.be short links', () {
      expect(
        YoutubeUtils.extractVideoId('https://youtu.be/dQw4w9WgXcQ?t=1'),
        'dQw4w9WgXcQ',
      );
    });

    test('extracts from embed and shorts', () {
      expect(
        YoutubeUtils.extractVideoId('https://www.youtube.com/embed/dQw4w9WgXcQ'),
        'dQw4w9WgXcQ',
      );
      expect(
        YoutubeUtils.extractVideoId('https://youtube.com/shorts/dQw4w9WgXcQ'),
        'dQw4w9WgXcQ',
      );
    });

    test('accepts bare IDs', () {
      expect(YoutubeUtils.extractVideoId('dQw4w9WgXcQ'), 'dQw4w9WgXcQ');
    });

    test('rejects playlist URLs (they are not single videos)', () {
      expect(
        YoutubeUtils.extractVideoId('https://www.youtube.com/playlist?list=PL123456789012345678'),
        isNull,
      );
      expect(
        YoutubeUtils.extractVideoId('https://www.youtube.com/watch?v=dQw4w9WgXcQ&list=PL123456789012'),
        isNull,
      );
    });

    test('rejects garbage', () {
      expect(YoutubeUtils.extractVideoId('not a youtube link'), isNull);
      expect(YoutubeUtils.extractVideoId(''), isNull);
    });
  });

  group('YoutubeUtils.extractPlaylistId', () {
    test('extracts from playlist URLs', () {
      expect(
        YoutubeUtils.extractPlaylistId('https://www.youtube.com/playlist?list=PL123456789012345678'),
        'PL123456789012345678',
      );
    });

    test('extracts list= param from watch URLs', () {
      expect(
        YoutubeUtils.extractPlaylistId('https://www.youtube.com/watch?v=dQw4w9WgXcQ&list=PL123456789012'),
        'PL123456789012',
      );
    });

    test('extracts bare playlist ids', () {
      expect(YoutubeUtils.extractPlaylistId('PL123456789012'), 'PL123456789012');
      expect(
        YoutubeUtils.extractPlaylistId('MO1234567890123ABC'),
        'MO1234567890123ABC',
      );
    });

    test('rejects non-playlist inputs', () {
      expect(YoutubeUtils.extractPlaylistId('dQw4w9WgXcQ'), isNull);
      expect(YoutubeUtils.extractPlaylistId(''), isNull);
    });
  });
}