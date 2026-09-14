import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../services/tv_state.dart';
import '../../widgets/tv/crt_overlay.dart';
import '../../widgets/tv/crt_tv_frame.dart';
import '../../widgets/tv/tv_controls.dart';
import '../../widgets/tv/channel_guide.dart';
import '../../widgets/tv/next_up_card.dart';
import '../../widgets/tv/tv_style_selector.dart';
import '../../widgets/tv/tv_filter_selector.dart';
import '../../widgets/tv/tv_loading_view.dart';
import '../../widgets/tv/youtube_screen_player.dart';
import '../admin/admin_login_screen.dart';
import 'about_screen.dart';
import '../../widgets/tv/fullscreen_tv_view.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final FocusNode _focusNode = FocusNode();
  bool _showGuide = false;
  bool _showVolumeOsd = false;
  Timer? _osdTimer;

  TvState? _tv;

  /// The single youtube player instance is shared between the small CRT
  /// screen and the fullscreen view. Reparenting it through this key (with
  /// the GlobalKey) keeps playback running uninterrupted across both modes
  /// instead of creating a second player that plays alongside the first.
  final GlobalKey _playerKey = GlobalKey();

  /// Playback position (ms) reported by whichever player surface is active.
  /// Handed back to the next surface (small screen <-> fullscreen) so the
  /// video continues at the same time & duration instead of restarting.
  int _lastPlayerPositionMs = 0;

  /// Tracks the program the saved position belongs to — any position travels
  /// only within one episode and resets to 0 when the episode changes.
  String? _lastProgramId;

  void _syncProgramPosition(TvState tv) {
    final programId = tv.currentProgram?.id;
    if (programId != _lastProgramId) {
      _lastProgramId = programId;
      _lastPlayerPositionMs = 0;
    }
  }

  void _capturePlayerPosition(int ms) {
    _lastPlayerPositionMs = ms;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final tv = context.read<TvState>();
      _tv = tv;
      tv.addListener(_syncFullscreenSystemUi);
      tv.initialize();
      _focusNode.requestFocus();
    });
  }

  void _syncFullscreenSystemUi() {
    final tv = _tv;
    if (tv == null) return;
    SystemChrome.setEnabledSystemUIMode(
      tv.fullscreen ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    );
  }

  @override
  void dispose() {
    _tv?.removeListener(_syncFullscreenSystemUi);
    _focusNode.dispose();
    _osdTimer?.cancel();
    super.dispose();
  }

  void _flashVolumeOsd() {
    setState(() => _showVolumeOsd = true);
    _osdTimer?.cancel();
    _osdTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _showVolumeOsd = false);
    });
  }

  void _handleKey(KeyEvent event, TvState tv) {
    if (event is! KeyDownEvent) return;
    // Digit keys 0-9 buffer a channel number, just like the on-screen pad.
    final digit = _digitFromKey(event.logicalKey);
    if (digit != null) {
      tv.pressDigit(digit);
      return;
    }
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowUp:
        tv.channelUp();
        break;
      case LogicalKeyboardKey.arrowDown:
        tv.channelDown();
        break;
      case LogicalKeyboardKey.arrowLeft:
        tv.volumeDown();
        _flashVolumeOsd();
        break;
      case LogicalKeyboardKey.arrowRight:
        tv.volumeUp();
        _flashVolumeOsd();
        break;
      case LogicalKeyboardKey.keyM:
        tv.toggleMute();
        _flashVolumeOsd();
        break;
      case LogicalKeyboardKey.keyF:
      case LogicalKeyboardKey.escape:
        if (tv.fullscreen) {
          tv.setFullscreen(false);
        } else {
          _openFullscreen(tv);
        }
        break;
      case LogicalKeyboardKey.keyP:
        tv.togglePower();
        break;
      case LogicalKeyboardKey.keyG:
        setState(() => _showGuide = !_showGuide);
        break;
      case LogicalKeyboardKey.enter:
        tv.confirmDigits();
        break;
      default:
        break;
    }
  }

  int? _digitFromKey(LogicalKeyboardKey key) {
    final map = {
      LogicalKeyboardKey.digit0: 0,
      LogicalKeyboardKey.digit1: 1,
      LogicalKeyboardKey.digit2: 2,
      LogicalKeyboardKey.digit3: 3,
      LogicalKeyboardKey.digit4: 4,
      LogicalKeyboardKey.digit5: 5,
      LogicalKeyboardKey.digit6: 6,
      LogicalKeyboardKey.digit7: 7,
      LogicalKeyboardKey.digit8: 8,
      LogicalKeyboardKey.digit9: 9,
    };
    return map[key];
  }

  void _openFullscreen(TvState tv) {
    if (!tv.isOn) return;
    tv.setFullscreen(true);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<TvState>(
      builder: (context, tv, _) {
        return PopScope(
          canPop: !(tv.fullscreen && tv.isOn),
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && tv.fullscreen) tv.setFullscreen(false);
          },
          child: KeyboardListener(
            focusNode: _focusNode,
            autofocus: true,
            onKeyEvent: (e) => _handleKey(e, tv),
            child: Scaffold(
              backgroundColor: const Color(0xFF0D0D10),
              body: SafeArea(
                child: tv.loading
                    ? const TvLoadingView()
                    : tv.error != null
                    ? _buildError(tv)
                    : tv.fullscreen && tv.isOn
                    ? _buildFullscreenLayout(context, tv)
                    : _buildContent(context, tv),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildError(TvState tv) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.redAccent, size: 40),
            const SizedBox(height: 12),
            Text(
              tv.error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: tv.initialize,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, TvState tv) {
    final style = tv.currentStyle;
    if (style == null || tv.channels.isEmpty) {
      return const Center(
        child: Text(
          'No channels available.',
          style: TextStyle(color: Colors.white70),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        children: [
          _buildHeader(context),
          const SizedBox(height: 12),
          TvStyleSelector(
            styles: tv.tvStyles,
            selected: tv.currentStyle,
            onSelect: tv.selectStyle,
          ),
          const SizedBox(height: 12),
          Text(
            'SCREEN FILTER',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.4),
              fontSize: 10,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 6),
          TvFilterSelector(
            selected: tv.screenFilter,
            accentColor: style.accentColor,
            onSelect: tv.selectScreenFilter,
          ),
          const SizedBox(height: 16),
          CrtTvFrame(
              style: style,
              poweredOn: tv.isOn,
              startingUp: tv.power == PowerState.startingUp,
              channelChanging: tv.channelChanging,
              reduceEffects: tv.reduceEffects,
              screenFilter: tv.screenFilter,
              channelNumber: tv.currentChannel?.channelNumber ?? 0,
              channelName: tv.currentChannel?.name ?? '',
              digitBuffer: tv.digitBuffer,
              volume: tv.effectiveVolume,
              muted: tv.muted,
              showVolumeOsd: _showVolumeOsd,
              screenChild: _buildScreenContent(tv),
            ),
          const SizedBox(height: 8),
          Text(
            'Tip: use the remote controls (or press F) for fullscreen',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.3),
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 12),
          if (tv.isOn &&
              tv.currentChannel != null &&
              (tv.upNext != null || tv.nextScheduledProgram != null)) ...[
            NextUpCard(
              upNext: tv.upNext,
              announcement: tv.nextScheduledProgram,
              accentColor: style.accentColor,
            ),
            const SizedBox(height: 12),
          ],
          _buildProgramInfo(tv, style),
          const SizedBox(height: 16),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: TvControls(
              tv: tv,
              accentColor: style.accentColor,
              onGuide: () => setState(() => _showGuide = !_showGuide),
              onFullscreen: () => _openFullscreen(tv),
              onVolumeChanged: _flashVolumeOsd,
            ),
          ),
          const SizedBox(height: 16),
          if (_showGuide)
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: ChannelGuide(
                channels: tv.channels,
                accentColor: style.accentColor,
                onSelect: (c) {
                  tv.selectChannel(c);
                  setState(() => _showGuide = false);
                },
              ),
            ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton.icon(
                onPressed: () => Navigator.of(
                  context,
                ).push(MaterialPageRoute(builder: (_) => const AboutScreen())),
                icon: const Icon(
                  Icons.info_outline,
                  color: Colors.white38,
                  size: 16,
                ),
                label: const Text(
                  'About',
                  style: TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AdminLoginScreen()),
                ),
                icon: const Icon(
                  Icons.admin_panel_settings,
                  color: Colors.white38,
                  size: 16,
                ),
                label: const Text(
                  'Admin',
                  style: TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Column(
      children: [
        Text(
          'RETRO TV',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.9),
            fontSize: 26,
            fontWeight: FontWeight.bold,
            letterSpacing: 4,
          ),
        ),
        Text(
          'Watch Classic Television',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.4),
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildScreenContent(TvState tv) {
    _syncProgramPosition(tv);
    if (!tv.isOn || tv.power != PowerState.on) {
      return const SizedBox.shrink();
    }
    final program = tv.currentProgram;
    if (tv.channelChanging) {
      return const SizedBox.shrink();
    }
    if (program == null) {
      return Container(
        color: Colors.black,
        alignment: Alignment.center,
        child: const Text(
          'Channel unavailable.',
          style: TextStyle(color: Colors.white54, fontSize: 12),
        ),
      );
    }
    // Video plays automatically — no user interaction required. Autoplay
    // is guaranteed via a muted-start-then-auto-unmute strategy inside
    // YoutubeScreenPlayer, so every episode added by an admin starts
    // playing the instant its channel is tuned in. The player is the
    // SAME shared instance used by fullscreen (see [_playerKey]); should
    // the surface be recreated instead of reparented, it resumes from
    // [_lastPlayerPositionMs] so the video does not restart at 0:00.
    return YoutubeScreenPlayer(
      key: _playerKey,
      videoId: program.youtubeVideoId,
      volume: tv.effectiveVolume,
      muted: tv.muted,
      initialPositionMs: _lastPlayerPositionMs,
      onPositionChanged: _capturePlayerPosition,
      onEnded: tv.onProgramEnded,
      onUnavailable: tv.onProgramUnavailable,
      crtOverlay: _buildCrtOverlay(tv),
    );
  }

  Widget _buildFullscreenLayout(BuildContext context, TvState tv) {
    return FullscreenTvView(
      tv: tv,
      screen: _buildFullscreenScreen(tv),
      onExit: () => tv.setFullscreen(false),
    );
  }

  Widget _buildFullscreenScreen(TvState tv) {
    _syncProgramPosition(tv);
    if (!tv.isOn || tv.power != PowerState.on) {
      return const SizedBox.shrink();
    }
    if (tv.channelChanging) {
      return const SizedBox.shrink();
    }
    final program = tv.currentProgram;
    if (program == null) {
      return Container(
        color: Colors.black,
        alignment: Alignment.center,
        child: const Text(
          'Channel unavailable.',
          style: TextStyle(color: Colors.white54, fontSize: 12),
        ),
      );
    }
    // Same shared instance as the small screen — no second player, so the
    // video continues from its current position instead of starting over.
    // If the platform rebuilds the player surface on the swap, it seeks to
    // [_lastPlayerPositionMs] first and keeps the same time & duration.
    return YoutubeScreenPlayer(
      key: _playerKey,
      videoId: program.youtubeVideoId,
      volume: tv.effectiveVolume,
      muted: tv.muted,
      initialPositionMs: _lastPlayerPositionMs,
      onPositionChanged: _capturePlayerPosition,
      onEnded: tv.onProgramEnded,
      onUnavailable: tv.onProgramUnavailable,
      crtOverlay: _buildCrtOverlay(tv),
    );
  }

  /// Builds the CRT screen picture filter overlay. This is passed to the
  /// shared [YoutubeScreenPlayer] which renders it through the YouTube
  /// plugin's [YoutubePlayer.controlsBuilder] — placing it INSIDE the
  /// plugin's overlay layer, above the WebView, on every platform. (A copy
  /// of the old frame-level overlay would be invisible on Android/iOS.)
  CrtOverlay _buildCrtOverlay(TvState tv) {
    final style = tv.currentStyle;
    return CrtOverlay(
      scanlineOpacity: tv.reduceEffects
          ? 0.06
          : (style?.scanlineOpacity ?? 0.15),
      glowColor: style?.glowColor ?? Colors.cyanAccent,
      reduceMotion: tv.reduceEffects,
      enabled: true,
      filter: tv.screenFilter,
    );
  }

  Widget _buildProgramInfo(TvState tv, dynamic style) {
    final channel = tv.currentChannel;
    final program = tv.currentProgram;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF14141A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tv.isOn ? (channel?.name ?? '—') : 'Standby',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    tv.isOn
                        ? (program?.title ?? 'No program')
                        : 'Press POWER to turn on',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(
              tv.muted ? Icons.volume_off : Icons.volume_up,
              color: Colors.white38,
              size: 16,
            ),
            const SizedBox(width: 4),
            Text(
              '${tv.effectiveVolume}',
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
