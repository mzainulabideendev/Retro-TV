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
///
/// FAILURE STRATEGY: two distinct failure classes are handled here —
///   1. HARD errors surfaced by the YouTube iframe API (for example
///      error 100/105 "video removed/private" and 101/150 "embedding
///      blocked by the uploader"). These can never be fixed by retrying,
///      so we immediately show the reason and hand off to [onUnavailable]
///      so TvState can skip to the next playable program.
///   2. TRANSIENT no-start cases (the WebView/iframe stays silent or shows
///      YouTube's own "unavailable / watch on YouTube" overlay because of
///      a slow connection, a cold WebView, or a flaky first autoplay).
///      Instead of skipping on the first timeout, we fully recreate the
///      embedded player up to [_maxRetries] times — a brand-new WebView
///      page clears error overlays that in-place reloads cannot — and only
///      give up — reporting the reason — if playback still has not started.
///
/// POSITION HANDOFF (small screen <-> fullscreen): the small CRT player and
/// the fullscreen player are the same shared widget, but on some platforms
/// (Android WebView) reparenting the player can recreate the underlying
/// view and restart the video at 0:00. To guarantee "same time & duration"
/// between the two surfaces, this widget periodically reports its current
/// playback position via [onPositionChanged] (and once more on dispose).
/// When a surface mounts with a non-zero [initialPositionMs] it seeks there
/// before continuing — so whichever screen appears next resumes exactly
/// where the previous one left off.
class YoutubeScreenPlayer extends StatefulWidget {
  final String videoId;
  final int volume; // 0-100
  final bool muted;

  /// Playback position in milliseconds the video should resume from when a
  /// fresh player surface mounts (0 = start from the beginning).
  final int initialPositionMs;

  /// Called periodically (and on dispose) with the current playback
  /// position in milliseconds so the next surface can resume seamlessly.
  final ValueChanged<int>? onPositionChanged;

  final VoidCallback? onEnded;
  final void Function(String reason)? onUnavailable;

  const YoutubeScreenPlayer({
    super.key,
    required this.videoId,
    required this.volume,
    required this.muted,
    this.initialPositionMs = 0,
    this.onPositionChanged,
    this.onEnded,
    this.onUnavailable,
  });

  @override
  State<YoutubeScreenPlayer> createState() => _YoutubeScreenPlayerState();
}

class _YoutubeScreenPlayerState extends State<YoutubeScreenPlayer> {
  static const Duration _watchdogTimeout = Duration(seconds: 12);
  static const Duration _positionReportInterval = Duration(seconds: 1);

  late YoutubePlayerController _controller;
  bool _disposed = false;
  bool _playbackStarted = false;
  bool _unavailable = false;
  bool _unavailableNotified = false;

  /// True until this surface has jumped to [YoutubeScreenPlayer.initialPositionMs]
  /// (fresh mounts only — an already-running reparented player never seeks).
  bool _pendingResume = false;

  static const int _maxRetries = 2;
  int _retryCount = 0;

  Timer? _playbackWatchdog;
  Timer? _positionReporter;
  int _audioSyncToken = 0;
  String _unavailableReason =
      'This video cannot be played in an embedded player.';

