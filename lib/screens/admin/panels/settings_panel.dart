import 'package:flutter/material.dart';
import '../../../services/supabase_service.dart';
import '../../../widgets/admin/admin_shared.dart';

class SettingsPanel extends StatefulWidget {
  const SettingsPanel({super.key});

  @override
  State<SettingsPanel> createState() => _SettingsPanelState();
}

class _SettingsPanelState extends State<SettingsPanel> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _settings = [];

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
      final res = await SupabaseService.client
          .from('site_settings')
          .select()
          .order('key');
      _settings = (res as List).cast<Map<String, dynamic>>();
      setState(() => _loading = false);
    } catch (e) {
      setState(() {
        _error = 'Failed to load settings.';
        _loading = false;
      });
    }
  }

  Future<void> _edit(Map<String, dynamic> setting) async {
    final controller = TextEditingController(text: setting['value'].toString());
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(setting['key'] as String),
        content: TextField(
          controller: controller,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Value (JSON)'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result == null) return;
    try {
      dynamic parsed;
      try {
        parsed =
            result; // stored as jsonb; supabase client will encode string as-is if valid JSON literal
      } catch (_) {
        parsed = result;
      }
      await SupabaseService.client
          .from('site_settings')
          .update({'value': parsed})
          .eq('id', setting['id']);
      await SupabaseService.client.rpc(
        'log_admin_action',
        params: {
          'p_action': 'ADMIN_CHANGED_SETTINGS',
          'p_entity_type': 'site_settings',
          'p_entity_id': setting['id'],
          'p_metadata': {'key': setting['key']},
        },
      );
      if (mounted) showSuccess(context, 'Setting updated.');
      _load();
    } catch (e) {
      if (mounted) showError(context, 'Failed to update setting.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminPageScaffold(
      title: 'Platform Settings',
      child: _loading
          ? const LoadingBox()
          : _error != null
          ? ErrorBox(message: _error!, onRetry: _load)
          : ListView.separated(
              itemCount: _settings.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final s = _settings[i];
                return Card(
                  child: ListTile(
                    title: Text(
                      s['key'] as String,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      s['value'].toString(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.edit),
                      onPressed: () => _edit(s),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
