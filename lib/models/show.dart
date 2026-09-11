class Show {
  final String id;
  final String title;
  final String slug;
  final String? description;
  final String? posterUrl;
  final String? bannerUrl;
  final String? categoryId;
  final String? channelId;
  final int? releaseYear;
  final bool enabled;

  Show({
    required this.id,
    required this.title,
    required this.slug,
    this.description,
    this.posterUrl,
    this.bannerUrl,
    this.categoryId,
    this.channelId,
    this.releaseYear,
    required this.enabled,
  });

  factory Show.fromMap(Map<String, dynamic> map) {
    return Show(
      id: map['id'] as String,
      title: map['title'] as String? ?? 'Untitled Show',
      slug: map['slug'] as String? ?? '',
      description: map['description'] as String?,
      posterUrl: map['poster_url'] as String?,
      bannerUrl: map['banner_url'] as String?,
      categoryId: map['category_id'] as String?,
      channelId: map['channel_id'] as String?,
      releaseYear: (map['release_year'] as num?)?.toInt(),
      enabled: map['enabled'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toInsertMap() => {
    'title': title,
    'slug': slug,
    'description': description,
    'poster_url': posterUrl,
    'banner_url': bannerUrl,
    'category_id': categoryId,
    'channel_id': channelId,
    'release_year': releaseYear,
    'enabled': enabled,
  };
}
