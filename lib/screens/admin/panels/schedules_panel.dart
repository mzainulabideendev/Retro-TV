import 'package:flutter/material.dart';
import '../../../models/channel.dart';
import '../../../models/episode.dart';
import '../../../models/schedule.dart';
import '../../../services/content_service.dart';
import '../../../services/scheduling_timezone.dart';
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
    if (mounted) setState(() {});
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

  ScheduleStatus _statusAt(ScheduleEntry e) =>
      e.statusAt(DateTime.now().toUtc());

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
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Icon(
                        Icons.schedule,
                        size: 15,
                        color: Colors.white38,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'All times shown in ${SchedulingClock.zoneName} '
                        '(${SchedulingClock.offsetLabel()}) — the '
                        'scheduling timezone (selectable in Settings).',
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                          height: 1.4,
                        ),
                        softWrap: true,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: Card(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        return SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              minWidth: constraints.maxWidth,
                            ),
                            child: SingleChildScrollView(
                              child: DataTable(
                                columns: const [
                                  DataColumn(label: Text('Episode')),
                                  DataColumn(label: Text('Scheduled Start')),
                                  DataColumn(label: Text('End')),
                                  DataColumn(label: Text('Type')),
                                  DataColumn(label: Text('Status')),
                                  DataColumn(label: Text('Actions')),
                                ],
                                rows: _entries.map((e) {
                                  final status = _statusAt(e);
                                  return DataRow(
                                    cells: [
                                      DataCell(
                                        Text(_episodeTitle(e.episodeId)),
                                      ),
                                      DataCell(Text(e.displayStart)),
                                      DataCell(Text(e.displayEnd)),
                                      DataCell(
                                        Text(
                                          e.dayOfWeek != null
                                              ? 'Weekly recurring'
                                              : 'One-off',
                                        ),
                                      ),
                                      DataCell(
                                        Text(
                                          scheduleStatusLabel(status),
                                          style: TextStyle(
                                            color: _statusColor(status),
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      DataCell(
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            IconButton(
                                              icon: const Icon(
                                                Icons.edit,
                                                size: 18,
                                              ),
                                              onPressed: () =>
                                                  _openEditor(entry: e),
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
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Color _statusColor(ScheduleStatus s) {
    switch (s) {
      case ScheduleStatus.live:
        return Colors.orangeAccent;
      case ScheduleStatus.completed:
        return Colors.grey;
      case ScheduleStatus.cancelled:
        return Colors.redAccent;
      case ScheduleStatus.recurring:
        return Colors.lightBlueAccent;
      case ScheduleStatus.scheduled:
        return Colors.lightGreenAccent;
    }
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
  static const _days = [
    'Sunday',
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
  ];

  String? _episodeId;
  TimeOfDay _startTime = const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay? _endTime;
  DateTime _oneOffDate = _todayWall();
  int? _dayOfWeek;
  int _priority = 0;
  bool _enabled = true;
  bool _saving = false;

  /// Today's date in the scheduling timezone (naive wall clock).
  static DateTime _todayWall() =>
      SchedulingClock.toWallClock(DateTime.now().toUtc());

  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    _episodeId = e?.episodeId;
    if (e != null) {
      // Round-trip the stored UTC instant through the scheduling timezone
      // so the admin sees the exact wall-clock date AND time they saved.
      final wall = SchedulingClock.toWallClock(e.startTime);
      _startTime = TimeOfDay(hour: wall.hour, minute: wall.minute);
      _oneOffDate = DateTime(wall.year, wall.month, wall.day);
      _endTime = e.endTime != null
          ? TimeOfDay.fromDateTime(SchedulingClock.toWallClock(e.endTime!))
          : null;
      _dayOfWeek = e.dayOfWeek;
      _priority = e.priority;
      _enabled = e.enabled;
    }
  }

  Future<void> _save() async {
    if (_episodeId == null) {
      showError(context, 'Please select an episode.');
      return;
    }
    if (_endTime != null && !_endTime!.isAfter(_startTime)) {
      showError(context, 'End time must be after the start time.');
      return;
    }
    setState(() => _saving = true);
    try {
      final startUtc = _buildWallDateTime(_startTime);
      // One-off entries must be in the future (past entries are rejected
      // server-side too — this is just a friendly early check).
      if (_dayOfWeek == null && !startUtc.isAfter(DateTime.now().toUtc())) {
        setState(() => _saving = false);
        showError(
          context,
          'The selected date and time has already passed. '
          'Choose a future date and time.',
        );
        return;
      }

      final entry = ScheduleEntry(
        id: widget.entry?.id ?? '',
        channelId: widget.channelId,
        episodeId: _episodeId!,
        startTime: startUtc,
        endTime: _endTime != null ? _buildWallDateTime(_endTime!) : null,
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
      if (mounted) {
        final msg = _friendlyError(e);
        showError(context, msg);
      }
    }
  }

  /// Builds a wall-clock DateTime from the selected date + time and
  /// converts it to the UTC instant using the scheduling timezone — the
  /// single input boundary for the whole scheduling flow.
  DateTime _buildWallDateTime(TimeOfDay t) {
    if (_dayOfWeek != null) {
      // Recurring templates: weekday + time. The anchor date does not
      // matter — the server canonicalizes it to this week's occurrence.
      final today = _todayWall();
      final wall = DateTime(
        today.year,
        today.month,
        today.day,
        t.hour,
        t.minute,
      );
      return SchedulingClock.toUtcFromWallClock(wall);
    }
    final wall = DateTime(
      _oneOffDate.year,
      _oneOffDate.month,
      _oneOffDate.day,
      t.hour,
      t.minute,
    );
    return SchedulingClock.toUtcFromWallClock(wall);
  }

  String _friendlyError(Object e) {
    final text = e.toString();
    if (text.contains('has already passed') ||
        text.contains('already chosen')) {
      return 'The selected date and time has already passed. Choose a future date and time.';
    }
    if (text.contains('already exists') || text.contains('duplicate')) {
      return 'This episode is already scheduled at that time on this channel.';
    }
    return 'Failed to save schedule entry.';
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

  Future<void> _pickDate() async {
    final today = _todayWall();
    var first = DateTime(today.year, today.month, today.day);
    if (_oneOffDate.isBefore(first)) first = _oneOffDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: _oneOffDate,
      firstDate: first,
      lastDate: first.add(const Duration(days: 366 * 2)),
      helpText: 'Pick the airing DATE (scheduling timezone)',
    );
    if (picked != null) {
      setState(() => _oneOffDate = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isOneOff = _dayOfWeek == null;
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
                const SizedBox(height: 4),
                Text(
                  'Times are in ${SchedulingClock.zoneName} '
                  '(${SchedulingClock.offsetLabel()}) — change it in Settings.',
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
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
                DropdownButtonFormField<int?>(
                  initialValue: _dayOfWeek,
                  decoration: const InputDecoration(labelText: 'Schedule type'),
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text('One-off — airs on an exact date'),
                    ),
                    ..._days.asMap().entries.map(
                      (e) => DropdownMenuItem(
                        value: e.key,
                        child: Text('Weekly — every ${e.value}'),
                      ),
                    ),
                  ],
                  onChanged: (v) => setState(() => _dayOfWeek = v),
                ),
                const SizedBox(height: 12),
                if (isOneOff)
                  OutlinedButton.icon(
                    onPressed: _pickDate,
                    icon: const Icon(Icons.calendar_today, size: 18),
                    label: Text('Airing date: ${_formatDate(_oneOffDate)}'),
                  ),
                if (isOneOff) const SizedBox(height: 12),
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

  String _formatDate(DateTime d) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[d.month - 1]} ${d.day.toString().padLeft(2, '0')}, ${d.year}';
  }
}
