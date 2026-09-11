import 'package:flutter/material.dart';
import '../../../models/channel.dart';
import '../../../models/episode.dart';
import '../../../models/schedule.dart';
import '../../../services/content_service.dart';
import '../../../widgets/admin/admin_shared.dart';

class SchedulesPanel extends StatefulWidget {
  const SchedulesPanel({super.key});

  @override
  State<SchedulesPanel> createState() => _SchedulesPanelState();
}

class _SchedulesPanelState extends State<SchedulesPanel> {
  bool _loading = true;
  String? _error;
  List<Channel> _channels = [];
  Channel? _selectedChannel;
  List<ScheduleEntry> _entries = [];
  List<Episode> _episodes = [];

  static const _days = [
    'Sunday',
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
  ];

  @override
  void initState() {
    super.initState();
    _loadChannels();
  }

  Future<void> _loadChannels() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _channels = await ContentService.getChannels(onlyEnabled: false);
      if (_channels.isNotEmpty) {
        _selectedChannel = _channels.first;
        await _loadSchedule();
      }
      setState(() => _loading = false);
    } catch (e) {
      setState(() {
        _error = 'Failed to load channels.';
        _loading = false;
      });
    }
  }

  Future<void> _loadSchedule() async {
    if (_selectedChannel == null) return;
    _entries = await ContentService.getSchedule(_selectedChannel!.id);
    _episodes = await ContentService.getEpisodes(
      channelId: _selectedChannel!.id,
    );
    setState(() {});
  }

  String _episodeTitle(String id) => _episodes
      .firstWhere(
        (e) => e.id == id,
        orElse: () => Episode(
          id: '',
          seasonNumber: 1,
          title: 'Unknown',
          youtubeVideoId: '',
          status: 'draft',
          enabled: true,
          sortOrder: 0,
        ),
      )
      .title;

  Future<void> _openEditor({ScheduleEntry? entry}) async {
    if (_selectedChannel == null) return;
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => _ScheduleEditorDialog(
        channelId: _selectedChannel!.id,
        episodes: _episodes,
        entry: entry,
      ),
    );
    if (result == true) _loadSchedule();
  }

  Future<void> _delete(ScheduleEntry e) async {
    final ok = await confirmDialog(
      context,
      title: 'Delete Schedule Entry',
      message: 'Remove this schedule entry?',
    );
    if (!ok) return;
    try {
      await ContentService.deleteScheduleEntry(e.id);
      await ContentService.logAdminAction(
        'ADMIN_UPDATED_SCHEDULE',
        entityType: 'schedule',
        entityId: e.id,
        metadata: {'action': 'deleted'},
      );
      _loadSchedule();
    } catch (ex) {
      if (mounted) showError(context, 'Failed to delete entry.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminPageScaffold(
      title: 'Channel Schedules',
      action: FilledButton.icon(
        onPressed: _selectedChannel == null ? null : () => _openEditor(),
        icon: const Icon(Icons.add),
        label: const Text('New Entry'),
      ),
      child: _loading
          ? const LoadingBox()
          : _error != null
          ? ErrorBox(message: _error!, onRetry: _loadChannels)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<Channel>(
                  initialValue: _selectedChannel,
                  decoration: const InputDecoration(
                    labelText: 'Select Channel',
                  ),
                  items: _channels
                      .map(
                        (c) => DropdownMenuItem(
                          value: c,
                          child: Text('${c.channelNumber} — ${c.name}'),
                        ),
                      )
                      .toList(),
                  onChanged: (c) {
                    setState(() => _selectedChannel = c);
                    _loadSchedule();
                  },
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: Card(
                    child: SingleChildScrollView(
                      child: DataTable(
                        columns: const [
                          DataColumn(label: Text('Episode')),
                          DataColumn(label: Text('Start')),
                          DataColumn(label: Text('End')),
                          DataColumn(label: Text('Day')),
                          DataColumn(label: Text('Priority')),
                          DataColumn(label: Text('Status')),
                          DataColumn(label: Text('Actions')),
                        ],
                        rows: _entries.map((e) {
                          return DataRow(
                            cells: [
                              DataCell(Text(_episodeTitle(e.episodeId))),
                              DataCell(
                                Text(
                                  '${e.startTime.hour.toString().padLeft(2, '0')}:${e.startTime.minute.toString().padLeft(2, '0')}',
                                ),
                              ),
                              DataCell(
                                Text(
                                  e.endTime != null
                                      ? '${e.endTime!.hour.toString().padLeft(2, '0')}:${e.endTime!.minute.toString().padLeft(2, '0')}'
                                      : '—',
                                ),
                              ),
                              DataCell(
                                Text(
                                  e.dayOfWeek != null
                                      ? _days[e.dayOfWeek!]
                                      : 'One-off',
                                ),
                              ),
                              DataCell(Text('${e.priority}')),
                              DataCell(StatusChip(enabled: e.enabled)),
                              DataCell(
                                Row(
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.edit, size: 18),
                                      onPressed: () => _openEditor(entry: e),
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.delete,
                                        size: 18,
                                        color: Colors.red,
                                      ),
                                      onPressed: () => _delete(e),
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

class _ScheduleEditorDialog extends StatefulWidget {
  final String channelId;
  final List<Episode> episodes;
  final ScheduleEntry? entry;
  const _ScheduleEditorDialog({
    required this.channelId,
    required this.episodes,
    this.entry,
  });

  @override
  State<_ScheduleEditorDialog> createState() => _ScheduleEditorDialogState();
}

class _ScheduleEditorDialogState extends State<_ScheduleEditorDialog> {
  String? _episodeId;
  TimeOfDay _startTime = const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay? _endTime;
  int? _dayOfWeek;
  int _priority = 0;
  bool _enabled = true;
  bool _saving = false;

  static const _days = [
    'Sunday',
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
  ];

  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    _episodeId = e?.episodeId;
    if (e != null) {
      _startTime = TimeOfDay.fromDateTime(e.startTime);
      _endTime = e.endTime != null ? TimeOfDay.fromDateTime(e.endTime!) : null;
      _dayOfWeek = e.dayOfWeek;
      _priority = e.priority;
      _enabled = e.enabled;
    }
  }

  DateTime _todayWithTime(TimeOfDay t) {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day, t.hour, t.minute);
  }

  Future<void> _save() async {
    if (_episodeId == null) {
      showError(context, 'Please select an episode.');
      return;
    }
    setState(() => _saving = true);
    try {
      final entry = ScheduleEntry(
        id: widget.entry?.id ?? '',
        channelId: widget.channelId,
        episodeId: _episodeId!,
        startTime: _todayWithTime(_startTime),
        endTime: _endTime != null ? _todayWithTime(_endTime!) : null,
        dayOfWeek: _dayOfWeek,
        priority: _priority,
        enabled: _enabled,
      );
      if (widget.entry == null) {
        await ContentService.createScheduleEntry(entry);
        await ContentService.logAdminAction(
          'ADMIN_UPDATED_SCHEDULE',
          entityType: 'schedule',
          metadata: {'action': 'created'},
        );
      } else {
        await ContentService.updateScheduleEntry(
          widget.entry!.id,
          entry.toInsertMap(),
        );
        await ContentService.logAdminAction(
          'ADMIN_UPDATED_SCHEDULE',
          entityType: 'schedule',
          entityId: widget.entry!.id,
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) showError(context, 'Failed to save schedule entry.');
    }
  }

  Future<void> _pickTime(bool isStart) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isStart ? _startTime : (_endTime ?? _startTime),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startTime = picked;
        } else {
          _endTime = picked;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.entry == null
                      ? 'New Schedule Entry'
                      : 'Edit Schedule Entry',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _episodeId,
                  decoration: const InputDecoration(labelText: 'Episode'),
                  items: widget.episodes
                      .map(
                        (e) =>
                            DropdownMenuItem(value: e.id, child: Text(e.title)),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => _episodeId = v),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _pickTime(true),
                        child: Text('Start: ${_startTime.format(context)}'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _pickTime(false),
                        child: Text(
                          _endTime != null
                              ? 'End: ${_endTime!.format(context)}'
                              : 'End: (none)',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int?>(
                  initialValue: _dayOfWeek,
                  decoration: const InputDecoration(
                    labelText:
                        'Day of Week (recurring) — leave blank for one-off',
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text('One-off (dated)'),
                    ),
                    ..._days.asMap().entries.map(
                      (e) =>
                          DropdownMenuItem(value: e.key, child: Text(e.value)),
                    ),
                  ],
                  onChanged: (v) => setState(() => _dayOfWeek = v),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  initialValue: _priority.toString(),
                  decoration: const InputDecoration(labelText: 'Priority'),
                  keyboardType: TextInputType.number,
                  onChanged: (v) => _priority = int.tryParse(v) ?? 0,
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
                              child: CircularProgressIndicator(strokeWidth: 2),
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
    );
  }
}
