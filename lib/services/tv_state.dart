import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/channel.dart';
import '../models/episode.dart';
import '../models/tv_style.dart';
import 'content_service.dart';

enum PowerState { off, startingUp, on }

/// Central state controller for the Retro TV experience: power, current
/// channel, volume, mute, currently playing program, and the
/// channel-switch transition sequence (static -> load -> play).
class TvState extends ChangeNotifier {
  List<Channel> _channels = [];
  List<TvStyle> _tvStyles = [];
  TvStyle? _currentStyle;
  Channel? _currentChannel;
  Channel? _previousChannel;
  Episode? _currentProgram;

  PowerState _power = PowerState.off;
  bool _channelChanging = false;
  int _volume = 50;
  bool _muted = false;
  bool _reduceEffects = false;
  bool _loading = true;
  String? _error;
  String _digitBuffer = '';
  Timer? _digitTimer;
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
  int get volume => _volume;
  bool get muted => _muted;
  bool get reduceEffects => _reduceEffects;
  bool get loading => _loading;
  String? get error => _error;
  String get digitBuffer => _digitBuffer;
  bool get fullscreen => _fullscreen;

  Future<void> initialize() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
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

  Future<void> _loadCurrentProgram() async {
    if (_currentChannel == null) return;
    try {
      _currentProgram = await ContentService.getCurrentProgram(
        _currentChannel!.id,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('_loadCurrentProgram error: $e');
      _currentProgram = null;
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

  /// Called when the current episode finishes playing — advances to another
  /// published episode on the same channel when possible.
  Future<void> onProgramEnded() async {
    await _advanceProgram(skipCurrent: false);
  }

  /// Called when Android WebView/YouTube reports that a video cannot be played
  /// in an embedded player (commonly YouTube error 150/152). This does not mean
  /// the phone is broken; it means that specific YouTube upload blocks app
  /// embeds. We skip it so users do not get stuck on YouTube's error screen.
  Future<void> onProgramUnavailable() async {
    await _advanceProgram(skipCurrent: true);
  }

  Future<void> _advanceProgram({required bool skipCurrent}) async {
    final channel = _currentChannel;
    final current = _currentProgram;
    if (channel == null) return;

    if (skipCurrent && current != null) {
      _temporarilySkippedProgramIds.add(current.id);
    }

    try {
      final episodes = await ContentService.getEpisodes(
        channelId: channel.id,
        onlyPublished: true,
      );
      final playable = episodes
          .where(
            (episode) =>
                episode.youtubeVideoId.trim().isNotEmpty &&
                !_temporarilySkippedProgramIds.contains(episode.id),
          )
          .toList();

      if (playable.isNotEmpty) {
        var nextIndex = 0;
        if (current != null) {
          final currentIndex = playable.indexWhere((e) => e.id == current.id);
          if (currentIndex >= 0) {
            nextIndex = (currentIndex + 1) % playable.length;
          }
        }
        _currentProgram = playable[nextIndex];
        notifyListeners();
        return;
      }

      // If every program on this channel is blocked from embeds, move to the
      // next channel instead of showing the YouTube error forever.
      if (skipCurrent) {
        final enabled = _channels.where((c) => c.enabled).toList();
        if (enabled.length > 1) {
          final currentIndex = enabled.indexWhere((c) => c.id == channel.id);
          final nextIndex = (currentIndex + 1) % enabled.length;
          await _switchToChannel(enabled[nextIndex]);
        } else {
          _currentProgram = null;
          notifyListeners();
        }
        return;
      }

      await _loadCurrentProgram();
      notifyListeners();
    } catch (e) {
      if (kDebugMode) debugPrint('_advanceProgram error: $e');
      await _loadCurrentProgram();
      notifyListeners();
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
    super.dispose();
  }
}
