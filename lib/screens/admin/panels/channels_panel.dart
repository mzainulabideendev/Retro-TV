import 'package:flutter/material.dart';
import '../../../models/category.dart';
import '../../../models/channel.dart';
import '../../../models/episode.dart';
import '../../../services/content_service.dart';
import '../../../widgets/admin/admin_shared.dart';

class ChannelsPanel extends StatefulWidget {
  const ChannelsPanel({super.key});

  @override
  State<ChannelsPanel> createState() => _ChannelsPanelState();
}

class _ChannelsPanelState extends State<ChannelsPanel> {
  bool _loading = true;
  String? _error;
  List<Channel> _channels = [];
  List<Category> _categories = [];
  String _search = '';

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
      _channels = await ContentService.getChannels(onlyEnabled: false);
      _categories = await ContentService.getCategories(onlyEnabled: false);
      setState(() => _loading = false);
    } catch (e) {
      setState(() {
        _error = 'Failed to load channels.';
        _loading = false;
      });
    }
  }

  List<Channel> get _filtered {
    if (_search.isEmpty) return _channels;
    return _channels
        .where((c) => c.name.toLowerCase().contains(_search.toLowerCase()))
        .toList();
  }

  String _categoryName(String? id) {
    if (id == null) return '—';
    return _categories
        .firstWhere(
          (c) => c.id == id,
          orElse: () => Category(
            id: '',
            name: '—',
            slug: '',
            enabled: true,
            sortOrder: 0,
          ),
        )
        .name;
  }

  Future<void> _openEditor({Channel? channel}) async {
    // Load every episode so the editor can offer a "Now Playing" picker
    // (episodes tagged for this channel are shown first).
    List<Episode> episodes = [];
    try {
      episodes = await ContentService.getEpisodes();
    } catch (_) {
      // non-fatal — the picker will just show empty if this fails
    }
    if (!mounted) return;
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => _ChannelEditorDialog(
        channel: channel,
        categories: _categories,
        episodes: episodes,
      ),
    );
    if (result == true) _load();
  }

  Future<void> _delete(Channel c) async {
    final ok = await confirmDialog(
      context,
      title: 'Delete Channel',
      message: 'Delete "${c.name}"? This cannot be undone.',
    );
    if (!ok) return;
    try {
      await ContentService.deleteChannel(c.id);
      await ContentService.logAdminAction(
        'ADMIN_DELETED_CHANNEL',
        entityType: 'channel',
        entityId: c.id,
      );
      if (mounted) showSuccess(context, 'Channel deleted.');
      _load();
    } catch (e) {
      if (mounted) showError(context, 'Failed to delete channel.');
    }
  }

  Future<void> _toggleEnabled(Channel c) async {
    try {
      await ContentService.updateChannel(c.id, {'enabled': !c.enabled});
      await ContentService.logAdminAction(
        c.enabled ? 'ADMIN_DISABLED_CHANNEL' : 'ADMIN_ENABLED_CHANNEL',
        entityType: 'channel',
        entityId: c.id,
      );
      _load();
    } catch (e) {
      if (mounted) showError(context, 'Failed to update channel.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminPageScaffold(
      title: 'Channels',
      action: FilledButton.icon(
        onPressed: () => _openEditor(),
        icon: const Icon(Icons.add),
        label: const Text('New Channel'),
      ),
      child: _loading
          ? const LoadingBox()
          : _error != null
          ? ErrorBox(message: _error!, onRetry: _load)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Search channels...',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) => setState(() => _search = v),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: Card(
                    child: SingleChildScrollView(
                      child: DataTable(
                        columns: const [
                          DataColumn(label: Text('#')),
                          DataColumn(label: Text('Channel')),
                          DataColumn(label: Text('Category')),
                          DataColumn(label: Text('Type')),
                          DataColumn(label: Text('Status')),
                          DataColumn(label: Text('Actions')),
                        ],
                        rows: _filtered.map((c) {
                          return DataRow(
                            cells: [
                              DataCell(
                                Text(
                                  c.channelNumber.toString().padLeft(2, '0'),
                                ),
                              ),
                              DataCell(Text(c.name)),
                              DataCell(Text(_categoryName(c.categoryId))),
                              DataCell(Text(c.channelType)),
                              DataCell(StatusChip(enabled: c.enabled)),
                              DataCell(
                                Row(
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.edit, size: 18),
                                      onPressed: () => _openEditor(channel: c),
                                    ),
                                    IconButton(
                                      icon: Icon(
                                        c.enabled
                                            ? Icons.visibility_off
                                            : Icons.visibility,
                                        size: 18,
                                      ),
                                      onPressed: () => _toggleEnabled(c),
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.delete,
                                        size: 18,
                                        color: Colors.red,
                                      ),
                                      onPressed: () => _delete(c),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _ChannelEditorDialog extends StatefulWidget {
  final Channel? channel;
  final List<Category> categories;
  final List<Episode> episodes;
  const _ChannelEditorDialog({
    this.channel,
    required this.categories,
    this.episodes = const [],
  });

  @override
  State<_ChannelEditorDialog> createState() => _ChannelEditorDialogState();
}

class _ChannelEditorDialogState extends State<_ChannelEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameCtrl;
  late TextEditingController _numberCtrl;
  late TextEditingController _descCtrl;
  String? _categoryId;
  String _channelType = 'general';
  bool _enabled = true;
  bool _featured = false;
  bool _kidsFriendly = false;
  bool _saving = false;
  String? _defaultEpisodeId;

  static const _types = [
    'kids',
    'cartoons',
    'animation',
    'classic_tv',
    'comedy',
    'educational',
    'music',
    'retro',
    'movies',
    'general',
  ];

  @override
  void initState() {
    super.initState();
    final c = widget.channel;
    _nameCtrl = TextEditingController(text: c?.name ?? '');
    _numberCtrl = TextEditingController(
      text: c?.channelNumber.toString() ?? '',
    );
    _descCtrl = TextEditingController(text: c?.description ?? '');
    _categoryId = c?.categoryId;
    _channelType = c?.channelType ?? 'general';
    _enabled = c?.enabled ?? true;
    _featured = c?.featured ?? false;
    _kidsFriendly = c?.isKidsFriendly ?? false;
    _defaultEpisodeId = c?.defaultEpisodeId;
  }

  /// Episodes assigned to this channel are listed first (most relevant),
  /// followed by everything else, so the admin can always pick any
  /// episode as the channel's "Now Playing" program.
  List<Episode> get _sortedEpisodes {
    final list = [...widget.episodes];
    final channelId = widget.channel?.id;
    list.sort((a, b) {
      final aMatch = channelId != null && a.channelId == channelId;
      final bMatch = channelId != null && b.channelId == channelId;
      if (aMatch == bMatch) return a.title.compareTo(b.title);
      return aMatch ? -1 : 1;
    });
    return list;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _numberCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  String _slugify(String s) => s
      .toLowerCase()
      .trim()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final number = int.parse(_numberCtrl.text.trim());
      if (widget.channel == null) {
        final id = await ContentService.createChannel(
          Channel(
            id: '',
            channelNumber: number,
            name: _nameCtrl.text.trim(),
            slug: _slugify(_nameCtrl.text.trim()),
            description: _descCtrl.text.trim().isEmpty
                ? null
                : _descCtrl.text.trim(),
            categoryId: _categoryId,
            channelType: _channelType,
            defaultEpisodeId: _defaultEpisodeId,
            enabled: _enabled,
            featured: _featured,
            isKidsFriendly: _kidsFriendly,
            sortOrder: number,
          ),
        );
        await ContentService.logAdminAction(
          'ADMIN_CREATED_CHANNEL',
          entityType: 'channel',
          entityId: id,
        );
      } else {
        await ContentService.updateChannel(widget.channel!.id, {
          'channel_number': number,
          'name': _nameCtrl.text.trim(),
          'description': _descCtrl.text.trim().isEmpty
              ? null
              : _descCtrl.text.trim(),
          'category_id': _categoryId,
          'channel_type': _channelType,
          'default_episode_id': _defaultEpisodeId,
          'enabled': _enabled,
          'featured': _featured,
          'is_kids_friendly': _kidsFriendly,
        });
        await ContentService.logAdminAction(
          'ADMIN_UPDATED_CHANNEL',
          entityType: 'channel',
          entityId: widget.channel!.id,
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) {
        showError(context, e.toString().replaceAll('Exception: ', ''));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.channel == null ? 'New Channel' : 'Edit Channel',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _numberCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Channel Number',
                    ),
                    keyboardType: TextInputType.number,
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Required';
                      final n = int.tryParse(v);
                      if (n == null || n < 1) {
                        return 'Must be a positive integer';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Channel Name',
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _descCtrl,
                    decoration: const InputDecoration(labelText: 'Description'),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _categoryId,
                    decoration: const InputDecoration(labelText: 'Category'),
                    items: widget.categories
                        .map(
                          (c) => DropdownMenuItem(
                            value: c.id,
                            child: Text(c.name),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setState(() => _categoryId = v),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _channelType,
                    decoration: const InputDecoration(
                      labelText: 'Channel Type',
                    ),
                    items: _types
                        .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                        .toList(),
                    onChanged: (v) =>
                        setState(() => _channelType = v ?? 'general'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _defaultEpisodeId,
                    decoration: const InputDecoration(
                      labelText: 'Now Playing (Default Episode)',
                      helperText:
                          'This is what actually airs on the TV for this '
                          'channel unless a schedule entry overrides it.',
                      helperMaxLines: 2,
                    ),
                    isExpanded: true,
                    items: [
                      const DropdownMenuItem<String>(
                        value: null,
                        child: Text('— None —'),
                      ),
                      ..._sortedEpisodes.map(
                        (e) => DropdownMenuItem(
                          value: e.id,
                          child: Text(e.title, overflow: TextOverflow.ellipsis),
                        ),
                      ),
                    ],
                    onChanged: (v) => setState(() => _defaultEpisodeId = v),
                  ),
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    value: _enabled,
                    title: const Text('Enabled'),
                    contentPadding: EdgeInsets.zero,
                    onChanged: (v) => setState(() => _enabled = v ?? true),
                  ),
                  CheckboxListTile(
                    value: _featured,
                    title: const Text('Featured'),
                    contentPadding: EdgeInsets.zero,
                    onChanged: (v) => setState(() => _featured = v ?? false),
                  ),
                  CheckboxListTile(
                    value: _kidsFriendly,
                    title: const Text('Kids-Friendly (admin-verified)'),
                    contentPadding: EdgeInsets.zero,
                    onChanged: (v) =>
                        setState(() => _kidsFriendly = v ?? false),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: _saving ? null : _save,
                        child: _saving
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Save'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
