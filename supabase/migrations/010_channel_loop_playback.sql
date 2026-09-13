-- =====================================================================
-- Retro TV — Migration 010: Per-Channel Loop Playback
-- =====================================================================
-- Adds a per-channel loop switch so an admin can tune loop playback for
-- ANY single channel, or (with the "apply to all" controls in Settings)
-- for ALL channels at once.
--
--   * loop_playback = TRUE  -> this channel repeats its episodes forever
--                              (1, 2, 3, ... n, then back to 1).
--   * loop_playback = FALSE -> this channel stops ("Channel unavailable")
--                              after its final episode instead of wrapping.
--   * loop_playback = NULL  -> follow the global loop_channels_enabled
--                              site setting (the default for all channels).
--
-- NULL is the default so nothing changes for existing channels until an
-- admin explicitly tunes one. The column is public-readable (channels are
-- public) and admin-writable via the existing channels_admin_update RLS
-- policy, so no new policies are required.
-- =====================================================================

alter table public.channels
  add column if not exists loop_playback boolean;

comment on column public.channels.loop_playback is
  'Per-channel loop override: TRUE loops forever, FALSE stops after the final episode, NULL follows the global loop_channels_enabled site setting.';