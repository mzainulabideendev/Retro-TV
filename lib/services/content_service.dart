import 'package:flutter/foundation.dart' hide Category;
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import '../models/category.dart';
import '../models/channel.dart';
import '../models/episode.dart';
import '../models/playlist_import_result.dart';
import '../models/schedule.dart';
import '../models/show.dart';
import '../models/tv_style.dart';
import 'supabase_service.dart';

/// Data-access layer for all public + admin content operations.
///
/// Read methods work for both anonymous and authenticated users (RLS
/// filters what each role can see). Write methods (create/update/delete)
/// will simply fail with a Postgrest 403-style error at the database
/// level if the caller isn't authorized — this class does not attempt
/// to replicate that logic client-side.
class ContentService {
  static final _client = SupabaseService.client;

  // ---------------------------------------------------------------
  // In-memory read cache
  // ---------------------------------------------------------------

  /// Small TTL cache for frequently-read reference data (channels, styles,
  /// categories, settings, episodes). Returning the cached copy avoids a
  /// network round-trip on repeat reads (retries, channel re-tuning,
  /// refreshChannels), which is the biggest driver of the "slow to load"
  /// feeling. Writes invalidate the affected family. Live broadcast data
  /// (current program, program queue, schedule RPCs) is deliberately NOT
  /// cached so playback stays correct.
  static final Map<String, _CachedValue> _cache = {};
  static const Duration _cacheTtl = Duration(seconds: 30);

  static Future<T> _cached<T>(String key, Future<T> Function() loader) async {
    final hit = _cache[key];
    if (hit != null && !hit.isExpired) return hit.value as T;
    final value = await loader();
    _cache[key] = _CachedValue(value, DateTime.now().add(_cacheTtl));
    return value;
  }

  static void _invalidate(String prefix) {
    _cache.removeWhere((key, _) => key.startsWith(prefix));
  }

  // ---------------------------------------------------------------
  // TV Styles
  // ---------------------------------------------------------------
  static Future<List<TvStyle>> getTvStyles({bool onlyEnabled = true}) async {
    return _cached('tv_styles:$onlyEnabled', () async {
      var query = _client.from('tv_styles').select();
      if (onlyEnabled) query = query.eq('enabled', true);
      final res = await query.order('sort_order');
      return (res as List).map((m) => TvStyle.fromMap(m)).toList();
    });
  }

  static Future<void> createTvStyle(TvStyle style) async {
    await _client.from('tv_styles').insert(style.toInsertMap());
    _invalidate('tv_styles');
  }

  static Future<void> updateTvStyle(
    String id,
    Map<String, dynamic> patch,
  ) async {
    await _client.from('tv_styles').update(patch).eq('id', id);
    _invalidate('tv_styles');
  }

  static Future<void> deleteTvStyle(String id) async {
    await _client.from('tv_styles').delete().eq('id', id);
    _invalidate('tv_styles');
  }

  // ---------------------------------------------------------------
  // Categories
  // ---------------------------------------------------------------
  static Future<List<Category>> getCategories({bool onlyEnabled = true}) async {
    return _cached('categories:$onlyEnabled', () async {
      var query = _client.from('categories').select();
      if (onlyEnabled) query = query.eq('enabled', true);
      final res = await query.order('sort_order');
      return (res as List).map((m) => Category.fromMap(m)).toList();
    });
  }

  static Future<void> createCategory(Category c) async {
    await _client.from('categories').insert(c.toInsertMap());
    _invalidate('categories');
  }

  static Future<void> updateCategory(
    String id,
    Map<String, dynamic> patch,
  ) async {
    await _client.from('categories').update(patch).eq('id', id);
    _invalidate('categories');
  }

  static Future<void> deleteCategory(String id) async {
    await _client.from('categories').delete().eq('id', id);
    _invalidate('categories');
  }

  // ---------------------------------------------------------------
  // Channels
  // ---------------------------------------------------------------
  static Future<List<Channel>> getChannels({bool onlyEnabled = true}) async {
    return _cached('channels:$onlyEnabled', () async {
      var query = _client.from('channels').select();
      if (onlyEnabled) query = query.eq('enabled', true);
      final res = await query.order('channel_number');
      return (res as List).map((m) => Channel.fromMap(m)).toList();
    });
  }

