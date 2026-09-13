import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/channel.dart';
import '../models/episode.dart';
import '../models/schedule.dart';
import '../models/tv_style.dart';
import '../models/up_next.dart';
import '../utils/program_queue.dart';
import 'content_service.dart';
import 'scheduling_timezone.dart';

enum PowerState { off, startingUp, on }

/// Central state controller for the Retro TV experience: power, current
/// channel, volume, mute, and the currently playing program.
///
/// PLAYBACK LOOP: each channel runs an infinite loop over its currently
/// ELIGIBLE episodes. Eligibility is decided server-side by
/// `get_channel_program_queue` (which excludes episodes reserved by a
/// future one-off schedule slot) and the queue is advanced one-by-one with
/// LAST -> FIRST wrap-around. When a scheduled premiere's start time
/// arrives, the server queue immediately includes it (the reservation
/// disappears), so the loop picks it up automatically — no manual
/// activation anywhere.
class TvState extends ChangeNotifier {
  List<Channel> _channels = [];
  List<TvStyle> _tvStyles = [];
  TvStyle? _currentStyle;
  Channel? _currentChannel;
  Channel? _previousChannel;
  Episode? _currentProgram;
  List<Episode> _programQueue = [];
  UpNext? _upNext;
  Map<String, dynamic>? _nextScheduledProgram;

  PowerState _power = PowerState.off;
  bool _channelChanging = false;
  bool _advancing = false;
  int _volume = 50;
  bool _muted = false;
  bool _reduceEffects = false;
  bool _loopChannels = true;
  bool _loading = true;
  String? _error;
  String _digitBuffer = '';
  Timer? _digitTimer;
  Timer? _airSyncTimer;
  bool _fullscreen = false;
  final Set<String> _temporarilySkippedProgramIds = <String>{};

  PowerState get power => _power;
  bool get isOn => _power == PowerState.on;
  bool get channelChanging => _channelChanging;
  List<Channel> get channels => _channels;
  List<TvStyle> get tvStyles => _tvStyles;
  TvStyle? get currentStyle => _currentStyle;
  Channel? get currentChannel => _currentChannel;
  Channel? get previousChannel => _previousChannel;
  Episode? get currentProgram => _currentProgram;

  /// Eligible episodes of the current channel in canonical playback order.
  List<Episode> get programQueue => List.unmodifiable(_programQueue);

  /// The exact program that will play when the current one ends
  /// (next in the loop). May carry an explicit schedule air time.
  UpNext? get upNext => _upNext;

  /// The channel's soonest upcoming *scheduled* program — shown as the
  /// "Up Next / announcement" banner (episode title, thumbnail, time,
  /// date, channel number).
  Map<String, dynamic>? get nextScheduledProgram => _nextScheduledProgram;

  int get volume => _volume;
  bool get muted => _muted;
  bool get reduceEffects => _reduceEffects;

  /// Admin-controlled channel playback switch (site setting
  /// `loop_channels_enabled`). When true the queue loops forever
  /// (last episode wraps back to the first); when false playback stops
  /// after the final episode instead of wrapping.
  bool get loopChannels => _loopChannels;

  /// Effective loop behavior for a channel: the channel's per-channel
  /// override (`loop_playback` column) wins when set, otherwise the global
  /// [loopChannels] site setting governs.
  bool _loopEnabledFor(Channel? channel) => channel?.loopPlayback ?? _loopChannels;

  bool get loading => _loading;
  String? get error => _error;
  String get digitBuffer => _digitBuffer;
  bool get fullscreen => _fullscreen;

  Future<void> initialize() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      // Ensure the scheduling timezone (used for every date/time shown on
      // the "Up Next" card and admin schedule list) is resolved first.
      await SchedulingClock.init();
      _loopChannels = await ContentService.getLoopChannelsEnabled();
      final prefs = await SharedPreferences.getInstance();
      _volume = prefs.getInt('tv_volume') ?? 50;
      _muted = prefs.getBool('tv_muted') ?? false;
      _reduceEffects = prefs.getBool('tv_reduce_effects') ?? false;
      final savedStyleSlug = prefs.getString('tv_style_slug');

      _tvStyles = await _retryWithTimeout(ContentService.getTvStyles);
      _channels = await _retryWithTimeout(ContentService.getChannels);
      _channels.sort((a, b) => a.channelNumber.compareTo(b.channelNumber));

