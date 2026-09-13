import 'package:flutter/material.dart';
import '../../services/tv_state.dart';
import 'crt_overlay.dart';
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
  @override
  Widget build(BuildContext context) {
    final style = widget.tv.currentStyle;
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
                  AbsorbPointer(child: widget.screen),
                  StaticNoise(active: widget.tv.channelChanging),
                  CrtOverlay(
                    scanlineOpacity: widget.tv.reduceEffects
                        ? 0.06
                        : (style?.scanlineOpacity ?? 0.15),
                    glowColor: style?.glowColor ?? Colors.cyanAccent,
                    reduceMotion: widget.tv.reduceEffects,
                    enabled: true,
                  ),
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