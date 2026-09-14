import 'package:flutter/material.dart';
import '../../models/screen_filter.dart';
import '../../services/tv_state.dart';
import 'static_noise.dart';

/// Fullscreen TV viewing mode rendered IN PLACE (no separate route), so the
/// app can keep a *single* shared player instance. Passing the live player
/// in as [screen] lets playback continue uninterrupted while the rest of
/// the UI (channel label, volume, controls) is overlaid on top — exactly
/// like a real TV's fullscreen/theater mode.
///
/// Key handling is owned by the hosting screen (HomeScreen), so channel /
/// volume / mute / exit shortcuts keep working without a second
/// KeyboardListener.
class FullscreenTvView extends StatefulWidget {
  final TvState tv;
  final Widget screen;
  final VoidCallback onExit;

  const FullscreenTvView({
    super.key,
    required this.tv,
    required this.screen,
    required this.onExit,
  });

  @override
  State<FullscreenTvView> createState() => _FullscreenTvViewState();
}

class _FullscreenTvViewState extends State<FullscreenTvView> {
  Future<void> _pickFilter() async {
    final tv = widget.tv;
    if (!tv.isOn) return;
    final picked = await showModalBottomSheet<ScreenFilter>(
      context: context,
      backgroundColor: const Color(0xFF1C1C22),
      builder: (sheetContext) {
        return ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 12),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Text(
                'Screen Filter',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            for (final f in ScreenFilter.values)
              ListTile(
                leading: Icon(f.icon, color: Colors.white70),
                title: Text(f.label, style: const TextStyle(color: Colors.white)),
                subtitle: Text(
                  f.description,
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
                trailing: tv.screenFilter == f
                    ? Icon(Icons.check_circle, color: tv.currentStyle?.accentColor)
                    : null,
                onTap: () => Navigator.of(sheetContext).pop(f),
              ),
          ],
        );
      },
    );
    if (picked != null && mounted) {
      await widget.tv.selectScreenFilter(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filter = widget.tv.screenFilter;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: AspectRatio(
              aspectRatio: 4 / 3,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Container(color: Colors.black),
                  // The picture itself is inert: tapping it can never skip,
                  // pause, overlay, or trigger the embedded player's own
                  // controls. Navigation lives on the remote-style bars above
                  // and below, like a real TV.
                  AbsorbPointer(
                    child: _applyColorGrade(widget.screen, filter),
                  ),
                  StaticNoise(active: widget.tv.channelChanging),
                ],
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                _topBar(),
                const Spacer(),
                _bottomBar(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Applies the filter's exact color grade to Flutter-rendered picture
  /// content (native). On web the YouTube iframe is an external platform
  /// view Flutter cannot repaint — the CrtOverlay tint wash (rendered
  /// inside the player, see YoutubeScreenPlayer.crtOverlay) carries the
  /// grade on top instead.
  Widget _applyColorGrade(Widget child, ScreenFilter filter) {
    final matrix = filter.matrix;
    if (matrix == null) return child;
    return ColorFiltered(
      colorFilter: ColorFilter.matrix(matrix),
      child: child,
    );
  }

  Widget _topBar() {
    final tv = widget.tv;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: Colors.black.withValues(alpha: 0.55),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.fullscreen_exit, color: Colors.white),
            onPressed: widget.onExit,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'CH ${tv.currentChannel?.channelNumber.toString().padLeft(2, '0') ?? '--'}  ·  ${tv.currentChannel?.name ?? ''}',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.tune, color: Colors.white),
            tooltip: 'Screen filter',
            onPressed: _pickFilter,
          ),
        ],
      ),
    );
  }

  Widget _bottomBar() {
    final tv = widget.tv;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: Colors.black.withValues(alpha: 0.55),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_up, color: Colors.white),
            tooltip: 'Channel up',
            onPressed: tv.channelUp,
          ),
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white),
            tooltip: 'Channel down',
            onPressed: tv.channelDown,
          ),
          const SizedBox(width: 12),
          IconButton(
            icon: Icon(
              tv.muted ? Icons.volume_off : Icons.volume_up,
              color: Colors.white,
            ),
            onPressed: tv.toggleMute,
          ),
          Expanded(
            child: Slider(
              value: tv.effectiveVolume.toDouble(),
              min: 0,
              max: 100,
              onChanged: (v) => tv.setVolume(v.round()),
            ),
          ),
          Text(
            '${tv.effectiveVolume}',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }
}