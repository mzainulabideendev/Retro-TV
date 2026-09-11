class Episode {
  final String id;
  final String? showId;
  final String? channelId;
  final int seasonNumber;
  final int? episodeNumber;
  final String title;
  final String? description;
  final String youtubeVideoId;
  final String? youtubeUrl;
  final String? thumbnailUrl;
  final int? durationSeconds;
  final int? releaseYear;
  final DateTime? airDate;
  final String? categoryId;
  final String status; // draft | published | disabled
  final bool enabled;
  final int sortOrder;

  Episode({
    required this.id,
    this.showId,
    this.channelId,
    required this.seasonNumber,
    this.episodeNumber,
    required this.title,
    this.description,
    required this.youtubeVideoId,
    this.youtubeUrl,
    this.thumbnailUrl,
    this.durationSeconds,
    this.releaseYear,
    this.airDate,
    this.categoryId,
    required this.status,
    required this.enabled,
    required this.sortOrder,
  });

  factory Episode.fromMap(Map<String, dynamic> map) {
    return Episode(
      id: map['id'] as String,
      showId: map['show_id'] as String?,
      channelId: map['channel_id'] as String?,
      seasonNumber: (map['season_number'] as num?)?.toInt() ?? 1,
      episodeNumber: (map['episode_number'] as num?)?.toInt(),
      title: map['title'] as String? ?? 'Untitled Episode',
      description: map['description'] as String?,
      youtubeVideoId: map['youtube_video_id'] as String? ?? '',
      youtubeUrl: map['youtube_url'] as String?,
      thumbnailUrl: map['thumbnail_url'] as String?,
      durationSeconds: (map['duration_seconds'] as num?)?.toInt(),
      releaseYear: (map['release_year'] as num?)?.toInt(),
      airDate: map['air_date'] != null
          ? DateTime.tryParse(map['air_date'] as String)
          : null,
      categoryId: map['category_id'] as String?,
      status: map['status'] as String? ?? 'draft',
      enabled: map['enabled'] as bool? ?? true,
      sortOrder: (map['sort_order'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toInsertMap() => {
    'show_id': showId,
    'channel_id': channelId,
    'season_number': seasonNumber,
    'episode_number': episodeNumber,
    'title': title,
    'description': description,
    'youtube_video_id': youtubeVideoId,
    'youtube_url': youtubeUrl,
    'thumbnail_url': thumbnailUrl,
    'duration_seconds': durationSeconds,
    'release_year': releaseYear,
    'air_date': airDate?.toIso8601String(),
    'category_id': categoryId,
    'status': status,
    'enabled': enabled,
    'sort_order': sortOrder,
  };
}