  static Future<Channel?> getChannelByNumber(int number) async {
    final res = await _client
        .from('channels')
        .select()
        .eq('channel_number', number)
        .maybeSingle();
    return res != null ? Channel.fromMap(res) : null;
  }

  static Future<String> createChannel(Channel c) async {
    try {
      final res = await _client
          .from('channels')
          .insert(c.toInsertMap())
          .select('id')
          .single();
      _invalidate('channels');
      return res['id'] as String;
    } on PostgrestException catch (e) {
      if (e.code == '23505') {
        throw Exception('Channel number or slug already exists.');
      }
      rethrow;
    }
  }

  static Future<void> updateChannel(
    String id,
    Map<String, dynamic> patch,
  ) async {
    try {
      await _client.from('channels').update(patch).eq('id', id);
      _invalidate('channels');
    } on PostgrestException catch (e) {
      if (e.code == '23505') {
        throw Exception('Channel number or slug already exists.');
      }
      rethrow;
    }
  }

  static Future<void> deleteChannel(String id) async {
    await _client.from('channels').delete().eq('id', id);
    _invalidate('channels');
  }

  /// Applies a single loop-playback value to EVERY channel, so an admin can
  /// switch looping on/off for all TV channels at once (in addition to the
  /// per-channel override). A non-null id filter keeps the update explicit
  /// while still covering every row (all channel ids are uuids).
  static Future<void> setLoopForAllChannels(bool enabled) async {
    await _client
        .from('channels')
        .update({'loop_playback': enabled})
        .neq('id', '00000000-0000-0000-0000-000000000000');
    _invalidate('channels');
  }

  // ---------------------------------------------------------------
  // Shows
  // ---------------------------------------------------------------
  static Future<List<Show>> getShows({
    bool onlyEnabled = true,
    String? channelId,
  }) async {
    var query = _client.from('shows').select();
    if (onlyEnabled) query = query.eq('enabled', true);
    if (channelId != null) query = query.eq('channel_id', channelId);
    final res = await query.order('title');
    return (res as List).map((m) => Show.fromMap(m)).toList();
  }

  static Future<String> createShow(Show s) async {
    final res = await _client
        .from('shows')
        .insert(s.toInsertMap())
        .select('id')
        .single();
    return res['id'] as String;
  }

  static Future<void> updateShow(String id, Map<String, dynamic> patch) async {
    await _client.from('shows').update(patch).eq('id', id);
  }

  static Future<void> deleteShow(String id) async {
    await _client.from('shows').delete().eq('id', id);
  }

  // ---------------------------------------------------------------
  // Episodes
  // ---------------------------------------------------------------
  static Future<List<Episode>> getEpisodes({
    String? showId,
    String? channelId,
    bool onlyPublished = false,
  }) async {
    var query = _client.from('episodes').select();
    if (showId != null) query = query.eq('show_id', showId);
    if (channelId != null) query = query.eq('channel_id', channelId);
    if (onlyPublished) {
      query = query.eq('enabled', true).eq('status', 'published');
    }
    final res = await query.order('season_number').order('episode_number');
    return (res as List).map((m) => Episode.fromMap(m)).toList();
  }

  static Future<Episode?> getEpisodeById(String id) async {
    if (id.isEmpty) return null;
    return _cached('episode:$id', () async {
      final res = await _client
          .from('episodes')
          .select()
          .eq('id', id)
          .maybeSingle();
      return res != null ? Episode.fromMap(res) : null;
    });
  }

  static Future<String> createEpisode(Episode e) async {
    try {
      final res = await _client
          .from('episodes')
          .insert(e.toInsertMap())
          .select('id')
          .single();
      final id = res['id'] as String;
      _invalidate('episodes');
      await _maybeSetAsChannelDefault(
        channelId: e.channelId,
        enabled: e.enabled,
        status: e.status,
        episodeId: id,
      );
      return id;
    } on PostgrestException catch (ex) {
      if (ex.code == '23505') {
        throw Exception('Duplicate episode number for this show/season.');
      }
      rethrow;
    }
  }

