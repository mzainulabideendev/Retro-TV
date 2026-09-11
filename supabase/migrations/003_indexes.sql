-- =====================================================================
-- Retro TV — Migration 003: Indexes
-- =====================================================================

create index idx_channels_enabled on public.channels(enabled);
create index idx_channels_channel_number on public.channels(channel_number);
create index idx_channels_slug on public.channels(slug);
create index idx_channels_category_id on public.channels(category_id);
create index idx_channels_featured on public.channels(featured) where featured = true;

create index idx_shows_slug on public.shows(slug);
create index idx_shows_channel_id on public.shows(channel_id);
create index idx_shows_category_id on public.shows(category_id);
create index idx_shows_enabled on public.shows(enabled);

create index idx_episodes_show_id on public.episodes(show_id);
create index idx_episodes_channel_id on public.episodes(channel_id);
create index idx_episodes_status on public.episodes(status);
create index idx_episodes_enabled on public.episodes(enabled);
create index idx_episodes_youtube_video_id on public.episodes(youtube_video_id);

create index idx_schedule_channel_start on public.channel_schedule(channel_id, start_time);
create index idx_schedule_day_of_week on public.channel_schedule(day_of_week);
create index idx_schedule_enabled on public.channel_schedule(enabled);

create index idx_profiles_role on public.profiles(role);
create index idx_profiles_is_active on public.profiles(is_active);

create index idx_tv_styles_enabled on public.tv_styles(enabled);
create index idx_tv_styles_sort_order on public.tv_styles(sort_order);

create index idx_categories_enabled on public.categories(enabled);
create index idx_categories_slug on public.categories(slug);

create index idx_favorites_user_id on public.channel_favorites(user_id);

create index idx_featured_content_type_id on public.featured_content(content_type, content_id);
create index idx_featured_enabled on public.featured_content(enabled);

create index idx_audit_logs_user_id on public.audit_logs(user_id);
create index idx_audit_logs_entity on public.audit_logs(entity_type, entity_id);
create index idx_audit_logs_created_at on public.audit_logs(created_at desc);

create index idx_site_settings_key on public.site_settings(key);
