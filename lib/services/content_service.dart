import 'package:flutter/foundation.dart' hide Category;
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import '../models/category.dart';
import '../models/channel.dart';
import '../models/episode.dart';
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
  // TV Styles
  // ---------------------------------------------------------------
  static Future<List<TvStyle>> getTvStyles({bool onlyEnabled = true}) async {
    var query = _client.from('tv_styles').select();
    if (onlyEnabled) query = query.eq('enabled', true);
    final res = await query.order('sort_order');
    return (res as List).map((m) => TvStyle.fromMap(m)).toList();
  }

  static Future<void> createTvStyle(TvStyle style) async {
    await _client.from('tv_styles').insert(style.toInsertMap());
  }

  static Future<void> updateTvStyle(
    String id,
    Map<String, dynamic> patch,
  ) async {
    await _client.from('tv_styles').update(patch).eq('id', id);
  }

  static Future<void> deleteTvStyle(String id) async {
    await _client.from('tv_styles').delete().eq('id', id);
  }

  // ---------------------------------------------------------------
  // Categories
  // ---------------------------------------------------------------
  static Future<List<Category>> getCategories({bool onlyEnabled = true}) async {
    var query = _client.from('categories').select();
    if (onlyEnabled) query = query.eq('enabled', true);
    final res = await query.order('sort_order');
    return (res as List).map((m) => Category.fromMap(m)).toList();
  }

  static Future<void> createCategory(Category c) async {
    await _client.from('categories').insert(c.toInsertMap());
  }

  static Future<void> updateCategory(
    String id,
    Map<String, dynamic> patch,
  ) async {
    await _client.from('categories').update(patch).eq('id', id);
  }

  static Future<void> deleteCategory(String id) async {
    await _client.from('categories').delete().eq('id', id);
  }

  // ---------------------------------------------------------------
  // Channels
  // ---------------------------------------------------------------
  static Future<List<Channel>> getChannels({bool onlyEnabled = true}) async {
    var query = _client.from('channels').select();
    if (onlyEnabled) query = query.eq('enabled', true);
    final res = await query.order('channel_number');
    return (res as List).map((m) => Channel.fromMap(m)).toList();
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
    } on PostgrestException catch (e) {
      if (e.code == '23505') {
        throw Exception('Channel number or slug already exists.');
      }
      rethrow;
    }
  }

  static Future<void> deleteChannel(String id) async {
    await _client.from('channels').delete().eq('id', id);
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
    final res = await _client
        .from('episodes')
        .select()
        .eq('id', id)
        .maybeSingle();
    return res != null ? Episode.fromMap(res) : null;
  }

  static Future<String> createEpisode(Episode e) async {
    try {
      final res = await _client
          .from('episodes')
          .insert(e.toInsertMap())
          .select('id')
          .single();
      final id = res['id'] as String;
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
  /// `get_current_program` Postgres function (schedule-aware, falls back
  /// to the channel's default episode).
  static Future<Episode?> getCurrentProgram(String channelId) async {
    try {
      final res = await _client.rpc(
        'get_current_program',
        params: {'p_channel_id': channelId},
      );
      if (res is List && res.isNotEmpty) {
        final episodeId = res.first['episode_id'] as String?;
        if (episodeId != null) {
          return getEpisodeById(episodeId);
        }
      }
      return null;
    } catch (e) {
      if (kDebugMode) debugPrint('getCurrentProgram error: $e');
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
  }

  // ---------------------------------------------------------------
  // Site settings
  // ---------------------------------------------------------------
  static Future<Map<String, dynamic>> getPublicSettings() async {
    final res = await _client
        .from('site_settings')
        .select()
        .eq('is_public', true);
    final Map<String, dynamic> out = {};
    for (final row in (res as List)) {
      out[row['key'] as String] = row['value'];
    }
    return out;
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
  }

  // ---------------------------------------------------------------
  // Featured content
  // ---------------------------------------------------------------
  static Future<List<Map<String, dynamic>>> getFeaturedContent() async {
    final res = await _client
        .from('featured_content')
        .select()
        .eq('enabled', true)
        .order('sort_order');
    return (res as List).cast<Map<String, dynamic>>();
  }

  // ---------------------------------------------------------------
  // Audit log convenience RPC
  // ---------------------------------------------------------------
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
          'p_entity_id': entityId,
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
