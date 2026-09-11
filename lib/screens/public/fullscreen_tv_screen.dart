import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../services/tv_state.dart';
import '../../widgets/tv/youtube_screen_player.dart';
import '../../widgets/tv/static_noise.dart';
import '../../widgets/tv/crt_overlay.dart';

/// Full-screen, edge-to-edge TV viewing mode. The video fills the whole
/// screen (letterboxed to preserve aspect ratio) with a minimal CRT
/// overlay and a tap-to-reveal control strip — like a real TV's
/// fullscreen/theater mode. Hardware back button / Escape / the exit
/// button all return to the normal TV-cabinet view.
class FullscreenTvScreen extends StatefulWidget {
  const FullscreenTvScreen({super.key});

  @override
  State<FullscreenTvScreen> createState() => _FullscreenTvScreenState();
}

class _FullscreenTvScreenState extends State<FullscreenTvScreen> {
  final FocusNode _focusNode = FocusNode();
  bool _showOverlay = true;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _focusNode.requestFocus(),
    );
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _focusNode.dispose();
    super.dispose();
  }

  void _exit(TvState tv) {
    tv.setFullscreen(false);
    Navigator.of(context).pop();
  }

  void _handleKey(KeyEvent event, TvState tv) {
    if (event is! KeyDownEvent) return;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.escape:
      case LogicalKeyboardKey.keyF:
        _exit(tv);
        break;
      case LogicalKeyboardKey.arrowUp:
        tv.channelUp();
        break;
      case LogicalKeyboardKey.arrowDown:
        tv.channelDown();
        break;
      case LogicalKeyboardKey.arrowLeft:
        tv.volumeDown();
        break;
      case LogicalKeyboardKey.arrowRight:
        tv.volumeUp();
        break;
      case LogicalKeyboardKey.keyM:
        tv.toggleMute();
        break;
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<TvState>(
      builder: (context, tv, _) {
        return PopScope(
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) {
              SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
              tv.setFullscreen(false);
            }
          },
          child: KeyboardListener(
            focusNode: _focusNode,
            autofocus: true,
            onKeyEvent: (e) => _handleKey(e, tv),
            child: Scaffold(
              backgroundColor: Colors.black,
              body: GestureDetector(
                onTap: () => setState(() => _showOverlay = !_showOverlay),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Center(
                      child: AspectRatio(
                        aspectRatio: 4 / 3,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Container(color: Colors.black),
                            if (tv.currentProgram != null &&
                                !tv.channelChanging)
                              YoutubeScreenPlayer(
                                key: ValueKey('${tv.currentProgram!.id}-fs'),
                                videoId: tv.currentProgram!.youtubeVideoId,
                                volume: tv.effectiveVolume,
                                muted: tv.muted,
                                onEnded: tv.onProgramEnded,
                              ),
                            StaticNoise(active: tv.channelChanging),
                            CrtOverlay(
                              scanlineOpacity: tv.reduceEffects
                                  ? 0.06
                                  : (tv.currentStyle?.scanlineOpacity ?? 0.15),
                              glowColor:
                                  tv.currentStyle?.glowColor ??
                                  Colors.cyanAccent,
                              reduceMotion: tv.reduceEffects,
                              enabled: true,
                            ),
                          ],
                        ),
                      ),
                    ),
                    AnimatedOpacity(
                      opacity: _showOverlay ? 1 : 0,
                      duration: const Duration(milliseconds: 250),
                      child: IgnorePointer(
                        ignoring: !_showOverlay,
                        child: SafeArea(
                          child: Column(
                            children: [
                              _topBar(tv),
                              const Spacer(),
                              _bottomBar(tv),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _topBar(TvState tv) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: Colors.black.withValues(alpha: 0.55),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.fullscreen_exit, color: Colors.white),
            onPressed: () => _exit(tv),
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

  Widget _bottomBar(TvState tv) {
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
