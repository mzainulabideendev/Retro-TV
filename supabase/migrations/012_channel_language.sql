-- =====================================================================
-- Retro TV — Migration 012: Channel (Cartoon) Language
-- =====================================================================
-- Adds a language tag to every channel so an admin can record which
-- language the uploaded cartoon / audio is in, and viewers can filter the
-- Channel Guide down to cartoons in their own language.
--
--   * language = 'en' / 'hi' / 'ur' / ...  -> one of the shared codes in
--     `lib/models/channel_language.dart`.
--   * language = NULL                       -> unspecified (channels that
--     existed before this migration; the guide still shows them under
--     "All languages").
--
-- The column is public-readable (channels are public) and admin-writable
-- via the existing channels_admin_update RLS policy, so no new policies
-- are required.
-- =====================================================================

alter table public.channels
  add column if not exists language text;

comment on column public.channels.language is
  'Language code of the cartoon/audio uploaded for this channel (e.g. en, hi, ur). NULL means unspecified; see lib/models/channel_language.dart for the shared list.';

-- Speeds up language filters on larger channel line-ups.
create index if not exists idx_channels_language
  on public.channels (language);
