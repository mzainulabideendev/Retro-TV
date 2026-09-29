import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart' as mkv;
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt;

/// Desktop YouTube player that bypasses the YouTube embed entirely.
///
/// Used on every desktop platform where `youtube_player_iframe` (and therefore
/// `webview_flutter`) has no native implementation:
///
/// * WINDOWS: WebView2-hosted embeds were tried and YouTube rejected them with
///   error 153 ("Video player configuration error"); `webview_flutter` has no
///   Windows implementation at all.
/// * LINUX: `webview_flutter` supports only Android/iOS/macOS - there is no
///   Linux implementation, so the iframe player cannot render here either.
///
/// WHAT THIS DOES INSTEAD: it asks YouTube for the real progressive MP4
/// stream URL via `youtube_explode_dart`, then plays that URL directly with
/// `media_kit` (libmpv). There is no embed, no player-config negotiation in a
/// browser, and therefore no way to hit 153. As a bonus there is no YouTube
/// chrome, no "watch on YouTube" overlays, and no autoplay policy to fight -
/// the TV just plays the file.
///
/// The public contract is identical to `YoutubeScreenPlayer` (autoplay,
/// volume, position handoff between the small and fullscreen surfaces,
/// next-program handoff when a video cannot be played), so no call site and no
/// other platform changes.
///
/// Runtime requirement on Linux: `media_kit_libs_linux` links against the
/// system libmpv (`libmpv.so.2`), which is an explicit package dependency of
/// every Linux package produced for this app.
class NativeStreamYoutubePlayer extends StatefulWidget {
  final String videoId;
  final int volume; // 0-100
  final bool muted;
  final int initialPositionMs;
  final ValueChanged<int>? onPositionChanged;
  final VoidCallback? onEnded;
  final void Function(String reason)? onUnavailable;
  final Widget? crtOverlay;

  const NativeStreamYoutubePlayer({
    super.key,
    required this.videoId,
    required this.volume,
    required this.muted,
    this.initialPositionMs = 0,
    this.onPositionChanged,
    this.onEnded,
    this.onUnavailable,
    this.crtOverlay,
  });

  @override
  State<NativeStreamYoutubePlayer> createState() =>
      _NativeStreamYoutubePlayerState();
}

class _NativeStreamYoutubePlayerState extends State<NativeStreamYoutubePlayer> {
  /// libmpv must be initialised exactly once per process, before any [Player]
  /// is constructed. `MediaKit.ensureInitialized` is not safe to call twice.
  static bool _mediaKitReady = false;
  static void _ensureMediaKit() {
    if (_mediaKitReady) return;
    MediaKit.ensureInitialized();
    _mediaKitReady = true;
  }

  static const Duration _watchdogTimeout = Duration(seconds: 25);
  static const int _maxRetries = 2;

  final yt.YoutubeExplode _yt = yt.YoutubeExplode();

  Player? _player;
  mkv.VideoController? _videoController;

  final List<StreamSubscription<dynamic>> _subs = [];

  Timer? _watchdog;
  int _loadToken = 0;
  int _retryCount = 0;

  bool _playbackStarted = false;
  bool _unavailable = false;
  bool _unavailableNotified = false;
  bool _endedReported = false;
  bool _reportedPosition = false;
  bool _pendingResume = false;
  String _unavailableReason =
      'This video cannot be played in an embedded player.';

  @override
  void initState() {
    super.initState();
    _pendingResume = widget.initialPositionMs > 0;
    _ensureMediaKit();
    _createPlayer();
    unawaited(_load(widget.videoId));
  }

  void _createPlayer() {
    final player = Player();
    _player = player;
    _videoController = mkv.VideoController(player);
    _watchState(player);
  }

  /// Mirrors the player state onto the TV's callbacks.
  void _watchState(Player player) {
    Duration position = Duration.zero;

    _subs.add(player.stream.playing.listen((playing) {
      if (!mounted || !playing || _playbackStarted) return;
      _playbackStarted = true;
      _watchdog?.cancel();
      // Resume where the previous surface left off, once the stream is live.
      if (_pendingResume) {
        _pendingResume = false;
        unawaited(
          player.seek(Duration(milliseconds: widget.initialPositionMs)),
        );
      }
    }));

    _subs.add(player.stream.position.listen((value) {
      if (!mounted) return;
      position = value;
      _reportPosition(value);
    }));

    _subs.add(player.stream.completed.listen((completed) {
      if (!mounted || !completed || _endedReported) return;
      _endedReported = true;
      _reportPosition(position);
      widget.onEnded?.call();
    }));
  }

  void _reportPosition(Duration position) {
    if (!mounted || _reportedPosition && position == Duration.zero) return;
    _reportedPosition = true;
    widget.onPositionChanged?.call(position.inMilliseconds);
  }