  static Future<void> updateEpisode(
    String id,
    Map<String, dynamic> patch,
  ) async {
    await _client.from('episodes').update(patch).eq('id', id);
    _invalidate('episodes');
    // If this episode is (still) assigned to a channel and is
    // published/enabled, make sure it's actually wired up as that
    // channel's now-playing program — otherwise an admin can add/edit an
    // episode, pick a channel for it, and nothing ever airs (the
    // "Channel unavailable" bug). Only `channel_schedule` entries or
    // `channels.default_episode_id` make an episode actually playable;
    // simply tagging an episode with a channel_id does not.
    if (patch.containsKey('channel_id') ||
        patch.containsKey('enabled') ||
        patch.containsKey('status')) {
      final channelId = patch.containsKey('channel_id')
          ? patch['channel_id'] as String?
          : (await getEpisodeById(id))?.channelId;
      final enabled = patch['enabled'] as bool? ?? true;
      final status = patch['status'] as String? ?? 'published';
      await _maybeSetAsChannelDefault(
        channelId: channelId,
        enabled: enabled,
        status: status,
        episodeId: id,
      );
    }
  }

  /// Ensures a freshly-created/updated episode actually becomes visible
  /// on its assigned channel by setting it as that channel's
  /// `default_episode_id`. This is what `get_current_program()` falls
  /// back to when there's no explicit `channel_schedule` entry, which is
  /// the normal case for a simple "admin drops a video on a channel"
  /// workflow. Without this, an episode with `channel_id` set but no
  /// schedule entry and no default would never actually air.
  static Future<void> _maybeSetAsChannelDefault({
    required String? channelId,
    required bool enabled,
    required String status,
    required String episodeId,
  }) async {
    if (channelId == null) return;
    if (!enabled || status != 'published') return;
    try {
      await updateChannel(channelId, {'default_episode_id': episodeId});
    } catch (e) {
      if (kDebugMode) debugPrint('_maybeSetAsChannelDefault error: $e');
    }
  }

  static Future<void> deleteEpisode(String id) async {
    await _client.from('episodes').delete().eq('id', id);
    _invalidate('episodes');
  }

  // ---------------------------------------------------------------
  // Channel Schedule
  // ---------------------------------------------------------------
  static Future<List<ScheduleEntry>> getSchedule(String channelId) async {
    final res = await _client
        .from('channel_schedule')
        .select()
        .eq('channel_id', channelId)
        .order('start_time');
    return (res as List).map((m) => ScheduleEntry.fromMap(m)).toList();
  }

  static Future<void> createScheduleEntry(ScheduleEntry s) async {
    await _client.from('channel_schedule').insert(s.toInsertMap());
  }

  static Future<void> updateScheduleEntry(
    String id,
    Map<String, dynamic> patch,
  ) async {
    await _client.from('channel_schedule').update(patch).eq('id', id);
  }

  static Future<void> deleteScheduleEntry(String id) async {
    await _client.from('channel_schedule').delete().eq('id', id);
  }

  /// Resolves the currently-active episode for a channel using the
  /// `get_current_program` Postgres function (server-side airing >
  /// scheduled > channel default). Returns the raw row so callers can
  /// distinguish a genuine "on the air" program (`is_airing == true`)
  /// from a schedule/default fallback. `null` when nothing resolves.
  static Future<Map<String, dynamic>?> getCurrentProgramRaw(
    String channelId,
  ) async {
    try {
      final res = await _client.rpc(
        'get_current_program',
        params: {'p_channel_id': channelId},
      );
      if (res is List && res.isNotEmpty) {
        final row = Map<String, dynamic>.from(res.first as Map);
        if (row['episode_id'] != null) return row;
      }
      return null;
    } catch (e) {
      if (kDebugMode) debugPrint('getCurrentProgramRaw error: $e');
      return null;
    }
  }

  static Future<Episode?> getCurrentProgram(String channelId) async {
    final row = await getCurrentProgramRaw(channelId);
    if (row != null) {
      final episodeId = row['episode_id'] as String?;
      if (episodeId != null && episodeId.isNotEmpty) {
        try {
          return await getEpisodeById(episodeId);
        } catch (_) {}
      }
    }
    // Fallback: try channel default_episode_id directly
    final channel = await _client
        .from('channels')
        .select()
        .eq('id', channelId)
        .maybeSingle();
    final defaultId = channel?['default_episode_id'] as String?;
    if (defaultId != null) return getEpisodeById(defaultId);
    return null;
  }

