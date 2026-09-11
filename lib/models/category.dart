class Category {
  final String id;
  final String name;
  final String slug;
  final String? description;
  final bool enabled;
  final int sortOrder;

  Category({
    required this.id,
    required this.name,
    required this.slug,
    this.description,
    required this.enabled,
    required this.sortOrder,
  });

  factory Category.fromMap(Map<String, dynamic> map) {
    return Category(
      id: map['id'] as String,
      name: map['name'] as String? ?? '',
      slug: map['slug'] as String? ?? '',
      description: map['description'] as String?,
      enabled: map['enabled'] as bool? ?? true,
      sortOrder: (map['sort_order'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toInsertMap() => {
    'name': name,
    'slug': slug,
    'description': description,
    'enabled': enabled,
    'sort_order': sortOrder,
  };
}
