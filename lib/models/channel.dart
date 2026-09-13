class Channel {
  final String id;
  final int channelNumber;
  final String name;
  final String slug;
  final String? description;
  final String? logoUrl;
  final String? bannerUrl;
  final String? categoryId;
  final String channelType;
  final String? defaultEpisodeId;
  final bool enabled;
  final bool featured;
  final bool isKidsFriendly;
  final int sortOrder;

  /// Per-channel loop override (NULL = follow the global site setting):
  /// true loops this channel's episodes forever, false stops after the
  /// final episode instead of wrapping back to episode 1.
  final bool? loopPlayback;

  Channel({
    required this.id,
    required this.channelNumber,
    required this.name,
    required this.slug,
    this.description,
    this.logoUrl,
    this.bannerUrl,
    this.categoryId,
    required this.channelType,
    this.defaultEpisodeId,
    required this.enabled,
    required this.featured,
    required this.isKidsFriendly,
    required this.sortOrder,
    this.loopPlayback,
  });

  factory Channel.fromMap(Map<String, dynamic> map) {
    return Channel(
      id: map['id'] as String,
      channelNumber: (map['channel_number'] as num?)?.toInt() ?? 0,
      name: map['name'] as String? ?? 'Untitled Channel',
      slug: map['slug'] as String? ?? '',
      description: map['description'] as String?,
      logoUrl: map['logo_url'] as String?,
      bannerUrl: map['banner_url'] as String?,
      categoryId: map['category_id'] as String?,
      channelType: map['channel_type'] as String? ?? 'general',
      defaultEpisodeId: map['default_episode_id'] as String?,
      enabled: map['enabled'] as bool? ?? true,
      featured: map['featured'] as bool? ?? false,
      isKidsFriendly: map['is_kids_friendly'] as bool? ?? false,
      sortOrder: (map['sort_order'] as num?)?.toInt() ?? 0,
      loopPlayback: map['loop_playback'] as bool?,
    );
  }

  Map<String, dynamic> toInsertMap() => {
    'channel_number': channelNumber,
    'name': name,
    'slug': slug,
    'description': description,
    'logo_url': logoUrl,
    'banner_url': bannerUrl,
    'category_id': categoryId,
    'channel_type': channelType,
    'default_episode_id': defaultEpisodeId,
    'enabled': enabled,
    'featured': featured,
    'is_kids_friendly': isKidsFriendly,
    'sort_order': sortOrder,
    'loop_playback': loopPlayback,
  };

  Channel copyWith({
    int? channelNumber,
    String? name,
    String? description,
    String? logoUrl,
    String? bannerUrl,
    String? categoryId,
    String? channelType,
    String? defaultEpisodeId,
    bool? enabled,
    bool? featured,
    bool? isKidsFriendly,
    int? sortOrder,
    bool? loopPlayback,
  }) {
    return Channel(
      id: id,
      channelNumber: channelNumber ?? this.channelNumber,
      name: name ?? this.name,
      slug: slug,
      description: description ?? this.description,
      logoUrl: logoUrl ?? this.logoUrl,
      bannerUrl: bannerUrl ?? this.bannerUrl,
      categoryId: categoryId ?? this.categoryId,
      channelType: channelType ?? this.channelType,
      defaultEpisodeId: defaultEpisodeId ?? this.defaultEpisodeId,
      enabled: enabled ?? this.enabled,
      featured: featured ?? this.featured,
      isKidsFriendly: isKidsFriendly ?? this.isKidsFriendly,
      sortOrder: sortOrder ?? this.sortOrder,
      loopPlayback: loopPlayback ?? this.loopPlayback,
    );
  }
}