  // ---------------------------------------------------------------
  // Playback program queue / Up Next (migration 007 RPCs)
  // ---------------------------------------------------------------

  /// Currently ELIGIBLE episodes for a channel, in canonical playback
  /// order (`get_channel_program_queue`). Episodes reserved by a future
  /// one-off schedule slot are excluded by the server so a scheduled
  /// premiere never plays early.
  static Future<List<Episode>> getChannelProgramQueue(String channelId) async {
    final res = await _client.rpc(
      'get_channel_program_queue',
      params: {'p_channel_id': channelId},
    );
    return (res as List).map((m) => Episode.fromMap(m)).toList();
  }

  /// Nearest schedule entry (one-off or recurring anchor) for a specific
  /// episode on a channel.
  static Future<ScheduleEntry?> getNextScheduleEntry(
    String channelId,
    String episodeId,
  ) async {
    final res = await _client.rpc(
      'get_next_schedule',
      params: {'p_channel_id': channelId, 'p_episode_id': episodeId},
    );
    if (res is List && res.isNotEmpty) {
      final row = Map<String, dynamic>.from(res.first as Map);
      return ScheduleEntry(
        id: row['schedule_id'] as String,
        channelId: channelId,
        episodeId: episodeId,
        startTime: _parseRpcTimestamp(row['start_time']),
        endTime:
            row['end_time'] != null ? _parseRpcTimestamp(row['end_time']) : null,
        dayOfWeek: (row['day_of_week'] as num?)?.toInt(),
        priority: 0,
        enabled: true,
      );
    }
    return null;
  }

  /// Soonest upcoming "announcement": the channel's next one-off scheduled
  /// program or next weekly recurrence, joined with episode + channel
  /// display fields (see `get_next_scheduled_program`).
  static Future<Map<String, dynamic>?> getNextScheduledProgram(
    String channelId,
  ) async {
    final res = await _client.rpc(
      'get_next_scheduled_program',
      params: {'p_channel_id': channelId},
    );
    if (res is List && res.isNotEmpty) {
      final row = Map<String, dynamic>.from(res.first as Map);
      // Normalize timestamps to UTC instants for the UI.
      if (row['start_time'] != null) {
        row['start_time'] = _parseRpcTimestamp(row['start_time']);
      }
      if (row['end_time'] != null) {
        row['end_time'] = _parseRpcTimestamp(row['end_time']);
      }
      return row;
    }
    return null;
  }

  static DateTime _parseRpcTimestamp(Object? raw) {
    if (raw is String) {
      final parsed = DateTime.tryParse(raw);
      if (parsed != null) return parsed.toUtc();
    }
    return DateTime.now().toUtc();
  }

  /// Upserts a fetched playlist's videos into `episodes` (server-side,
  /// content-manager-gated RPC from migration 007).
  static Future<List<PlaylistImportResult>> importPlaylistVideos({
    required String channelId,
    required String playlistId,
    String? defaultShowId,
    required List<Map<String, dynamic>> items,
  }) async {
    final res = await _client.rpc(
      'import_playlist_videos',
      params: {
        'p_channel_id': channelId,
        'p_playlist_id': playlistId,
        'p_default_show_id': defaultShowId,
        'p_items': items,
      },
    );
    return (res as List)
        .map((m) => PlaylistImportResult.fromMap(Map<String, dynamic>.from(m as Map)))
        .toList();
  }

  /// Rewrites a channel's episode sort_order to match [episodeIds]
  /// (admin-only RPC from migration 007).
  static Future<void> reorderEpisodes(
    String channelId,
    List<String> episodeIds,
  ) async {
    await _client.rpc(
      'reorder_episodes',
      params: {'p_channel_id': channelId, 'p_episode_ids': episodeIds},
    );
  }

  // ---------------------------------------------------------------
  // Site settings
  // ---------------------------------------------------------------
  static Future<Map<String, dynamic>> getPublicSettings() async {
    return _cached('site_settings', () async {
      final res = await _client
          .from('site_settings')
          .select()
          .eq('is_public', true);
      final Map<String, dynamic> out = {};
      for (final row in (res as List)) {
        out[row['key'] as String] = row['value'];
      }
      return out;
    });
  }