      if (_tvStyles.isEmpty) {
        _currentStyle = _fallbackStyle;
      } else {
        _currentStyle = _tvStyles.firstWhere(
          (s) => s.slug == savedStyleSlug,
          orElse: () => _tvStyles.first,
        );
      }

      if (_channels.isNotEmpty) {
        _currentChannel = _channels.first;
        _temporarilySkippedProgramIds.clear();
        await _loadCurrentProgram();
      }
      _startAirSync();
    } catch (e) {
      _error =
          'Unable to connect to Retro TV channels. Please check your internet connection and try again.';
      if (kDebugMode) debugPrint('TvState.initialize error: $e');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<T> _retryWithTimeout<T>(Future<T> Function() action) async {
    Object? lastError;
    StackTrace? lastStackTrace;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        return await action().timeout(const Duration(seconds: 20));
      } catch (error, stackTrace) {
        lastError = error;
        lastStackTrace = stackTrace;
        if (attempt == 0) {
          await Future<void>.delayed(const Duration(milliseconds: 700));
        }
      }
    }
    return Future<T>.error(
      lastError ?? StateError('Unknown network error'),
      lastStackTrace,
    );
  }

  static final TvStyle _fallbackStyle = TvStyle(
    id: 'fallback-style',
    name: 'Classic Walnut',
    slug: 'classic-walnut',
    description: 'Default offline-safe TV cabinet style.',
    era: '1970s',
    previewImage: null,
    themeConfig: const {
      'bodyColor': '#5A3928',
      'bezelColor': '#261A15',
      'screenTint': '#DCEEFF',
      'accentColor': '#E0A83E',
      'knobColor': '#17110E',
      'glow': '#8AD0FF',
      'grain': true,
      'scanlineOpacity': 0.22,
      'curvature': 0.16,
    },
    screenAspectRatio: '4:3',
    defaultVolume: 50,
    enabled: true,
    sortOrder: 0,
  );

  /// Loads the current channel's eligible program queue, the program it
  /// should start on, the next program, and the channel's upcoming
  /// "announcement" (soonest scheduled program).
  Future<void> _loadCurrentProgram() async {
    if (_currentChannel == null) return;
    try {
      final queue = await _retryWithTimeout(
        () => ContentService.getChannelProgramQueue(_currentChannel!.id),
      );
      _programQueue = queue;

      // Prefer the server-side "airing" episode (set by the backend loop)
      // when one is active, so every viewer joins whatever the channel is
      // genuinely on the air — the loop advances on the server whether or
      // not this TV is open. Without a server airing we keep the previous
      // behavior: tune straight to the channel's default ("Now Playing")
      // episode and continue the loop naturally from there.
      _currentProgram = await _resolveStartWithAiring(queue);

      await _refreshUpNext();
      await _refreshNextScheduled();

      if (kDebugMode) {
        debugPrint(
          'TvState: channel=${_currentChannel!.name} queue=${queue.length} '
          'program=${_currentProgram?.title}',
        );
      }
    } catch (e) {
      if (kDebugMode) debugPrint('_loadCurrentProgram error: $e');
      _programQueue = [];
      _currentProgram = null;
      _upNext = null;
      _nextScheduledProgram = null;
    }
  }

  /// Picks the first episode that plays when a channel is tuned in.
  ///
  /// The channel's default ("Now Playing") episode always wins — even when
  /// it is not currently part of the eligible queue, in which case it is
  /// prepended so the loop keeps running through the playlist from there.
  /// Falls back to the first eligible episode when there is no default.
  Future<Episode?> _resolveStartProgram(List<Episode> queue) async {
    final defaultId = _currentChannel?.defaultEpisodeId;
    if (defaultId != null && defaultId.isNotEmpty) {
      for (final e in queue) {
        if (e.id == defaultId) return e;
      }
      Episode? defaultEpisode;
      try {
        defaultEpisode = await ContentService.getEpisodeById(defaultId);
      } catch (_) {
        defaultEpisode = null;
      }
      if (defaultEpisode != null &&
          defaultEpisode.enabled &&
          defaultEpisode.status == 'published' &&
          defaultEpisode.youtubeVideoId.trim().isNotEmpty) {
        final start = defaultEpisode;
        _programQueue = [
          start,
          ...queue.where((e) => e.id != start.id),
        ];
        return start;
      }
    }
    return queue.isEmpty ? null : queue.first;
  }

  /// First program when a channel is tuned in: the server-side "airing"
  /// episode (from `get_current_program`, flagged `is_airing`) wins when
  /// it is part of the eligible queue — or when the queue is empty and the
  /// airing episode itself is still playable. Otherwise fall back to
  /// [_resolveStartProgram] (channel default before first eligible).
  Future<Episode?> _resolveStartWithAiring(List<Episode> queue) async {
    Map<String, dynamic>? row;
    try {
      row = await ContentService.getCurrentProgramRaw(_currentChannel!.id);
    } catch (_) {
      row = null;
    }
    if (row != null && row['is_airing'] == true) {
      final airingId = row['episode_id'] as String?;
      if (airingId != null && airingId.isNotEmpty) {
        final match = _firstById(queue, airingId);
        if (match != null) return match;
        if (queue.isEmpty) {
          try {
            final airing = await ContentService.getEpisodeById(airingId);
            if (airing != null &&
                airing.enabled &&
                airing.status == 'published' &&
                airing.youtubeVideoId.trim().isNotEmpty) {
              return airing;
            }
          } catch (_) {}
        }
      }
    }
    return _resolveStartProgram(queue);
  }

  Episode? _firstById(List<Episode> queue, String id) {
    for (final e in queue) {
      if (e.id == id) return e;
    }
    return null;
  }

  // ---------------------------------------------------------------
  // Server-side "broadcast" sync
  // ---------------------------------------------------------------

  /// Polls the backend loop once a minute so a long-open TV stays tuned to
  /// whatever the server is actually airing. Episodes advance in the
  /// database (pg_cron) even when no TV is open; powered-on viewers simply
  /// re-sync to the new airing episode the next time the window changes.
  void _startAirSync() {
    _airSyncTimer?.cancel();
    _airSyncTimer =
        Timer.periodic(const Duration(seconds: 60), (_) => _pollAiring());
  }

  Future<void> _pollAiring() async {
    final channel = _currentChannel;
    if (channel == null || !isOn) return;
    if (_channelChanging || _advancing) return;
    try {
      final row = await ContentService.getCurrentProgramRaw(channel.id);
      if (row == null || row['is_airing'] != true) return;
      final airingId = row['episode_id'] as String?;
      if (airingId == null || airingId.isEmpty) return;
      if (_currentProgram?.id == airingId) return;
      final match = _firstById(_programQueue, airingId);
      if (match == null) return;
      if (kDebugMode) {
        debugPrint('TvState: air sync -> ${match.title}');
      }
      _currentProgram = match;
      await _refreshUpNext();
      notifyListeners();
    } catch (e) {
      if (kDebugMode) debugPrint('_pollAiring error: $e');
    }
  }

  Future<void> _refreshUpNext() async {
    final channel = _currentChannel;
    if (channel == null) {
      _upNext = null;
      return;
    }
    // With loop playback disabled there is no "next in the loop" program
    // past the final episode, so the Up Next preview goes away.
    if (!_loopEnabledFor(channel) &&
        ProgramQueue.loopsToStart(_programQueue, _currentProgram?.id)) {
      _upNext = null;
      return;
    }
    final next = ProgramQueue.nextAfter(_programQueue, _currentProgram?.id);
    if (next == null) {
      _upNext = null;
      return;
    }
    ScheduleEntry? entry;
    try {
      entry = await ContentService.getNextScheduleEntry(channel.id, next.id);
    } catch (e) {
      if (kDebugMode) debugPrint('_refreshUpNext error: $e');
    }
    _upNext = UpNext(episode: next, schedule: entry);
  }

  Future<void> _refreshNextScheduled() async {
    final channel = _currentChannel;
    if (channel == null) {
      _nextScheduledProgram = null;
      return;
    }
    try {
      _nextScheduledProgram = await ContentService.getNextScheduledProgram(
        channel.id,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('_refreshNextScheduled error: $e');
      _nextScheduledProgram = null;
    }
  }

  // ---------------------------------------------------------------
  // Power
  // ---------------------------------------------------------------
  Future<void> powerOn() async {
    if (_power == PowerState.on) return;
    _power = PowerState.startingUp;
    notifyListeners();
    await Future.delayed(const Duration(milliseconds: 900));
    _power = PowerState.on;
    if (_currentChannel != null && _currentProgram == null) {
      await _loadCurrentProgram();
    }
    notifyListeners();
  }

  void powerOff() {
    _power = PowerState.off;
    notifyListeners();
  }

  void togglePower() {
    if (isOn) {
      powerOff();
    } else {
      powerOn();
    }
  }

  // ---------------------------------------------------------------
  // TV Style selection
  // ---------------------------------------------------------------
  Future<void> selectStyle(TvStyle style) async {
    _currentStyle = style;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('tv_style_slug', style.slug);
  }

  // ---------------------------------------------------------------
  // Channel switching
  // ---------------------------------------------------------------
  Future<void> _switchToChannel(Channel channel) async {
    if (_channelChanging) return;
    if (_currentChannel != null && _currentChannel!.id != channel.id) {
      _previousChannel = _currentChannel;
    }
    final isDifferentChannel = _currentChannel?.id != channel.id;
    _channelChanging = true;
    _currentProgram = null;
    _programQueue = [];
    _upNext = null;
    _nextScheduledProgram = null;
    if (isDifferentChannel) {
      _temporarilySkippedProgramIds.clear();
    }
    notifyListeners();

    // Show static/glitch transition briefly.
    await Future.delayed(const Duration(milliseconds: 550));

    _currentChannel = channel;
    await _loadCurrentProgram();

    await Future.delayed(const Duration(milliseconds: 150));
    _channelChanging = false;
    notifyListeners();
  }

  /// Recalls the previously-tuned channel (like a "last channel" / "jump"
  /// button on a real remote).
  Future<void> recallLastChannel() async {
    if (_previousChannel == null) return;
    final target = _previousChannel!;
    if (!target.enabled) return;
    await _switchToChannel(target);
  }

  Future<void> channelUp() async {
    if (_channels.isEmpty || _currentChannel == null) return;
    final enabled = _channels.where((c) => c.enabled).toList();
    if (enabled.isEmpty) return;
    final idx = enabled.indexWhere((c) => c.id == _currentChannel!.id);
    final nextIdx = (idx + 1) % enabled.length;
    await _switchToChannel(enabled[nextIdx]);
  }

  Future<void> channelDown() async {
    if (_channels.isEmpty || _currentChannel == null) return;
    final enabled = _channels.where((c) => c.enabled).toList();
    if (enabled.isEmpty) return;
    final idx = enabled.indexWhere((c) => c.id == _currentChannel!.id);
    final prevIdx = (idx - 1 + enabled.length) % enabled.length;
    await _switchToChannel(enabled[prevIdx]);
  }

  Future<void> selectChannelNumber(int number) async {
    final target = _channels.firstWhere(
      (c) => c.channelNumber == number && c.enabled,
      orElse: () => _channels.first,
    );
    if (target.channelNumber != number) return; // no matching enabled channel
    await _switchToChannel(target);
  }

  /// Handles remote-style multi-digit number entry: buffers up to 3 digits,
  /// auto-confirms after a short pause (like a real TV remote), or can be
  /// confirmed immediately with [confirmDigits].
  void pressDigit(int digit) {
    if (!isOn) return;
    _digitBuffer += digit.toString();
    if (_digitBuffer.length > 3) {
      _digitBuffer = _digitBuffer.substring(_digitBuffer.length - 3);
    }
    notifyListeners();
    _digitTimer?.cancel();
    _digitTimer = Timer(const Duration(milliseconds: 1200), confirmDigits);
  }

  void confirmDigits() {
    _digitTimer?.cancel();
    if (_digitBuffer.isEmpty) return;
    final number = int.tryParse(_digitBuffer);
    _digitBuffer = '';
    notifyListeners();
    if (number != null) {
      selectChannelNumber(number);
    }
  }

  void clearDigitBuffer() {
    _digitTimer?.cancel();
    _digitBuffer = '';
    notifyListeners();
  }

  // ---------------------------------------------------------------
  // Fullscreen
  // ---------------------------------------------------------------
  void setFullscreen(bool value) {
    _fullscreen = value;
    notifyListeners();
  }

  void toggleFullscreen() => setFullscreen(!_fullscreen);

  Future<void> selectChannel(Channel channel) async {
    if (!channel.enabled) return;
    await _switchToChannel(channel);
  }

  Future<void> channelSurf() async {
    final enabled = _channels.where((c) => c.enabled).toList();
    if (enabled.isEmpty) return;
    final rng = Random();
    final target = enabled[rng.nextInt(enabled.length)];
    await _switchToChannel(target);
  }

  /// Called when the current episode finishes playing — advances to the
  /// next eligible program on the same channel (continuous loop).
  Future<void> onProgramEnded() async {
    await _advanceProgram(skipCurrent: false);
  }

  /// Called when Android WebView/YouTube reports that a video cannot be played
  /// in an embedded player (commonly YouTube error 150/152, or a transient
  /// failure that survived one automatic reload). This does not mean the phone
  /// is broken; it means that specific YouTube upload blocks app embeds. We
  /// skip it so users do not get stuck on the error overlay. [reason] describes
  /// what happened and is used for debugging.
  Future<void> onProgramUnavailable(String reason) async {
    if (kDebugMode) {
      debugPrint('TvState: skipping unplayable program — $reason');
    }
    await _advanceProgram(skipCurrent: true);
  }

  /// Advances the continuous program loop one step.
  ///
  /// * Re-fetches the channel's eligible queue (eligibility can change the
  ///   instant a schedule slot goes live or a reservation is released).
  /// * Applies [skipCurrent] by remembering the blocked program so the
  ///   loop never retries it immediately.
  /// * `nextAfter` wraps LAST -> FIRST — the infinite channel loop.
  /// * If EVERY remaining program is blocked/hidden we move to the next
  ///   channel instead of pinning the user to a YouTube error screen.
  ///
  /// [_advancing] is a re-entrancy guard: an onEnded callback racing an
  /// onUnavailable callback can never double-advance the loop.
  Future<void> _advanceProgram({required bool skipCurrent}) async {
    final channel = _currentChannel;
    final current = _currentProgram;
    if (channel == null || _advancing) return;
    _advancing = true;
    try {
      if (skipCurrent && current != null) {
        _temporarilySkippedProgramIds.add(current.id);
      }

      List<Episode> queue;
      try {
        queue = await ContentService.getChannelProgramQueue(channel.id);
        _programQueue = queue;
      } catch (e) {
        if (kDebugMode) debugPrint('_advanceProgram fetch error: $e');
        queue = _programQueue;
      }

      final playable = ProgramQueue.playable(
        queue,
        excludedIds: _temporarilySkippedProgramIds,
      );

      if (playable.isNotEmpty) {
        // Loop playback OFF: the final episode finished — stop the channel
        // instead of wrapping back to episode 1.
        final currentIdx = playable.indexWhere((e) => e.id == current?.id);
        if (!_loopEnabledFor(channel) && currentIdx == playable.length - 1) {
          _currentProgram = null;
          _upNext = null;
          notifyListeners();
          return;
        }

        _currentProgram =
            ProgramQueue.nextAfter(playable, current?.id) ?? playable.first;
        _programQueue = playable;
        await _refreshUpNext();
        await _refreshNextScheduled();
        notifyListeners();
        return;
      }

      // Nothing on this channel can be embedded / is playable right now.
      if (skipCurrent) {
        final enabled = _channels.where((c) => c.enabled).toList();
        if (enabled.length > 1) {
          final currentIndex = enabled.indexWhere((c) => c.id == channel.id);
          if (currentIndex >= 0) {
            await _switchToChannel(
              enabled[(currentIndex + 1) % enabled.length],
            );
            return;
          }
        }
        _currentProgram = null;
        _upNext = null;
        notifyListeners();
        return;
      }

      // Natural end-of-program but nothing queued — fall back to a full
      // program refresh (may pick up newly published/reserved-release items).
      await _loadCurrentProgram();
      notifyListeners();
    } catch (e) {
      if (kDebugMode) debugPrint('_advanceProgram error: $e');
      await _loadCurrentProgram();
      notifyListeners();
    } finally {
      _advancing = false;
    }
  }

  // ---------------------------------------------------------------
  // Volume
  // ---------------------------------------------------------------
  Future<void> setVolume(int value) async {
    _volume = value.clamp(0, 100);
    if (_volume > 0) _muted = false;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('tv_volume', _volume);
    await prefs.setBool('tv_muted', _muted);
  }

  Future<void> volumeUp() => setVolume(_volume + 5);
  Future<void> volumeDown() => setVolume(_volume - 5);

  Future<void> toggleMute() async {
    _muted = !_muted;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('tv_muted', _muted);
  }

  int get effectiveVolume => _muted ? 0 : _volume;

  // ---------------------------------------------------------------
  // Effects setting
  // ---------------------------------------------------------------
  Future<void> setReduceEffects(bool value) async {
    _reduceEffects = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('tv_reduce_effects', value);
  }

  Future<void> refreshChannels() async {
    try {
      _channels = await ContentService.getChannels();
      _channels.sort((a, b) => a.channelNumber.compareTo(b.channelNumber));
      notifyListeners();
    } catch (e) {
      if (kDebugMode) debugPrint('refreshChannels error: $e');
    }
  }

  @override
  void dispose() {
    _digitTimer?.cancel();
    _airSyncTimer?.cancel();
    super.dispose();
  }
}