  /// When the current video was last (re)loaded. The iframe API can emit
  /// "phantom" transient errors (notably code -1) while the WebView/iframe
  /// is still initializing right after a load — we ignore errors that land
  /// within a short grace window after (re)loading and let actual playback
  /// state decide instead.
  DateTime _lastLoadAt = DateTime.fromMicrosecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _createController();
  }

  void _createController() {
    // Invalidate any audio-sync loop still associated with a previous
    // controller instance (used on retry recreation).
    _audioSyncToken++;
    _controller = YoutubePlayerController(
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
        // Use youtube-nocookie.com to avoid YouTube's embed error 15/152
        // ("This video is unavailable") which plagues WebView-based
        // players on Android TV devices.
        privacyEnhancedMode: true,
        // Android TV boxes often ship a stale/system WebView whose UA ends
        // with "; wv" — YouTube rejects webviews (error 152) and treats
        // them as non-autoplayable embeds. Presenting a normal mobile
        // Chrome UA sidesteps that embed detection so autoplay starts.
        userAgent:
            'Mozilla/5.0 (Linux; Android 10; Mobile) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
      ),
      onWebResourceError: (error) {
        // WebView-level failures (DNS/connection blips, blocked hosts)
        // never reach the iframe API, so the only visible symptom can be
        // a silent player. Log them for diagnosis; the timeout handling
        // below decides whether a retry is worthwhile.
        if (kDebugMode) {
          debugPrint('YoutubeScreenPlayer WebView error: ${error.description}');
        }
      },
    )..loadVideoById(videoId: widget.videoId);
    _lastLoadAt = DateTime.now();

    _controller.listen(_onPlayerEvent);

    // Fresh surface: if a position was handed off from the surface this one
    // is replacing (small screen <-> fullscreen), resume there instead of
    // restarting at 0:00. Rechecks on the first "playing" event so the seek
    // happens once the stream is actually ready.
    _pendingResume = widget.initialPositionMs > 0;
    if (_pendingResume) {
      Future.delayed(const Duration(milliseconds: 1200), _resumeFromSavedPosition);
    }

    // Kick playback immediately; also acts as a safety net in case the
    // autoPlay param is ignored on some platforms.
    _controller.playVideo();

    // Unconditional fallback: start the sync loop shortly after creation
    // regardless of whether a usable player-state event ever arrives, so
    // the channel never stays muted/silent forever.
    Future.delayed(const Duration(milliseconds: 700), _startAudioSync);

    _startPositionReporter();

    _armWatchdog();
  }

  /// Reports the current playback position (ms) to [onPositionChanged] so the
  /// next surface (small screen or fullscreen) can resume seamlessly. No-ops
  /// when silent.
  void _reportPosition(double seconds) {
    if (_disposed) return;
    widget.onPositionChanged?.call((seconds * 1000).round());
  }

  void _startPositionReporter() {
    _positionReporter?.cancel();
    _positionReporter = Timer.periodic(_positionReportInterval, (_) async {
      if (_disposed) return;
      try {
        _reportPosition(await _controller.currentTime);
      } catch (_) {
        // The iframe bridge can throw while the WebView is being torn down.
      }
    });
  }

  /// Seeks this freshly-created surface to the position handed off by the
  /// surface it replaces, then continues playback.
  Future<void> _resumeFromSavedPosition() async {
    if (_disposed || !_pendingResume) return;
    try {
      await _controller.seekTo(
        seconds: widget.initialPositionMs / 1000.0,
        allowSeekAhead: true,
      );
    } catch (_) {
      // Seek before the stream is ready is a no-op rather than an error;
      // the "playing" recheck covers that case.
    }
    _pendingResume = false;
  }

  void _onPlayerEvent(YoutubePlayerValue event) {
    if (event.error != YoutubeError.none) {
      _handlePlayerError(event.error);
      return;
    }
    switch (event.playerState) {
      case PlayerState.playing:
        // Real playback confirmed — stop worrying about timeouts.
        _playbackStarted = true;
        _playbackWatchdog?.cancel();
        _startAudioSync();
        if (_pendingResume) _resumeFromSavedPosition();
        break;
      case PlayerState.buffering:
        // The player is actively loading the stream (this can last a long
        // while on slow connections) — extend the timeout instead of
        // assuming failure, and keep audio retrying in case playback
        // started silently without a clean "playing" transition.
        _armWatchdog();
        if (!_playbackStarted) _startAudioSync();
        break;
      case PlayerState.ended:
        widget.onEnded?.call();
        break;
      default:
        break;
    }
  }

  /// Hardest failures from the iframe API. None of them are helped by a
  /// reload, so skip straight to the unavailable screen with the reason.
  void _handlePlayerError(YoutubeError error) {
    switch (error) {
      case YoutubeError.none:
        return;
      case YoutubeError.videoNotFound:
      case YoutubeError.cannotFindVideo:
        _markUnavailable(
          'This video is no longer available (removed or made private).',
          retryable: false,
        );
        break;
      case YoutubeError.notEmbeddable:
      case YoutubeError.sameAsNotEmbeddable:
      case YoutubeError.sameAsNotEmbeddable2:
        _markUnavailable(
          'This video can\'t be viewed inside the app because its '
          'owner blocked embedding on YouTube.',
          retryable: false,
        );
        break;
      case YoutubeError.invalidParam:
      case YoutubeError.html5Error:
      case YoutubeError.unknown:
        // Transient error family (codes -1, 2, 5). These frequently fire
        // once while the iframe is still initializing and the very same
        // video then plays perfectly — so they must NEVER kill an already
        // playing session, and at start-up they get one full reload before
        // we even consider declaring the video unplayable. Only a failure
        // that persists after that reload (outside the short grace window)
        // hands off to the skip path.
        if (_playbackStarted) return;
        if (_retryCount >= _maxRetries &&
            DateTime.now().difference(_lastLoadAt) <
                const Duration(milliseconds: 1000)) {
          // Phantom error right after the final remediation reload —
          // ignore and let the watchdog/player events decide the outcome.
          _armWatchdog();
          return;
        }
        _markUnavailable(
          'YouTube reported a playback error (code ${error.code}).',
        );
        break;
    }
  }

  /// Marks this video as unplayable, paints an explanatory overlay and —
  /// after a short beat so the viewer can read it — asks [onUnavailable]
  /// to hand off to the next playable program.
  ///
  /// When [retryable] is true and the video has not started playing yet,
  /// the first calls trigger full rebuilds of the embedded player (a fresh
  /// WebView) instead of skipping — transient "Playback error"/unavailable
  /// overlays usually disappear once the player is recreated. Only once
  /// the retry budget is exhausted do we paint the overlay and hand off.
  void _markUnavailable(String reason, {bool retryable = true}) {
    if (_disposed || _unavailableNotified) return;

    if (retryable && !_playbackStarted && _retryCount < _maxRetries) {
      _retryCount++;
      if (kDebugMode) {
        debugPrint(
          'YoutubeScreenPlayer: retry $_retryCount/$_maxRetries '
          'for ${widget.videoId} ($reason)',
        );
      }
      _retryPlayback();
      return;
    }

    _unavailableNotified = true;
    if (kDebugMode) {
      debugPrint(
        'YoutubeScreenPlayer unavailable '
        '($reason) for video ${widget.videoId}',
      );
    }
    _playbackWatchdog?.cancel();
    try {
      _controller.pauseVideo();
    } catch (_) {
      // Ignore controller shutdown/race errors.
    }
    if (mounted) {
      setState(() {
        _unavailable = true;
        _unavailableReason = reason;
      });
    }
    Future<void>.delayed(const Duration(milliseconds: 900), () {
      if (!_disposed) widget.onUnavailable?.call(reason);
    });
  }

  /// Transient-failure remediation: tear down the current player and build a
  /// completely fresh one (a brand-new WebView page) for the same video,
  /// then immediately try to start playback again. Recreating the player is
  /// deliberately preferred over in-place reloads because YouTube's own
  /// error overlays ("This video is unavailable · Watch on YouTube", 152-x)
  /// live inside the broken WebView document and do not go away when you
  /// merely re-call loadVideoById() on that same, already-broken page.
  void _retryPlayback() {
    if (_disposed) return;
    _playbackStarted = false;
    if (kDebugMode) {
      debugPrint(
        'YoutubeScreenPlayer: recreating player for ${widget.videoId}',
      );
    }
    try {
      _controller.close();
    } catch (_) {
      // Ignore shutdown/race errors.
    }
    _createController();
  }

  void _armWatchdog() {
    _playbackWatchdog?.cancel();
    _playbackWatchdog = Timer(_watchdogTimeout, () {
      if (_disposed || _playbackStarted) return;
      _markUnavailable('The video did not start playing.');
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
      _unavailableReason = 'This video cannot be played in an embedded player.';
      _playbackStarted = false;
      _unavailableNotified = false;
      _retryCount = 0;
      _playbackWatchdog?.cancel();
      _pendingResume = false; // a fresh video always starts at 0:00
      // Load muted first (autoplay-safe), then re-sync real audio state
      // once playback is confirmed via the listener above.
      _controller.mute();
      _controller.loadVideoById(videoId: widget.videoId);
      _lastLoadAt = DateTime.now();
      _controller.playVideo();
      Future.delayed(const Duration(milliseconds: 700), _startAudioSync);
      _armWatchdog();
    } else if (oldWidget.volume != widget.volume ||
        oldWidget.muted != widget.muted) {
      _startAudioSync();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _playbackWatchdog?.cancel();
    _positionReporter?.cancel();
    // Hand the current position to whatever surface mounts next (small
    // screen <-> fullscreen) so playback resumes at the same time instead
    // of restarting at 0:00.
    if (widget.onPositionChanged != null) {
      try {
        _controller.currentTime.then(_reportPosition).catchError((_) {});
      } catch (_) {}
    }
    _controller.close();
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

    // AbsorbPointer: the on-screen TV is a "watch only" appliance — we
    // don't want viewers accidentally opening YouTube's own gesture
    // menu/context actions inside our CRT screen illusion.
    return AbsorbPointer(
      absorbing: true,
      child: YoutubePlayer(controller: _controller, aspectRatio: 4 / 3),
    );
  }
}