  static Future<void> upsertSetting(
    String key,
    dynamic value, {
    bool isPublic = true,
  }) async {
    await _client.from('site_settings').upsert({
      'key': key,
      'value': value,
      'is_public': isPublic,
    }, onConflict: 'key');
    _invalidate('site_settings');
  }

  /// Key of the admin-controlled "loop playback" switch. When enabled each
  /// channel repeats its episode queue forever (last episode wraps back to
  /// the first); when disabled playback stops after the final episode.
  static const String loopChannelsSettingKey = 'loop_channels_enabled';

  /// Reads the admin's loop-playback preference. Missing/invalid rows and
  /// network failures fall back to `true` (looping is the default).
  static Future<bool> getLoopChannelsEnabled() async {
    try {
      final settings = await getPublicSettings();
      return parseBoolSetting(settings[loopChannelsSettingKey]) ?? true;
    } catch (_) {
      return true;
    }
  }

  /// Coerces a JSON value from `site_settings.value` into a [bool].
  /// Tolerates real booleans (`true`), SQL-style strings (`'true'`,
  /// `'false'`) and numbers (`1`/`0`).
  static bool? parseBoolSetting(Object? raw) {
    if (raw is bool) return raw;
    if (raw is num) return raw != 0;
    if (raw is String) {
      final t = raw.trim().toLowerCase();
      if (t == 'true' || t == 'yes' || t == '1' || t == 'on') return true;
      if (t == 'false' || t == 'no' || t == '0' || t == 'off') return false;
    }
    return null;
  }

  // ---------------------------------------------------------------
  // Featured content
  // ---------------------------------------------------------------
  static Future<List<Map<String, dynamic>>> getFeaturedContent() async {
    return _cached('featured_content', () async {
      final res = await _client
          .from('featured_content')
          .select()
          .eq('enabled', true)
          .order('sort_order');
      return (res as List).cast<Map<String, dynamic>>();
    });
  }

  // ---------------------------------------------------------------
  // Audit log convenience RPC
  // ---------------------------------------------------------------

  /// Canonical UUID shape — used to keep `log_admin_action`'s
  /// `p_entity_id uuid` argument happy. Admin flows that log about
  /// non-row entities (settings keys, "all channels") must NOT pass a
  /// free-form string here: PostgREST cannot cast it and the whole
  /// request (including the real write that preceded it) looks like a
  /// failure to the UI.
  static final RegExp _uuidPattern = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
    r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  /// Returns [id] only when it is actually a UUID, otherwise `null`
  /// (so the RPC falls back to its null default instead of failing).
  static Object? _asUuidOrNull(String? id) {
    if (id != null && _uuidPattern.hasMatch(id)) return id;
    return null;
  }

  static Future<void> logAdminAction(
    String action, {
    String? entityType,
    String? entityId,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      await _client.rpc(
        'log_admin_action',
        params: {
          'p_action': action,
          'p_entity_type': entityType,
          'p_entity_id': _asUuidOrNull(entityId),
          'p_metadata': metadata ?? {},
        },
      );
    } catch (e) {
      if (kDebugMode) debugPrint('logAdminAction error: $e');
    }
  }

  static Future<List<Map<String, dynamic>>> getAuditLogs({
    int limit = 100,
  }) async {
    final res = await _client
        .from('audit_logs')
        .select()
        .order('created_at', ascending: false)
        .limit(limit);
    return (res as List).cast<Map<String, dynamic>>();
  }

  // ---------------------------------------------------------------
  // Profiles / user management
  // ---------------------------------------------------------------
  static Future<List<Map<String, dynamic>>> getAllProfiles() async {
    final res = await _client.from('profiles').select().order('created_at');
    return (res as List).cast<Map<String, dynamic>>();
  }

  static Future<void> promoteUserToRole(String userId, String newRole) async {
    await _client.rpc(
      'promote_user_to_role',
      params: {'target_user_id': userId, 'new_role': newRole},
    );
  }

  static Future<void> setProfileActive(String userId, bool active) async {
    await _client
        .from('profiles')
        .update({'is_active': active})
        .eq('id', userId);
  }
}

/// Value stored by [ContentService]'s in-memory read cache. Expires after
/// the configured TTL so reference data never goes stale for long.
class _CachedValue {
  final Object? value;
  final DateTime expiresAt;

  _CachedValue(this.value, this.expiresAt);

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}
