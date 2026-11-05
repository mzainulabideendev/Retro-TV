import 'package:flutter/material.dart';
import '../../models/channel.dart';
import '../../models/channel_language.dart';
import '../../models/episode.dart';
import '../../services/content_service.dart';
import 'channel_logo.dart';

/// Electronic program guide: lists all channels with their current
/// (and best-effort next) program. Tapping a row switches the TV to it.
///
/// Includes a search box and a language filter so viewers can quickly find
/// a channel and pick cartoons uploaded in their own language.
///
/// Performance: all channel programs are fetched in parallel via
/// [ContentService.getCurrentProgramsForChannels] so the guide opens
/// instantly even with dozens of channels. The channel list renders
/// immediately with "Loading..." placeholders that update as each
/// program resolves.
class ChannelGuide extends StatefulWidget {
  final List<Channel> channels;
  final void Function(Channel) onSelect;
  final Color accentColor;

  const ChannelGuide({
    super.key,
    required this.channels,
    required this.onSelect,
    required this.accentColor,
  });

  @override
  State<ChannelGuide> createState() => _ChannelGuideState();
}

class _ChannelGuideState extends State<ChannelGuide> {
  final Map<String, Episode?> _nowPlaying = {};
  final TextEditingController _searchController = TextEditingController();
  bool _programsLoaded = false;
  String _search = '';
  String? _language;

  @override
  void initState() {
    super.initState();
    _loadPrograms();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadPrograms() async {
    final results = await ContentService.getCurrentProgramsForChannels(
      widget.channels,
    );
    if (!mounted) return;
    setState(() {
      _nowPlaying.addAll(results);
      _programsLoaded = true;
    });
  }

  /// Languages that actually occur on the loaded channels, so the filter
  /// never offers an empty option. Known languages sort by their label;
  /// anything unrecognised goes last.
  List<ChannelLanguage> get _availableLanguages {
    final codes = <String>{};
    for (final channel in widget.channels) {
      final code = channel.language?.trim().toLowerCase();
      if (code != null && code.isNotEmpty) codes.add(code);
    }
    final languages =
        channelLanguages
            .where((language) => codes.contains(language.code))
            .toList()
          ..sort((a, b) => a.label.compareTo(b.label));
    final unknown =
        codes.where((code) => !isKnownChannelLanguage(code)).toList()..sort();
    return [
      ...languages,
      ...unknown.map(
        (code) => ChannelLanguage(code, channelLanguageLabel(code)),
      ),
    ];
  }

  List<Channel> get _filteredChannels {
    final query = _search.trim().toLowerCase();
    return widget.channels.where((channel) {
      final language = channel.language?.trim().toLowerCase();
      final matchesLanguage = _language == null || language == _language;
      if (!matchesLanguage) return false;

      if (query.isEmpty) return true;
      final label = channelLanguageLabel(channel.language).toLowerCase();
      return channel.name.toLowerCase().contains(query) ||
          channel.channelNumber.toString().contains(query) ||
          channel.channelType
              .replaceAll('_', ' ')
              .toLowerCase()
              .contains(query) ||
          label.contains(query) ||
          (channel.description?.toLowerCase().contains(query) ?? false);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final languages = _availableLanguages;
    final filtered = _filteredChannels;
    // Keep the selected language valid if channels reload without it
    // (fall back to "All languages" for this build instead of showing a
    // value the dropdown can no longer offer).
    final selectedLanguage =
        _language != null &&
            languages.any((language) => language.code == _language)
        ? _language
        : null;

    return Container(
      constraints: const BoxConstraints(maxHeight: 520),
      decoration: BoxDecoration(
        color: const Color(0xFF14141A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Row(
              children: [
                Icon(Icons.grid_view, color: widget.accentColor, size: 18),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'CHANNEL GUIDE',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                      fontSize: 14,
                    ),
                  ),
                ),
                Text(
                  '${filtered.length}/${widget.channels.length}',
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              cursorColor: widget.accentColor,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Search channels, numbers, languages...',
                hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                prefixIcon: Icon(
                  Icons.search,
                  color: widget.accentColor,
                  size: 18,
                ),
                suffixIcon: _search.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        icon: const Icon(
                          Icons.close,
                          color: Colors.white38,
                          size: 16,
                        ),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _search = '');
                        },
                      ),
                filled: true,
                fillColor: Colors.black26,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Colors.white12),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Colors.white12),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: widget.accentColor),
                ),
              ),
              onChanged: (value) => setState(() => _search = value),
            ),
          ),
          if (languages.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Row(
                children: [
                  const Icon(Icons.translate, color: Colors.white38, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String?>(
                        value: selectedLanguage,
                        isDense: true,
                        isExpanded: true,
                        dropdownColor: const Color(0xFF1E1E24),
                        icon: const Icon(
                          Icons.arrow_drop_down,
                          color: Colors.white54,
                        ),
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('All languages'),
                          ),
                          ...languages.map(
                            (language) => DropdownMenuItem<String?>(
                              value: language.code,
                              child: Text(language.label),
                            ),
                          ),
                        ],
                        onChanged: (value) => setState(() => _language = value),
                      ),
                    ),
                  ),
                  if (selectedLanguage != null)
                    TextButton(
                      style: TextButton.styleFrom(
                        minimumSize: const Size(0, 28),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      onPressed: () => setState(() => _language = null),
                      child: const Text(
                        'Clear',
                        style: TextStyle(fontSize: 11),
                      ),
                    ),
                ],
              ),
            ),
          const Divider(color: Colors.white12, height: 1),
          Flexible(
            child: filtered.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 24,
                    ),
                    child: Text(
                      widget.channels.isEmpty
                          ? 'No channels available.'
                          : 'No channels match "${_search.trim()}".',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) =>
                        const Divider(color: Colors.white10, height: 1),
                    itemBuilder: (context, i) {
                      final c = filtered[i];
                      final program = _nowPlaying[c.id];
                      final subtitle = !_programsLoaded
                          ? 'NOW: Loading...'
                          : program != null
                          ? 'NOW: ${program.title}'
                          : 'NOW: Off-air';
                      final logoUrl = c.logoUrl?.trim();
                      return ListTile(
                        // Identity keys let Flutter move/dispose the right
                        // row when the guide is filtered.
                        key: ValueKey('channel-guide-row-${c.id}'),
                        dense: true,
                        leading: SizedBox(
                          width: 44,
                          height: 38,
                          child: logoUrl == null || logoUrl.isEmpty
                              ? const Icon(Icons.tv, color: Colors.white54)
                              : ChannelLogo(
                                  channelId: c.id,
                                  url: logoUrl,
                                  width: 44,
                                  height: 38,
                                ),
                        ),
                        title: Row(
                          children: [
                            Text(
                              c.channelNumber.toString().padLeft(2, '0'),
                              style: TextStyle(
                                color: widget.accentColor,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'monospace',
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                c.name,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            if (c.language != null &&
                                c.language!.trim().isNotEmpty)
                              Container(
                                margin: const EdgeInsets.only(left: 6),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: widget.accentColor.withValues(
                                    alpha: 0.15,
                                  ),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  channelLanguageLabel(c.language),
                                  style: TextStyle(
                                    color: widget.accentColor,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        subtitle: Text(
                          subtitle,
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 11,
                          ),
                        ),
                        enabled: c.enabled,
                        onTap: c.enabled ? () => widget.onSelect(c) : null,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
