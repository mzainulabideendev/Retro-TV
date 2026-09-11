import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../services/auth_service.dart';
import '../../../services/content_service.dart';
import '../../../widgets/admin/admin_shared.dart';

/// User/admin management. Role changes are executed via the
/// `promote_user_to_role` RPC which enforces super_admin-only server-side
/// (see migration 004_functions.sql) — this UI simply calls that RPC and
/// never mutates profiles.role directly from the client.
class UsersPanel extends StatefulWidget {
  const UsersPanel({super.key});

  @override
  State<UsersPanel> createState() => _UsersPanelState();
}

class _UsersPanelState extends State<UsersPanel> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _profiles = [];

  static const _roles = ['super_admin', 'admin', 'editor', 'viewer'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _profiles = await ContentService.getAllProfiles();
      setState(() => _loading = false);
    } catch (e) {
      setState(() {
        _error = 'Failed to load users. (You may need super_admin access.)';
        _loading = false;
      });
    }
  }

  Future<void> _changeRole(String userId, String newRole) async {
    try {
      await ContentService.promoteUserToRole(userId, newRole);
      if (mounted) showSuccess(context, 'Role updated.');
      _load();
    } catch (e) {
      if (mounted) {
        showError(
          context,
          'Failed to update role. Only super_admin can change roles.',
        );
      }
    }
  }

  Future<void> _toggleActive(String userId, bool active) async {
    try {
      await ContentService.setProfileActive(userId, active);
      _load();
    } catch (e) {
      if (mounted) showError(context, 'Failed to update status.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = context.read<AuthService>().currentUser?.id;
    return AdminPageScaffold(
      title: 'Users & Admins',
      child: _loading
          ? const LoadingBox()
          : _error != null
          ? ErrorBox(message: _error!, onRetry: _load)
          : Card(
              child: SingleChildScrollView(
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('Email')),
                    DataColumn(label: Text('Display Name')),
                    DataColumn(label: Text('Role')),
                    DataColumn(label: Text('Status')),
                    DataColumn(label: Text('Actions')),
                  ],
                  rows: _profiles.map((p) {
                    final userId = p['id'] as String;
                    final role = p['role'] as String? ?? 'viewer';
                    final isActive = p['is_active'] as bool? ?? true;
                    final isSelf = userId == currentUserId;
                    return DataRow(
                      cells: [
                        DataCell(Text(p['email'] as String? ?? '')),
                        DataCell(Text(p['display_name'] as String? ?? '—')),
                        DataCell(
                          DropdownButton<String>(
                            value: role,
                            underline: const SizedBox.shrink(),
                            items: _roles
                                .map(
                                  (r) => DropdownMenuItem(
                                    value: r,
                                    child: Text(r),
                                  ),
                                )
                                .toList(),
                            onChanged: isSelf
                                ? null
                                : (v) =>
                                      v != null ? _changeRole(userId, v) : null,
                          ),
                        ),
                        DataCell(StatusChip(enabled: isActive)),
                        DataCell(
                          isSelf
                              ? const Text(
                                  '(you)',
                                  style: TextStyle(
                                    color: Colors.grey,
                                    fontSize: 12,
                                  ),
                                )
                              : IconButton(
                                  icon: Icon(
                                    isActive
                                        ? Icons.block
                                        : Icons.check_circle_outline,
                                    size: 18,
                                  ),
                                  tooltip: isActive ? 'Deactivate' : 'Activate',
                                  onPressed: () =>
                                      _toggleActive(userId, !isActive),
                                ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),
    );
  }
}
