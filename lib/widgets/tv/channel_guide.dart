import 'package:flutter/material.dart';
import '../../models/channel.dart';
import '../../models/episode.dart';
import '../../services/content_service.dart';

/// Electronic program guide: lists all channels with their current
/// (and best-effort next) program. Tapping a row switches the TV to it.
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
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadPrograms();
  }

  Future<void> _loadPrograms() async {
    for (final c in widget.channels) {
      try {
        final ep = await ContentService.getCurrentProgram(c.id);
        _nowPlaying[c.id] = ep;
      } catch (_) {
        _nowPlaying[c.id] = null;
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 480),
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
                const Text(
                  'CHANNEL GUIDE',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          const Divider(color: Colors.white12, height: 1),
          Flexible(
            child: _loading
                ? const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: widget.channels.length,
                    separatorBuilder: (_, __) =>
                        const Divider(color: Colors.white10, height: 1),
                    itemBuilder: (context, i) {
                      final c = widget.channels[i];
                      final program = _nowPlaying[c.id];
                      return ListTile(
                        dense: true,
                        leading: Container(
                          width: 34,
                          height: 34,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: Colors.black26,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            c.channelNumber.toString().padLeft(2, '0'),
                            style: TextStyle(
                              color: widget.accentColor,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                        title: Text(
                          c.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        subtitle: Text(
                          program != null
                              ? 'NOW: ${program.title}'
                              : 'NOW: Off-air',
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
