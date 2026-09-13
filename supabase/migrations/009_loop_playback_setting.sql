-- =====================================================================
-- Retro TV — Migration 009: Admin Loop Playback Setting
-- =====================================================================
-- Adds a global admin-controlled switch that governs channel playback:
--
--   * ON  (default): every channel's episodes play back-to-back in the
--     canonical order (1, 2, 3, ... n) and when the last episode ends the
--     loop wraps around and repeats from episode 1 forever.
--
--   * OFF: episodes still play in order (1, 2, 3, ... n) but the channel
--     does NOT wrap around. When the final episode ends, playback stops
--     ("Channel unavailable") instead of jumping back to episode 1.
--
-- The player and the admin "Settings" panel read this row. It is public
-- (is_public = true) on purpose — anonymous viewers use it to decide how
-- to advance the loop, same as the scheduling_timezone setting.
-- =====================================================================

insert into public.site_settings (key, value, is_public)
values ('loop_channels_enabled', 'true', true)
on conflict (key) do nothing;