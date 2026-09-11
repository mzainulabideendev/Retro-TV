import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

/// Wraps the official YouTube iframe player so it visually appears
/// integrated into the TV screen rather than looking like a YouTube
/// embed. Handles autoplay-blocked / unavailable-video states.
///
/// AUTOPLAY STRATEGY: Browsers (and some platforms) block autoplay with
/// sound. To guarantee the video *always* starts playing automatically
/// like a real TV channel (per product requirement), we always start the
/// player MUTED (which browsers universally allow to autoplay), then as
/// soon as playback is confirmed to have started we programmatically
/// unmute and apply the real volume. Because some browsers silently
/// re-mute (or ignore) the very first unmute() call right after an
/// autoplay sequence, we don't just fire-and-forget the unmute — we run
/// a short-lived verification loop that actively reads back the
/// player's real `isMuted` / `volume` state via the JS bridge and keeps
/// correcting it until it actually matches what the TV wants, or a
/// generous attempt budget is exhausted. This guarantees audio reliably
/// comes on together with the video, without ever requiring a user tap.
class YoutubeScreenPlayer extends StatefulWidget {
  final String videoId;
  final int volume; // 0-100
  final bool muted;
  final VoidCallback? onEnded;
  final VoidCallback? onUnavailable;

  const YoutubeScreenPlayer({
    super.key,
    required this.videoId,
    required this.volume,
    required this.muted,
    this.onEnded,
    this.onUnavailable,
  });

  @override
  State<YoutubeScreenPlayer> createState() => _YoutubeScreenPlayerState();
}

class _YoutubeScreenPlayerState extends State<YoutubeScreenPlayer> {
  late YoutubePlayerController _controller;
  bool _unavailable = false;
  bool _disposed = false;
  bool _playbackStarted = false;
  bool _unavailableNotified = false;
  Timer? _playbackWatchdog;
  int _audioSyncToken = 0;

  @override
  void initState() {
    super.initState();
    _createController();
  }

  void _createController() {
    _controller = YoutubePlayerController.fromVideoId(
      videoId: widget.videoId,
      autoPlay: true,
      params: const YoutubePlayerParams(
        showControls: false,
        showFullscreenButton: false,
        enableJavaScript: true,
        strictRelatedVideos: true,
        // Always start muted so the browser/OS never blocks autoplay.
        mute: true,
        playsInline: true,
        enableCaption: false,
        loop: false,
      ),
    );

    _controller.listen((event) {
      if (event.playerState == PlayerState.ended) {
        widget.onEnded?.call();
      }
      if (event.error != YoutubeError.none) {
        _markUnavailable('YouTube error ${event.error.code}');
      }
      // As soon as the player reports *any* active state (buffering,
      // cued or playing) it means the underlying iframe/JS bridge is
      // alive and ready to accept commands — kick off the audio sync
      // loop. We don't wait strictly for "playing" because some
      // browsers fire buffering repeatedly and skip straight to
      // playing without a clean single transition.
      if (event.playerState == PlayerState.playing ||
          event.playerState == PlayerState.buffering) {
        if (event.playerState == PlayerState.playing) {
          _playbackStarted = true;
          _playbackWatchdog?.cancel();
        }
        _startAudioSync();
      }
    });

    // Kick playback immediately; also acts as a safety net in case the
    // autoPlay param is ignored on some platforms.
    _controller.playVideo();

    // Unconditional fallback: start the sync loop shortly after creation
    // regardless of whether a usable player-state event ever arrives, so
    // the channel never stays muted/silent forever.
    Future.delayed(const Duration(milliseconds: 700), _startAudioSync);

    // Android WebView can show YouTube's internal "This video is unavailable"
    // screen (for example error 152-4 for videos that are blocked from embeds)
    // without surfacing a clean iframe API error. If playback never actually
    // starts, hide the native YouTube error screen and ask TvState to skip to
    // another playable episode/channel.
    _playbackWatchdog?.cancel();
    _playbackWatchdog = Timer(const Duration(seconds: 8), () {
      if (!_playbackStarted) {
        _markUnavailable('Playback did not start');
      }
    });
  }

  void _markUnavailable(String reason) {
    if (_disposed || _unavailableNotified) return;
    _unavailableNotified = true;
    if (kDebugMode) debugPrint('YoutubeScreenPlayer unavailable: $reason');
    _playbackWatchdog?.cancel();
    try {
      _controller.pauseVideo();
    } catch (_) {
      // Ignore controller shutdown/race errors.
    }
    if (mounted) setState(() => _unavailable = true);
    Future<void>.delayed(const Duration(milliseconds: 900), () {
      if (!_disposed) widget.onUnavailable?.call();
    });
  }

  /// Actively polls the player's real mute/volume state and re-applies
  /// the desired state until it verifiably sticks (or we give up after a
  /// generous number of attempts). This is what makes audio reliably
  /// "come on" together with the video instead of the video playing
  /// silently forever.
  Future<void> _startAudioSync() async {
    final myToken = ++_audioSyncToken;
    final wantMuted = widget.muted || widget.volume <= 0;
    final wantVolume = widget.volume.clamp(0, 100);

    for (int attempt = 0; attempt < 8; attempt++) {
      if (_disposed || !mounted || myToken != _audioSyncToken) return;
      try {
        if (wantMuted) {
          await _controller.mute();
          await _controller.setVolume(0);
          final isMuted = await _controller.isMuted;
          if (isMuted) return; // verified — done
        } else {
          await _controller.setVolume(wantVolume);
          await _controller.unMute();
          final isMuted = await _controller.isMuted;
          final currentVolume = await _controller.volume;
          if (!isMuted && currentVolume > 0) return; // verified — done
        }
      } catch (e) {
        if (kDebugMode) debugPrint('audio sync attempt error: $e');
      }
      await Future.delayed(Duration(milliseconds: 250 + attempt * 150));
    }
  }

  @override
  void didUpdateWidget(covariant YoutubeScreenPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoId != widget.videoId) {
      _unavailable = false;
      _playbackStarted = false;
      _unavailableNotified = false;
      _playbackWatchdog?.cancel();
      // Load muted first (autoplay-safe), then re-sync real audio state
      // once playback is confirmed via the listener above.
      _controller.mute();
      _controller.loadVideoById(videoId: widget.videoId);
      _controller.playVideo();
      Future.delayed(const Duration(milliseconds: 700), _startAudioSync);
      _playbackWatchdog = Timer(const Duration(seconds: 8), () {
        if (!_playbackStarted) {
          _markUnavailable('Playback did not start after video change');
        }
      });
    } else if (oldWidget.volume != widget.volume ||
        oldWidget.muted != widget.muted) {
      _startAudioSync();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _playbackWatchdog?.cancel();
    _controller.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_unavailable) {
      return Container(
        color: Colors.black,
        alignment: Alignment.center,
        child: const Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.skip_next, color: Colors.white70, size: 40),
              SizedBox(height: 8),
              Text(
                'This video cannot play inside the Android app.\nSkipping to the next available program...',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }

    // AbsorbPointer: the on-screen TV is a "watch only" appliance — we
    // don't want viewers accidentally opening YouTube's own gesture
    // menu/context actions inside our CRT screen illusion.
    return AbsorbPointer(
      absorbing: true,
      child: YoutubePlayer(controller: _controller, aspectRatio: 4 / 3),
    );
  }
}
