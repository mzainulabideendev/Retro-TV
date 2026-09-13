import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../public/home_screen.dart';
import 'panels/dashboard_panel.dart';
import 'panels/channels_panel.dart';
import 'panels/shows_panel.dart';
import 'panels/episodes_panel.dart';
import 'panels/schedules_panel.dart';
import 'panels/tv_styles_panel.dart';
import 'panels/categories_panel.dart';
import 'panels/users_panel.dart';
import 'panels/settings_panel.dart';
import 'panels/audit_logs_panel.dart';

enum AdminSection {
  dashboard,
  channels,
  shows,
  episodes,
  schedules,
  tvStyles,
  categories,
  users,
  settings,
  auditLogs,
}

/// Professional admin dashboard shell with a role-aware sidebar.
/// Editors only see Shows/Episodes management; admins/super_admins see
/// everything except Users which is super_admin-only for role changes.
class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  AdminSection _section = AdminSection.dashboard;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final profile = auth.profile;

    if (profile == null || !profile.isContentManager) {
      return const _Unauthorized();
    }

    final isAdmin = profile.isAdminOrAbove;
    final isSuperAdmin = profile.isSuperAdmin;

    final sidebar = _Sidebar(
      current: _section,
      isAdmin: isAdmin,
      isSuperAdmin: isSuperAdmin,
      onSelect: (s) => setState(() => _section = s),
      onLogout: () async {
        await auth.signOut();
        if (!context.mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      },
    );

    // Responsive shell: wide screens get the classic sidebar + content two
    // pane layout; narrow screens (phones) collapse the navigation into a
    // drawer so the content panels never get squeezed and overflow.
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 840;
        if (wide) {
          return Scaffold(
            backgroundColor: const Color(0xFFF4F5F7),
            body: Row(
              children: [
                SizedBox(width: 220, child: sidebar),
                Expanded(child: _buildPanel(profile)),
              ],
            ),
          );
        }
        return Scaffold(
          backgroundColor: const Color(0xFFF4F5F7),
          appBar: AppBar(
            backgroundColor: const Color(0xFF1C1C26),
            elevation: 0,
            leading: Builder(
              builder: (context) => IconButton(
                icon: const Icon(Icons.menu, color: Colors.white),
                onPressed: () => Scaffold.of(context).openDrawer(),
              ),
            ),
            title: const Text(
              'Retro TV Admin',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          drawer: Drawer(child: sidebar),
          body: _buildPanel(profile),
        );
      },
    );
  }

  Widget _buildPanel(dynamic profile) {
    switch (_section) {
      case AdminSection.dashboard:
        return const DashboardPanel();
      case AdminSection.channels:
        return const ChannelsPanel();
      case AdminSection.shows:
        return const ShowsPanel();
      case AdminSection.episodes:
        return const EpisodesPanel();
      case AdminSection.schedules:
        return const SchedulesPanel();
      case AdminSection.tvStyles:
        return const TvStylesPanel();
      case AdminSection.categories:
        return const CategoriesPanel();
      case AdminSection.users:
        return const UsersPanel();
      case AdminSection.settings:
        return const SettingsPanel();
      case AdminSection.auditLogs:
        return const AuditLogsPanel();
    }
  }
}

class _Sidebar extends StatelessWidget {
  final AdminSection current;
  final bool isAdmin;
  final bool isSuperAdmin;
  final void Function(AdminSection) onSelect;
  final VoidCallback onLogout;

  const _Sidebar({
    required this.current,
    required this.isAdmin,
    required this.isSuperAdmin,
    required this.onSelect,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    final items = <(AdminSection, IconData, String, bool)>[
      (AdminSection.dashboard, Icons.dashboard, 'Dashboard', true),
      (AdminSection.channels, Icons.live_tv, 'Channels', isAdmin),
      (AdminSection.shows, Icons.movie, 'Shows', true),
      (AdminSection.episodes, Icons.play_circle, 'Episodes', true),
      (AdminSection.schedules, Icons.schedule, 'Schedules', isAdmin),
      (AdminSection.tvStyles, Icons.tv, 'TV Styles', isAdmin),
      (AdminSection.categories, Icons.category, 'Categories', isAdmin),
      (AdminSection.users, Icons.people, 'Users', isSuperAdmin),
      (AdminSection.settings, Icons.settings, 'Settings', isAdmin),
      (AdminSection.auditLogs, Icons.receipt_long, 'Audit Logs', isAdmin),
    ];

    return Container(
      // Fills whatever width the parent gives it (the fixed 220px sidebar
      // on wide layouts, or the full-width drawer on narrow layouts).
      color: const Color(0xFF1C1C26),
      child: Column(
        children: [
          const SizedBox(height: 20),
          const Icon(Icons.tv, color: Colors.white, size: 32),
          const SizedBox(height: 6),
          const Text(
            'Retro TV Admin',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: ListView(
              children: items
                  .where((e) => e.$4)
                  .map((e) => _navTile(e.$1, e.$2, e.$3))
                  .toList(),
            ),
          ),
          const Divider(color: Colors.white12),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.white54),
            title: const Text(
              'Logout',
              style: TextStyle(color: Colors.white54),
            ),
            onTap: onLogout,
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _navTile(AdminSection section, IconData icon, String label) {
    final selected = section == current;
    return ListTile(
      leading: Icon(
        icon,
        color: selected ? Colors.white : Colors.white54,
        size: 20,
      ),
      title: Text(
        label,
        style: TextStyle(
          color: selected ? Colors.white : Colors.white54,
          fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          fontSize: 13,
        ),
      ),
      selected: selected,
      selectedTileColor: Colors.white.withValues(alpha: 0.08),
      onTap: () => onSelect(section),
    );
  }
}

class _Unauthorized extends StatelessWidget {
  const _Unauthorized();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock, color: Colors.redAccent, size: 40),
            const SizedBox(height: 12),
            const Text(
              'Unauthorized',
              style: TextStyle(color: Colors.white, fontSize: 18),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const HomeScreen()),
              ),
              child: const Text('Back to TV'),
            ),
          ],
        ),
      ),
    );
  }
}
