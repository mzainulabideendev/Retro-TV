import 'package:flutter_test/flutter_test.dart';
import 'package:retro_tv/models/episode.dart';
import 'package:retro_tv/utils/program_queue.dart';

Episode makeEpisode({
  String id = 'e1',
  int sortOrder = 0,
  int? playlistPosition,
  int? episodeNumber,
  String videoId = 'dQw4w9WgXcQ',
}) {
  return Episode(
    id: id,
    seasonNumber: 1,
    title: 'Episode $id',
    youtubeVideoId: videoId,
    status: 'published',
    enabled: true,
    sortOrder: sortOrder,
    youtubePlaylistId:
        playlistPosition != null ? 'PL123456789012' : null,
    playlistPosition: playlistPosition,
    episodeNumber: episodeNumber,
  );
}

void main() {
  group('ProgramQueue.nextAfter (continuous loop)', () {
    final queue = [
      makeEpisode(id: 'a', sortOrder: 1),
      makeEpisode(id: 'b', sortOrder: 2),
      makeEpisode(id: 'c', sortOrder: 3),
    ];

    test('advances one at a time', () {
      expect(ProgramQueue.nextAfter(queue, 'a')?.id, 'b');
      expect(ProgramQueue.nextAfter(queue, 'b')?.id, 'c');
    });

    test('wraps last -> first (infinite loop)', () {
      expect(ProgramQueue.nextAfter(queue, 'c')?.id, 'a');
    });

    test('unknown/current-null starts at the top', () {
      expect(ProgramQueue.nextAfter(queue, null)?.id, 'a');
      expect(ProgramQueue.nextAfter(queue, 'missing')?.id, 'a');
    });

    test('empty queue returns null', () {
      expect(ProgramQueue.nextAfter([], 'a'), isNull);
    });

    test('previousBefore wraps first -> last', () {
      expect(ProgramQueue.previousBefore(queue, 'a')?.id, 'c');
      expect(ProgramQueue.previousBefore(queue, 'c')?.id, 'b');
    });
  });

  group('ProgramQueue.playable', () {
    test('filters empty video ids and excluded ids', () {
      final list = [
        makeEpisode(id: 'ok'),
        makeEpisode(id: 'empty', videoId: '   '),
      ];
      final playable = ProgramQueue.playable(list, excludedIds: {'ok'});
      expect(playable, isEmpty);
    });
  });

  group('ProgramQueue.canonicalOrder', () {
    test('orders by sort_order then playlist position', () {
      final list = [
        makeEpisode(id: 'pos2', sortOrder: 0, playlistPosition: 2),
        makeEpisode(id: 'pos1', sortOrder: 0, playlistPosition: 1),
        makeEpisode(id: 'manual', sortOrder: 5),
      ];
      final ordered = ProgramQueue.canonicalOrder(list);
      expect(ordered.map((e) => e.id).toList(), ['pos1', 'pos2', 'manual']);
    });
  });
}