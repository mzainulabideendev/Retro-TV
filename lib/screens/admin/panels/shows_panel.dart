import 'package:flutter/material.dart';
import '../../../models/category.dart';
import '../../../models/channel.dart';
import '../../../models/show.dart';
import '../../../services/content_service.dart';
import '../../../widgets/admin/admin_shared.dart';

class ShowsPanel extends StatefulWidget {
  const ShowsPanel({super.key});

  @override
  State<ShowsPanel> createState() => _ShowsPanelState();
}

class _ShowsPanelState extends State<ShowsPanel> {
  bool _loading = true;
  String? _error;
  List<Show> _shows = [];
  List<Category> _categories = [];
  List<Channel> _channels = [];

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
      _shows = await ContentService.getShows(onlyEnabled: false);
      _categories = await ContentService.getCategories(onlyEnabled: false);
      _channels = await ContentService.getChannels(onlyEnabled: false);
      setState(() => _loading = false);
    } catch (e) {
      setState(() {
        _error = 'Failed to load shows.';
        _loading = false;
      });
    }
  }

  String _channelName(String? id) => _channels
      .firstWhere(
        (c) => c.id == id,
        orElse: () => Channel(
          id: '',
          channelNumber: 0,
          name: '—',
          slug: '',
          channelType: 'general',
          enabled: true,
          featured: false,
          isKidsFriendly: false,
          sortOrder: 0,
        ),
      )
      .name;

  Future<void> _openEditor({Show? show}) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => _ShowEditorDialog(
        show: show,
        categories: _categories,
        channels: _channels,
      ),
    );
    if (result == true) _load();
  }

  Future<void> _delete(Show s) async {
    final ok = await confirmDialog(
      context,
      title: 'Delete Show',
      message: 'Delete "${s.title}"?',
    );
    if (!ok) return;
    try {
      await ContentService.deleteShow(s.id);
      await ContentService.logAdminAction(
        'ADMIN_DELETED_SHOW',
        entityType: 'show',
        entityId: s.id,
      );
      if (mounted) showSuccess(context, 'Show deleted.');
      _load();
    } catch (e) {
      if (mounted) showError(context, 'Failed to delete show.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminPageScaffold(
      title: 'Shows',
      action: FilledButton.icon(
        onPressed: () => _openEditor(),
        icon: const Icon(Icons.add),
        label: const Text('New Show'),
      ),
      child: _loading
          ? const LoadingBox()
          : _error != null
          ? ErrorBox(message: _error!, onRetry: _load)
          : Card(
              child: SingleChildScrollView(
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('Title')),
                    DataColumn(label: Text('Channel')),
                    DataColumn(label: Text('Year')),
                    DataColumn(label: Text('Status')),
                    DataColumn(label: Text('Actions')),
                  ],
                  rows: _shows.map((s) {
                    return DataRow(
                      cells: [
                        DataCell(Text(s.title)),
                        DataCell(Text(_channelName(s.channelId))),
                        DataCell(Text(s.releaseYear?.toString() ?? '—')),
                        DataCell(StatusChip(enabled: s.enabled)),
                        DataCell(
                          Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit, size: 18),
                                onPressed: () => _openEditor(show: s),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.delete,
                                  size: 18,
                                  color: Colors.red,
                                ),
                                onPressed: () => _delete(s),
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
    );
  }
}

class _ShowEditorDialog extends StatefulWidget {
  final Show? show;
  final List<Category> categories;
  final List<Channel> channels;
  const _ShowEditorDialog({
    this.show,
    required this.categories,
    required this.channels,
  });

  @override
  State<_ShowEditorDialog> createState() => _ShowEditorDialogState();
}

class _ShowEditorDialogState extends State<_ShowEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _titleCtrl;
  late TextEditingController _descCtrl;
  late TextEditingController _yearCtrl;
  String? _categoryId;
  String? _channelId;
  bool _enabled = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final s = widget.show;
    _titleCtrl = TextEditingController(text: s?.title ?? '');
    _descCtrl = TextEditingController(text: s?.description ?? '');
    _yearCtrl = TextEditingController(text: s?.releaseYear?.toString() ?? '');
    _categoryId = s?.categoryId;
    _channelId = s?.channelId;
    _enabled = s?.enabled ?? true;
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
      final show = Show(
        id: widget.show?.id ?? '',
        title: _titleCtrl.text.trim(),
        slug: _slugify(_titleCtrl.text.trim()),
        description: _descCtrl.text.trim().isEmpty
            ? null
            : _descCtrl.text.trim(),
        categoryId: _categoryId,
        channelId: _channelId,
        releaseYear: int.tryParse(_yearCtrl.text.trim()),
        enabled: _enabled,
      );
      if (widget.show == null) {
        final id = await ContentService.createShow(show);
        await ContentService.logAdminAction(
          'ADMIN_CREATED_SHOW',
          entityType: 'show',
          entityId: id,
        );
      } else {
        await ContentService.updateShow(widget.show!.id, show.toInsertMap());
        await ContentService.logAdminAction(
          'ADMIN_UPDATED_SHOW',
          entityType: 'show',
          entityId: widget.show!.id,
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) showError(context, 'Failed to save show.');
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
                    widget.show == null ? 'New Show' : 'Edit Show',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _titleCtrl,
                    decoration: const InputDecoration(labelText: 'Title'),
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
                  TextFormField(
                    controller: _yearCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Release Year',
                    ),
                    keyboardType: TextInputType.number,
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
                    initialValue: _channelId,
                    decoration: const InputDecoration(labelText: 'Channel'),
                    items: widget.channels
                        .map(
                          (c) => DropdownMenuItem(
                            value: c.id,
                            child: Text('${c.channelNumber} — ${c.name}'),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setState(() => _channelId = v),
                  ),
                  CheckboxListTile(
                    value: _enabled,
                    title: const Text('Enabled'),
                    contentPadding: EdgeInsets.zero,
                    onChanged: (v) => setState(() => _enabled = v ?? true),
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
