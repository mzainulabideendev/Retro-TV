import 'package:flutter/material.dart';
import '../../../services/content_service.dart';
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
  bool _loopEnabled = true;

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
      _loopEnabled = _loopFromSettings(_settings) ?? true;
      setState(() => _loading = false);
    } catch (e) {
      setState(() {
        _error = 'Failed to load settings.';
        _loading = false;
      });
    }
  }

  bool? _loopFromSettings(List<Map<String, dynamic>> settings) {
    for (final s in settings) {
      if (s['key'] == ContentService.loopChannelsSettingKey) {
        return ContentService.parseBoolSetting(s['value']);
      }
    }
    return null;
  }

  Future<void> _toggleLoop(bool value) async {
    final previous = _loopEnabled;
    setState(() => _loopEnabled = value);
    try {
      await ContentService.upsertSetting(
        ContentService.loopChannelsSettingKey,
        value,
        isPublic: true,
      );
      await ContentService.logAdminAction(
        'ADMIN_CHANGED_SETTINGS',
        entityType: 'site_settings',
        metadata: {
          'key': ContentService.loopChannelsSettingKey,
          'value': value,
        },
      );
      _load();
    } catch (e) {
      setState(() => _loopEnabled = previous);
      if (mounted) showError(context, 'Failed to update loop setting.');
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

  Future<void> _applyLoopToAll(bool value) async {
    final ok = await confirmDialog(
      context,
      title: value
          ? 'Loop for All Channels?'
          : 'Stop at End for All Channels?',
      message: value
          ? 'Every channel will repeat its episodes forever, '
              'overriding any per-channel loop choice.'
          : 'Every channel will stop after its final episode, '
              'overriding any per-channel loop choice.',
    );
    if (!ok) return;
    try {
      await ContentService.setLoopForAllChannels(value);
      await ContentService.logAdminAction(
        'ADMIN_CHANGED_SETTINGS',
        entityType: 'channels',
        metadata: {'loop_playback': value},
      );
      if (mounted) {
        showSuccess(
          context,
          value ? 'Loop enabled for all channels.' : 'Loop disabled for all channels.',
        );
      }
    } catch (e) {
      if (mounted) showError(context, 'Failed to update all channels.');
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
          : ListView(
              children: [
                Card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SwitchListTile(
                        value: _loopEnabled,
                        secondary: const Icon(Icons.repeat),
                        title: const Text('Loop Playback (global default)'),
                        subtitle: const Text(
                          'When enabled, channels play their episodes '
                          'back-to-back (1, 2, 3…) and restart from the first '
                          'episode once the last one finishes. When disabled, '
                          'playback stops after the final episode. Individual '
                          'channels can override this in the Channels panel.',
                        ),
                        onChanged: _toggleLoop,
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            FilledButton.tonalIcon(
                              onPressed: () => _applyLoopToAll(true),
                              icon: const Icon(Icons.repeat, size: 18),
                              label: const Text('Loop for All Channels'),
                            ),
                            OutlinedButton.icon(
                              onPressed: () => _applyLoopToAll(false),
                              icon: const Icon(Icons.stop, size: 18),
                              label: const Text('Stop at End (All Channels)'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'All Settings',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                ...List.generate(_settings.length, (i) {
                  final s = _settings[i];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Card(
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
                    ),
                  );
                }),
              ],
            ),
    );
  }
}
