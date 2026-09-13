import 'package:flutter/material.dart';
import '../../../services/content_service.dart';
import '../../../widgets/admin/admin_shared.dart';

class DashboardPanel extends StatefulWidget {
  const DashboardPanel({super.key});

  @override
  State<DashboardPanel> createState() => _DashboardPanelState();
}

class _DashboardPanelState extends State<DashboardPanel> {
  bool _loading = true;
  String? _error;
  Map<String, int> _stats = {};

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
      final channels = await ContentService.getChannels(onlyEnabled: false);
      final shows = await ContentService.getShows(onlyEnabled: false);
      final episodes = await ContentService.getEpisodes();
      final tvStyles = await ContentService.getTvStyles(onlyEnabled: false);

      setState(() {
        _stats = {
          'Total Channels': channels.length,
          'Active Channels': channels.where((c) => c.enabled).length,
          'Total Shows': shows.length,
          'Total Episodes': episodes.length,
          'Total TV Styles': tvStyles.length,
          'Published Content': episodes
              .where((e) => e.status == 'published')
              .length,
          'Disabled Content': episodes.where((e) => !e.enabled).length,
        };
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load dashboard stats.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminPageScaffold(
      title: 'Dashboard',
      child: _loading
          ? const LoadingBox()
          : _error != null
          ? ErrorBox(message: _error!, onRetry: _load)
          : LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final columns = width >= 900
                    ? 4
                    : width >= 600
                    ? 3
                    : 2;
                return GridView.count(
                  crossAxisCount: columns,
                  childAspectRatio: width < 600 ? 1.4 : 1.6,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                  children: _stats.entries
                      .map((e) => _StatCard(label: e.key, value: e.value))
                      .toList(),
                );
              },
            ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final int value;
  const _StatCard({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$value',
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1C1C26),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