  /// Resolves the real stream URL and hands it to the player.
  Future<void> _load(String videoId) async {
    final myToken = ++_loadToken;
    final player = _player;
    if (player == null) return;

    _playbackStarted = false;
    _endedReported = false;
    _reportedPosition = false;
    _armWatchdog();

    try {
      // Progressive (muxed audio+video) MP4 streams are the only ones a plain
      // URL can play; adaptive DASH would need a separate audio track.
      final manifest = await _yt.videos.streamsClient.getManifest(videoId);
      if (!mounted || myToken != _loadToken) return;

      final muxed = manifest.muxed;
      if (muxed.isEmpty) {
        _markUnavailable(
          'YouTube offered no playable stream for this video.',
          retryable: false,
        );
        return;
      }

      // Best available: highest resolution wins, then the largest file.
      final chosen = _pickBest(muxed);

      if (kDebugMode) {
        debugPrint(
          'NativeStreamYoutubePlayer: $videoId -> ${chosen.qualityLabel} '
          '${chosen.videoResolution.width}x${chosen.videoResolution.height} '
          '${chosen.container.name} '
          '${(chosen.size.totalBytes / 1024).round()}KiB',
        );
      }

      await player.open(Media(chosen.url.toString()), play: true);
      if (!mounted || myToken != _loadToken) return;

      await _applyAudio();
    } on yt.VideoUnplayableException catch (e) {
      if (!mounted || myToken != _loadToken) return;
      _markUnavailable(_reasonForUnplayable(e), retryable: false);
    } catch (e) {
      if (!mounted || myToken != _loadToken) return;
      if (kDebugMode) debugPrint('NativeStreamYoutubePlayer load error: $e');
      _markUnavailable('Could not start this video ($e).');
    }
  }

  yt.MuxedStreamInfo _pickBest(List<yt.MuxedStreamInfo> streams) {
    var best = streams.first;
    for (final candidate in streams.skip(1)) {
      final candidateHeight = candidate.videoResolution.height;
      final bestHeight = best.videoResolution.height;
      if (candidateHeight > bestHeight ||
          (candidateHeight == bestHeight &&
              candidate.size.totalBytes > best.size.totalBytes)) {
        best = candidate;
      }
    }
    return best;
  }

  String _reasonForUnplayable(yt.VideoUnplayableException e) {
    final message = e.message.toLowerCase();
    if (message.contains('live stream')) {
      return 'This program is a live stream. Live video is not available on '
          'this channel yet.';
    }
    if (message.contains('unavailable') || message.contains('private')) {
      return 'This video is no longer available (removed or made private).';
    }
    if (message.contains('reloaded')) {
      return 'YouTube asked to reload the video. Trying again shortly.';
    }
    if (message.contains('restrictions') || message.contains('age')) {
      return 'This video is age-restricted and cannot be played on this '
          'channel.';
    }
    return 'This video cannot be played here (YouTube reports it as '
        'unplayable).';
  }

  Future<void> _applyAudio() async {
    final player = _player;
    if (player == null) return;
    final silent = widget.muted || widget.volume <= 0;
    try {
      await player.setVolume(
        silent ? 0 : widget.volume.clamp(0, 100).toDouble(),
      );
    } catch (e) {
      if (kDebugMode) debugPrint('NativeStreamYoutubePlayer volume error: $e');
    }
  }

  void _armWatchdog() {
    _watchdog?.cancel();
    _watchdog = Timer(_watchdogTimeout, () {
      if (!mounted || _playbackStarted) return;
      _markUnavailable('The video did not start playing.');
    });
  }

  void _markUnavailable(String reason, {bool retryable = true}) {
    if (!mounted || _unavailableNotified) return;

    if (retryable && !_playbackStarted && _retryCount < _maxRetries) {
      _retryCount++;
      if (kDebugMode) {
        debugPrint(
          'NativeStreamYoutubePlayer: retry $_retryCount/$_maxRetries for '
          '${widget.videoId} ($reason)',
        );
      }
      unawaited(_load(widget.videoId));
      return;
    }

    _unavailableNotified = true;
    if (kDebugMode) {
      debugPrint(
        'NativeStreamYoutubePlayer unavailable ($reason) for ${widget.videoId}',
      );
    }
    _watchdog?.cancel();
    setState(() {
      _unavailable = true;
      _unavailableReason = reason;
    });
    Future<void>.delayed(const Duration(milliseconds: 900), () {
      if (mounted) widget.onUnavailable?.call(reason);
    });
  }

  @override
  void didUpdateWidget(covariant NativeStreamYoutubePlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoId != widget.videoId) {
      _retryCount = 0;
      _unavailable = false;
      _unavailableNotified = false;
      _pendingResume = false;
      unawaited(_load(widget.videoId));
      return;
    }
    if (oldWidget.volume != widget.volume ||
        oldWidget.muted != widget.muted) {
      unawaited(_applyAudio());
    }
  }

  @override
  void dispose() {
    _loadToken++;
    _watchdog?.cancel();
    for (final sub in _subs) {
      unawaited(sub.cancel());
    }
    _subs.clear();

    final player = _player;
    _player = null;
    _videoController = null;
    if (player != null) {
      unawaited(player.stop());
      unawaited(player.dispose());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_unavailable) {
      return Container(
        color: Colors.black,
        alignment: Alignment.center,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.white70, size: 36),
              const SizedBox(height: 10),
              Text(
                _unavailableReason,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Skipping to the next available program\u2026',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ],
          ),
        ),
      );
    }

    final controller = _videoController;

    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: Colors.black),
        if (controller != null)
          mkv.Video(
            controller: controller,
            // The TV picture is a plain rectangle; the CRT frame, curvature and
            // scanline treatment are layered on top by the caller.
            fit: BoxFit.contain,
            alignment: Alignment.center,
            // No native controls: the on-screen remote is the only control.
            controls: mkv.NoVideoControls,
          ),
        if (widget.crtOverlay != null)
          IgnorePointer(child: widget.crtOverlay!),
      ],
    );
  }
}