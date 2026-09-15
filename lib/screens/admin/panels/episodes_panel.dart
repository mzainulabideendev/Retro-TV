import 'package:flutter/material.dart';
import '../../../models/channel.dart';
import '../../../models/episode.dart';
import '../../../models/show.dart';
import '../../../services/content_service.dart';
import '../../../services/playlist_import_service.dart';
import '../../../utils/youtube_utils.dart';
import '../../../widgets/admin/admin_shared.dart';
import '../../../widgets/tv/youtube_screen_player.dart';

class EpisodesPanel extends StatefulWidget {
  const EpisodesPanel({super.key});

  @override
  State<EpisodesPanel> createState() => _EpisodesPanelState();
}

class _EpisodesPanelState extends State<EpisodesPanel> {
  bool _loading = true;
  String? _error;
  List<Episode> _episodes = [];
  List<Show> _shows = [];
  List<Channel> _channels = [];
  final _searchCtrl = TextEditingController();
  String _search = '';
  String? _filterShowId;
  String? _filterChannelId;
  String? _filterStatus;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<Episode> get _filtered {
    final q = _search.toLowerCase();
    return _episodes.where((e) {
      final matchesSearch = _search.isEmpty ||
          e.title.toLowerCase().contains(q) ||
          e.youtubeVideoId.toLowerCase().contains(q) ||
          'S${e.seasonNumber}E${e.episodeNumber ?? ''}'
              .toLowerCase()
              .contains(q);
      final matchesShow =
          _filterShowId == null || e.showId == _filterShowId;
      final matchesChannel =
          _filterChannelId == null || e.channelId == _filterChannelId;
      final matchesStatus =
          _filterStatus == null || e.status == _filterStatus;
      return matchesSearch && matchesShow && matchesChannel && matchesStatus;
    }).toList();
  }

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
      _episodes = await ContentService.getEpisodes();
      _shows = await ContentService.getShows(onlyEnabled: false);
      _channels = await ContentService.getChannels(onlyEnabled: false);
      setState(() => _loading = false);
    } catch (e) {
      setState(() {
        _error = 'Failed to load episodes.';
        _loading = false;
      });
    }
  }

  String _showTitle(String? id) => _shows
      .firstWhere(
        (s) => s.id == id,
        orElse: () => Show(id: '', title: '—', slug: '', enabled: true),
      )
      .title;
  String _channelName(String? id) => id == null
      ? '—'
      : _channels
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

  Future<void> _openEditor({Episode? episode}) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => _EpisodeEditorDialog(
        episode: episode,
        shows: _shows,
        channels: _channels,
      ),
    );
    if (result == true) _load();
  }

  Future<void> _openPlaylistImport() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => _PlaylistImportDialog(channels: _channels, shows: _shows),
    );
    if (result == true) _load();
  }

  /// Moves an episode one position up/down WITHIN its channel's playback
  /// order by rewriting that channel's `sort_order` (the admin-only
  /// `reorder_episodes` RPC). Episode order determines the continuous
  /// channel loop sequence.
  Future<void> _moveEpisode(Episode e, int delta) async {
    final channelId = e.channelId;
    if (channelId == null) {
      if (mounted) {
        showError(
          context,
          'This episode has no channel assigned. Edit it and choose a channel first.',
        );
      }
      return;
    }
    final group = _episodes.where((x) => x.channelId == channelId).toList();
    if (group.isEmpty) return;
    group.sort((a, b) {
      final sa = a.sortOrder;
      final sb = b.sortOrder;
      if (sa != sb) return sa.compareTo(sb);
      final pa = a.playlistPosition ?? 1 << 30;
      final pb = b.playlistPosition ?? 1 << 30;
      if (pa != pb) return pa.compareTo(pb);
      return (a.episodeNumber ?? 1 << 30).compareTo(b.episodeNumber ?? 1 << 30);
    });

    final ids = group.map((x) => x.id).toList();
    final i = ids.indexOf(e.id);
    if (i < 0) return;
    final j = i + delta;
    if (j < 0 || j >= ids.length) return;

    final reordered = [...ids];
    final tmp = reordered[i];
    reordered[i] = reordered[j];
    reordered[j] = tmp;

    try {
      await ContentService.reorderEpisodes(channelId, reordered);
      await ContentService.logAdminAction(
        'ADMIN_REORDERED_EPISODES',
        entityType: 'episode',
        entityId: e.id,
        metadata: {'channel_id': channelId},
      );
      _load();
    } catch (ex) {
      if (mounted) {
        showError(context, 'Failed to reorder. Admin access is required.');
      }
    }
  }

  Future<void> _delete(Episode e) async {
    final ok = await confirmDialog(
      context,
      title: 'Delete Episode',
      message: 'Delete "${e.title}"?',
    );
    if (!ok) return;
    try {
      await ContentService.deleteEpisode(e.id);
      await ContentService.logAdminAction(
        'ADMIN_DELETED_EPISODE',
        entityType: 'episode',
        entityId: e.id,
      );
      if (mounted) showSuccess(context, 'Episode deleted.');
      _load();
    } catch (ex) {
      if (mounted) showError(context, 'Failed to delete episode.');
    }
  }

  /// Makes [e] the channel's "now playing" program by setting
  /// `channels.default_episode_id`. This is the missing link that was
  /// causing admin-added episodes to show "Channel unavailable" on the
  /// public TV until an admin manually wired up the channel/schedule —
  /// this button does it in one click.
  Future<void> _setAsNowPlaying(Episode e) async {
    if (e.channelId == null) {
      if (mounted) {
        showError(
          context,
          'This episode has no channel assigned. Edit it and choose a channel first.',
        );
      }
      return;
    }
    try {
      await ContentService.updateChannel(e.channelId!, {
        'default_episode_id': e.id,
      });
      await ContentService.logAdminAction(
        'ADMIN_UPDATED_CHANNEL',
        entityType: 'channel',
        entityId: e.channelId,
        metadata: {'default_episode_id': e.id},
      );
      if (mounted) {
        showSuccess(
          context,
          '"${e.title}" is now playing on ${_channelName(e.channelId)}.',
        );
      }
      _load();
    } catch (ex) {
      if (mounted) showError(context, 'Failed to set as now playing.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminPageScaffold(
      title: 'Episodes',
      action: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          OutlinedButton.icon(
            onPressed: _openPlaylistImport,
            icon: const Icon(Icons.playlist_add),
            label: const Text('Import Playlist'),
          ),
          FilledButton.icon(
            onPressed: () => _openEditor(),
            icon: const Icon(Icons.add),
            label: const Text('New Episode'),
          ),
        ],
      ),
      child: _loading
          ? const LoadingBox()
          : _error != null
          ? ErrorBox(message: _error!, onRetry: _load)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _searchCtrl,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText:
                        'Search episodes by title, YouTube ID, or S/E number...',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) => setState(() => _search = v),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    SizedBox(
                      width: 180,
                      child: AdminFilterDropdown<String>(
                        value: _filterShowId,
                        label: 'Show',
                        options: _shows.map((s) => s.id).toList(),
                        itemLabel: (id) => _showTitle(id),
                        onChanged: (v) => setState(() => _filterShowId = v),
                      ),
                    ),
                    SizedBox(
                      width: 200,
                      child: AdminFilterDropdown<String>(
                        value: _filterChannelId,
                        label: 'Channel',
                        options: _channels.map((c) => c.id).toList(),
                        itemLabel: (id) => _channelName(id),
                        onChanged: (v) => setState(() => _filterChannelId = v),
                      ),
                    ),
                    SizedBox(
                      width: 160,
                      child: AdminFilterDropdown<String>(
                        value: _filterStatus,
                        label: 'Status',
                        options: const ['draft', 'published', 'disabled'],
                        itemLabel: (s) =>
                            s[0].toUpperCase() + s.substring(1),
                        onChanged: (v) => setState(() => _filterStatus = v),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => setState(() {
                        _searchCtrl.clear();
                        _search = '';
                        _filterShowId = null;
                        _filterChannelId = null;
                        _filterStatus = null;
                      }),
                      icon: const Icon(Icons.filter_alt_off, size: 16),
                      label: const Text('Clear'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: Card(
                    child: ResponsiveTableScroll(
                      child: DataTable(
                        columns: const [
                          DataColumn(label: Text('Episode')),
                          DataColumn(label: Text('Show')),
                          DataColumn(label: Text('S/E')),
                          DataColumn(label: Text('Channel')),
                          DataColumn(label: Text('Status')),
                          DataColumn(label: Text('Actions')),
                        ],
                        rows: _filtered.map((e) {
                    return DataRow(
                      cells: [
                        DataCell(Text(e.title)),
                        DataCell(Text(_showTitle(e.showId))),
                        DataCell(
                          Text('S${e.seasonNumber} E${e.episodeNumber ?? '-'}'),
                        ),
                        DataCell(Text(_channelName(e.channelId))),
                        DataCell(Text(e.status)),
                        DataCell(
                          Row(
                            children: [
                              IconButton(
                                icon: const Icon(
                                  Icons.play_circle_outline,
                                  size: 18,
                                ),
                                tooltip: 'Preview',
                                onPressed: () => _previewEpisode(e),
                              ),
                              IconButton(
                                icon: const Icon(Icons.live_tv, size: 18),
                                tooltip: 'Set as Now Playing on its channel',
                                onPressed: () => _setAsNowPlaying(e),
                              ),
                              IconButton(
                                icon: const Icon(Icons.edit, size: 18),
                                onPressed: () => _openEditor(episode: e),
                              ),
                              IconButton(
                                icon: const Icon(Icons.arrow_upward, size: 18),
                                tooltip: 'Move earlier in this channel\'s loop',
                                onPressed: () => _moveEpisode(e, -1),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.arrow_downward,
                                  size: 18,
                                ),
                                tooltip: 'Move later in this channel\'s loop',
                                onPressed: () => _moveEpisode(e, 1),
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

  void _previewEpisode(Episode e) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: const Color(0xFF14141A),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 440),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        e.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.close,
                        color: Colors.white54,
                        size: 18,
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              // Live auto-playing preview — verifies the video actually
              // plays automatically exactly as it will on the public TV,
              // matching the "admin add it, automatically plays" behavior.
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: ColoredBox(
                      color: Colors.black,
                      child: YoutubeScreenPlayer(
                        key: ValueKey('preview-${e.id}'),
                        videoId: e.youtubeVideoId,
                        volume: 60,
                        muted: false,
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  'YouTube ID: ${e.youtubeVideoId} · Auto-plays on the TV',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EpisodeEditorDialog extends StatefulWidget {
  final Episode? episode;
  final List<Show> shows;
  final List<Channel> channels;
  const _EpisodeEditorDialog({
    this.episode,
    required this.shows,
    required this.channels,
  });

  @override
  State<_EpisodeEditorDialog> createState() => _EpisodeEditorDialogState();
}

class _EpisodeEditorDialogState extends State<_EpisodeEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _titleCtrl;
  late TextEditingController _descCtrl;
  late TextEditingController _urlCtrl;
  late TextEditingController _seasonCtrl;
  late TextEditingController _episodeNumCtrl;
  late TextEditingController _durationCtrl;
  String? _showId;
  String? _channelId;
  String _status = 'draft';
  bool _enabled = true;
  bool _saving = false;
  String? _extractedId;
  String? _urlError;

  @override
  void initState() {
    super.initState();
    final e = widget.episode;
    _titleCtrl = TextEditingController(text: e?.title ?? '');
    _descCtrl = TextEditingController(text: e?.description ?? '');
    _urlCtrl = TextEditingController(
      text: e?.youtubeUrl ?? e?.youtubeVideoId ?? '',
    );
    _seasonCtrl = TextEditingController(
      text: e?.seasonNumber.toString() ?? '1',
    );
    _episodeNumCtrl = TextEditingController(
      text: e?.episodeNumber?.toString() ?? '',
    );
    _durationCtrl = TextEditingController(
      text: e?.durationSeconds?.toString() ?? '',
    );
    _showId = e?.showId;
    _channelId = e?.channelId;
    _status = e?.status ?? 'draft';
    _enabled = e?.enabled ?? true;
    _extractedId = e?.youtubeVideoId;
    _validateUrl(_urlCtrl.text);
  }

  void _validateUrl(String value) {
    final id = YoutubeUtils.extractVideoId(value);
    setState(() {
      _extractedId = id;
      _urlError = id == null && value.trim().isNotEmpty
          ? 'Unsupported or invalid YouTube URL/ID'
          : null;
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_extractedId == null) {
      setState(() => _urlError = 'A valid YouTube URL or video ID is required');
      return;
    }
    setState(() => _saving = true);
    try {
      final episode = Episode(
        id: widget.episode?.id ?? '',
        showId: _showId,
        channelId: _channelId,
        seasonNumber: int.tryParse(_seasonCtrl.text.trim()) ?? 1,
        episodeNumber: int.tryParse(_episodeNumCtrl.text.trim()),
        title: _titleCtrl.text.trim(),
        description: _descCtrl.text.trim().isEmpty
            ? null
            : _descCtrl.text.trim(),
        youtubeVideoId: _extractedId!,
        youtubeUrl: _urlCtrl.text.trim(),
        thumbnailUrl: YoutubeUtils.thumbnailUrl(_extractedId!),
        durationSeconds: int.tryParse(_durationCtrl.text.trim()),
        status: _status,
        enabled: _enabled,
        sortOrder: int.tryParse(_episodeNumCtrl.text.trim()) ?? 0,
      );

      if (widget.episode == null) {
        final id = await ContentService.createEpisode(episode);
        await ContentService.logAdminAction(
          'ADMIN_CREATED_EPISODE',
          entityType: 'episode',
          entityId: id,
        );

        // ---------------------------------------------------------------
        // Auto-link fix: newly created episodes were previously left
        // completely disconnected from "what actually plays" on their
        // channel — nothing set channels.default_episode_id or created a
        // channel_schedule row, so get_current_program() had nothing to
        // resolve and the public TV showed "Channel unavailable." for
        // every admin-added video. If this episode's channel doesn't
        // already have a default/"now playing" episode, wire it up
        // automatically so the content is immediately watchable.
        // ---------------------------------------------------------------
        if (_channelId != null) {
          final targetChannel = widget.channels.firstWhere(
            (c) => c.id == _channelId,
            orElse: () => widget.channels.first,
          );
          if (targetChannel.id == _channelId &&
              targetChannel.defaultEpisodeId == null) {
            try {
              await ContentService.updateChannel(_channelId!, {
                'default_episode_id': id,
              });
              await ContentService.logAdminAction(
                'ADMIN_UPDATED_CHANNEL',
                entityType: 'channel',
                entityId: _channelId,
                metadata: {'default_episode_id': id, 'auto_linked': true},
              );
            } catch (_) {
              // Non-fatal: episode was still created successfully; the
              // admin can use the "Set as Now Playing" action to link it.
            }
          }
        }
      } else {
        await ContentService.updateEpisode(
          widget.episode!.id,
          episode.toInsertMap(),
        );
        await ContentService.logAdminAction(
          'ADMIN_UPDATED_EPISODE',
          entityType: 'episode',
          entityId: widget.episode!.id,
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
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 650),
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
                    widget.episode == null ? 'New Episode' : 'Edit Episode',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _titleCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Episode Title',
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _urlCtrl,
                    decoration: InputDecoration(
                      labelText: 'YouTube URL or Video ID',
                      helperText: _extractedId != null
                          ? 'Detected ID: $_extractedId'
                          : null,
                      errorText: _urlError,
                    ),
                    onChanged: _validateUrl,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _descCtrl,
                    decoration: const InputDecoration(labelText: 'Description'),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _seasonCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Season #',
                          ),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _episodeNumCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Episode #',
                          ),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _durationCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Duration (sec)',
                          ),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _showId,
                    decoration: const InputDecoration(labelText: 'Show'),
                    items: widget.shows
                        .map(
                          (s) => DropdownMenuItem(
                            value: s.id,
                            child: Text(s.title),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setState(() => _showId = v),
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
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _status,
                    decoration: const InputDecoration(labelText: 'Status'),
                    items: const [
                      DropdownMenuItem(value: 'draft', child: Text('Draft')),
                      DropdownMenuItem(
                        value: 'published',
                        child: Text('Published'),
                      ),
                      DropdownMenuItem(
                        value: 'disabled',
                        child: Text('Disabled'),
                      ),
                    ],
                    onChanged: (v) => setState(() => _status = v ?? 'draft'),
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

class _PlaylistImportDialog extends StatefulWidget {
  final List<Channel> channels;
  final List<Show> shows;
  const _PlaylistImportDialog({required this.channels, required this.shows});

  @override
  State<_PlaylistImportDialog> createState() => _PlaylistImportDialogState();
}

class _PlaylistImportDialogState extends State<_PlaylistImportDialog> {
  final _urlCtrl = TextEditingController();
  String? _playlistId;
  String? _urlError;
  String? _channelId;
  String? _showId;
  bool _working = false;
  String? _progress;
  List<String> _errors = [];
  int _inserted = 0;
  int _updated = 0;

  @override
  void dispose() {
    _urlCtrl.dispose();
    super.dispose();
  }

  void _validateUrl(String value) {
    final id = YoutubeUtils.extractPlaylistId(value);
    setState(() {
      _playlistId = id;
      _urlError = id == null && value.trim().isNotEmpty
          ? 'Enter a YouTube playlist URL or a valid playlist ID '
                '(starts with PL..., like "PLabc123...")'
          : null;
    });
  }

  Future<void> _import() async {
    final playlistId = _playlistId;
    final channelId = _channelId;
    if (playlistId == null) {
      showError(context, 'Please enter a valid YouTube playlist URL/ID.');
      return;
    }
    if (channelId == null) {
      showError(context, 'Please pick the channel these episodes belong to.');
      return;
    }
    setState(() {
      _working = true;
      _errors = [];
      _progress = 'Fetching playlist…';
    });
    try {
      final items = await PlaylistImportService.fetchPlaylist(playlistId);
      if (!mounted) return;
      setState(() => _progress = 'Importing ${items.length} videos…');
      final results = await ContentService.importPlaylistVideos(
        channelId: channelId,
        playlistId: playlistId,
        defaultShowId: _showId,
        items: items,
      );
      await ContentService.logAdminAction(
        'ADMIN_IMPORTED_PLAYLIST',
        entityType: 'episode',
        metadata: {
          'playlist_id': playlistId,
          'channel_id': channelId,
          'total': results.length,
        },
      );
      if (!mounted) return;
      _inserted = results.where((r) => r.inserted).length;
      _updated = results.where((r) => !r.inserted && r.error == null).length;
      _errors = results
          .where((r) => r.error != null)
          .map((r) => '• ${r.title ?? 'Video'} — ${r.error}')
          .take(5)
          .toList();
      setState(() {
        _working = false;
        _progress = null;
      });
      if (_errors.isEmpty) {
        showSuccess(
          context,
          'Imported ${results.length} videos '
          '($_inserted new, $_updated updated).',
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _working = false;
        _progress = null;
      });
      showError(context, e.toString().replaceAll('Exception: ', ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Import YouTube Playlist',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Re-importing a playlist keeps it perfectly in sync: new '
                  'videos are added, existing ones updated, and runners '
                  'continue from where they left off. Videos play in '
                  'playlist order on their channel.',
                  style: TextStyle(color: Colors.white54, fontSize: 11),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _urlCtrl,
                  onChanged: _validateUrl,
                  decoration: InputDecoration(
                    labelText: 'Playlist URL or Playlist ID',
                    helperText: _playlistId != null
                        ? 'Detected playlist ID: $_playlistId'
                        : 'Example: https://www.youtube.com/playlist?list=PL…',
                    errorText: _urlError,
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _channelId,
                  decoration: const InputDecoration(labelText: 'Channel *'),
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
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _showId,
                  decoration: const InputDecoration(
                    labelText: 'Show (optional)',
                  ),
                  items: [
                    const DropdownMenuItem<String>(
                      value: null,
                      child: Text('No show'),
                    ),
                    ...widget.shows.map(
                      (s) =>
                          DropdownMenuItem(value: s.id, child: Text(s.title)),
                    ),
                  ],
                  onChanged: (v) => setState(() => _showId = v),
                ),
                const SizedBox(height: 16),
                if (_progress != null) ...[
                  Row(
                    children: [
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Text(_progress!)),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
                if (_errors.isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.redAccent),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Some videos were skipped:',
                          style: TextStyle(
                            color: Colors.redAccent,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 4),
                        ..._errors.map(
                          (e) => Padding(
                            padding: const EdgeInsets.only(bottom: 2),
                            child: Text(
                              e,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _working
                          ? null
                          : () => Navigator.of(context).pop(false),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: _working ? null : _import,
                      icon: const Icon(Icons.download),
                      label: Text(_working ? 'Importing…' : 'Import'),
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
