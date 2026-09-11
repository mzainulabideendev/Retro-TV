enum AppRole { superAdmin, admin, editor, viewer }

AppRole roleFromString(String? s) {
  switch (s) {
    case 'super_admin':
      return AppRole.superAdmin;
    case 'admin':
      return AppRole.admin;
    case 'editor':
      return AppRole.editor;
    default:
      return AppRole.viewer;
  }
}

String roleToString(AppRole r) {
  switch (r) {
    case AppRole.superAdmin:
      return 'super_admin';
    case AppRole.admin:
      return 'admin';
    case AppRole.editor:
      return 'editor';
    case AppRole.viewer:
      return 'viewer';
  }
}

class Profile {
  final String id;
  final String email;
  final String? displayName;
  final AppRole role;
  final bool isActive;

  Profile({
    required this.id,
    required this.email,
    this.displayName,
    required this.role,
    required this.isActive,
  });

  factory Profile.fromMap(Map<String, dynamic> map) {
    return Profile(
      id: map['id'] as String,
      email: map['email'] as String? ?? '',
      displayName: map['display_name'] as String?,
      role: roleFromString(map['role'] as String?),
      isActive: map['is_active'] as bool? ?? true,
    );
  }

  bool get isAdminOrAbove =>
      role == AppRole.superAdmin || role == AppRole.admin;
  bool get isContentManager =>
      role == AppRole.superAdmin ||
      role == AppRole.admin ||
      role == AppRole.editor;
  bool get isSuperAdmin => role == AppRole.superAdmin;
}
