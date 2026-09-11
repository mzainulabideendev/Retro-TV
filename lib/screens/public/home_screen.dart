import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../services/tv_state.dart';
import '../../widgets/tv/crt_tv_frame.dart';
import '../../widgets/tv/tv_controls.dart';
import '../../widgets/tv/channel_guide.dart';
import '../../widgets/tv/tv_style_selector.dart';
import '../../widgets/tv/youtube_screen_player.dart';
import '../admin/admin_login_screen.dart';
import 'about_screen.dart';
import 'fullscreen_tv_screen.dart';

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<TvState>().initialize();
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
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
        _openFullscreen(tv);
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

  Future<void> _openFullscreen(TvState tv) async {
    if (!tv.isOn) return;
    tv.setFullscreen(true);
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const FullscreenTvScreen(),
        fullscreenDialog: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<TvState>(
      builder: (context, tv, _) {
        return KeyboardListener(
          focusNode: _focusNode,
          autofocus: true,
          onKeyEvent: (e) => _handleKey(e, tv),
          child: Scaffold(
            backgroundColor: const Color(0xFF0D0D10),
            body: SafeArea(
              child: tv.loading
                  ? const Center(child: CircularProgressIndicator())
                  : tv.error != null
                  ? _buildError(tv)
                  : _buildContent(context, tv),
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
          const SizedBox(height: 16),
          GestureDetector(
            onDoubleTap: () => _openFullscreen(tv),
            child: CrtTvFrame(
              style: style,
              poweredOn: tv.isOn,
              startingUp: tv.power == PowerState.startingUp,
              channelChanging: tv.channelChanging,
              reduceEffects: tv.reduceEffects,
              channelNumber: tv.currentChannel?.channelNumber ?? 0,
              channelName: tv.currentChannel?.name ?? '',
              digitBuffer: tv.digitBuffer,
              volume: tv.effectiveVolume,
              muted: tv.muted,
              showVolumeOsd: _showVolumeOsd,
              screenChild: _buildScreenContent(tv),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tip: double-tap the screen (or press F) for fullscreen',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.3),
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 12),
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
    // playing the instant its channel is tuned in.
    return YoutubeScreenPlayer(
      key: ValueKey(program.id),
      videoId: program.youtubeVideoId,
      volume: tv.effectiveVolume,
      muted: tv.muted,
      onEnded: tv.onProgramEnded,
      onUnavailable: tv.onProgramUnavailable,
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
