-- =====================================================================
-- Retro TV — Migration 007: Scheduling integrity, playlist import,
-- timezone strategy & validation
-- =====================================================================
-- This migration is SAFE for production databases: it only ADDS columns,
-- indexes and triggers. It never drops or resets existing data.
--
-- TIMEZONE STRATEGY (applies to the whole scheduling flow):
--   * All schedule timestamps are stored as timestamptz (UTC) in Postgres.
--   * The "scheduling timezone" is an IANA name stored in site_settings
--     under the key 'scheduling_timezone' (default 'UTC').
--   * Admin DATE+TIME input is interpreted as WALL-CLOCK time in the
--     scheduling timezone, then converted to UTC before being INSERTED.
--   * The user/player side compares against UTC only (no local conversion).
--   * Admin UI displays timestamps back in the SAME scheduling timezone.
--   This single, consistent strategy eliminates the "aired a day early /
--   a day late" class of bugs caused by mixing device-local and server
--   naive timestamps.
-- =====================================================================

-- ---------------------------------------------------------------------
-- helpers (must exist before functions that use them)
-- ---------------------------------------------------------------------
create or replace function public.youtube_thumb(p_video_id text)
returns text
language sql
immutable
as $$
  select 'https://img.youtube.com/vi/' || p_video_id || '/hqdefault.jpg';
$$;

-- ---------------------------------------------------------------------
-- episodes: add YouTube playlist import metadata
-- ---------------------------------------------------------------------
alter table public.episodes
  add column if not exists youtube_playlist_id text;

alter table public.episodes
  add column if not exists playlist_position integer
    check (playlist_position is null or playlist_position >= 1);

comment on column public.episodes.youtube_playlist_id is 'Source YouTube playlist id when the episode was imported from a playlist (NULL for manually added videos).';
comment on column public.episodes.playlist_position is '1-based position of the video inside its source YouTube playlist, preserved on import.';

-- Deduplication: the SAME video (youtube_video_id) may appear once per
-- playlist. Re-importing a playlist must not create duplicate rows; a
-- video that legitimately exists in two different playlists is still
-- allowed (playlist_id participates in the key).
create unique index if not exists uq_episodes_playlist_video
  on public.episodes (youtube_playlist_id, youtube_video_id)
  where youtube_playlist_id is not null;

-- Efficient ordered playback lookups per playlist.
create index if not exists idx_episodes_playlist_position
  on public.episodes (youtube_playlist_id, playlist_position);

-- ---------------------------------------------------------------------
-- episodes: server-side validation trigger
-- ---------------------------------------------------------------------
-- Authoritative server-side validation that always runs regardless of
-- which client wrote the row. Mirrors the client-side checks so no
-- invalid or incomplete record can ever be stored.
-- =====================================================================
create or replace function public.validate_episode()
returns trigger
language plpgsql
as $$
begin
  if new.title is null or length(trim(new.title)) = 0 then
    raise exception 'Episode title is required';
  end if;

  if new.youtube_video_id is null or length(trim(new.youtube_video_id)) = 0 then
    raise exception 'A valid YouTube video ID is required';
  end if;
  if public.normalize_youtube_id(new.youtube_video_id) is null then
    raise exception 'Invalid YouTube video ID "%"', new.youtube_video_id;
  end if;

  if new.youtube_playlist_id is not null
     and new.youtube_playlist_id !~ '^[A-Za-z0-9_-]{10,}$' then
    raise exception 'Invalid YouTube playlist ID "%"', new.youtube_playlist_id;
  end if;

  if new.playlist_position is not null and new.youtube_playlist_id is null then
    raise exception 'playlist_position requires a youtube_playlist_id';
  end if;

  -- Keep the lifecycle dates honest
  if new.status = 'published'
     and (old.status is distinct from 'published' or new.published_at is null) then
    new.published_at := coalesce(new.published_at, new.updated_at, now());
  end if;

  return new;
end;
$$;

drop trigger if exists trg_episodes_validate on public.episodes;
create trigger trg_episodes_validate
  before insert or update on public.episodes
  for each row execute function public.validate_episode();

-- ---------------------------------------------------------------------
-- channel_schedule: duplicate + past-date protection
-- ---------------------------------------------------------------------
-- Prevent two identical one-off slots for the same episode on the same
-- channel. (Recurring day_of_week templates are excluded from this key
-- deliberately — an episode may air on multiple weekdays.)
create unique index if not exists uq_schedule_channel_episode_start
  on public.channel_schedule (channel_id, episode_id, start_time)
  where enabled = true and day_of_week is null;

-- Fast "currently scheduled / reserved upcoming" lookups.
create index if not exists idx_schedule_onedate_upcoming
  on public.channel_schedule (channel_id, start_time)
  where day_of_week is null;

-- =====================================================================
-- Past-time rule:
--   * One-off dated slots (day_of_week IS NULL) must NOT start in the
--     past. This app does not support historical/back-dated scheduling.
--   * Recurring weekly templates keep a canonical UTC weekday anchor
--     (only the UTC time-of-day and weekday matter for matching), so an
--     update never blocks just because an anchor date is in the past.
-- =====================================================================
create or replace function public.validate_schedule_entry()
returns trigger
language plpgsql
as $$
begin
  if new.day_of_week is null then
    -- One-off dated slot: must be in the future. (Updates that leave the
    -- slot's own start_time untouched are allowed so admins can still
    -- edit notes/enabled on an already-aired entry without triggering a
    -- "past date" rejection.)
    if (old.start_time is null or new.start_time <> old.start_time)
       and new.start_time <= now() then
      raise exception 'The selected date and time has already passed. Choose a future date and time.';
    end if;
  else
    -- Recurring weekly template: normalise to a canonical UTC weekday
    -- anchor so `extract(dow from start_time)` matches day_of_week under
    -- the UTC session timezone used by get_current_program().
    new.start_time := (
      date_trunc('week', now() at time zone 'UTC')
      + new.day_of_week * interval '1 day'
      + (new.start_time at time zone 'UTC')::time
    ) at time zone 'UTC';
    if new.end_time is not null then
      new.end_time := (
        date_trunc('week', now() at time zone 'UTC')
        + new.day_of_week * interval '1 day'
        + (new.end_time at time zone 'UTC')::time
      ) at time zone 'UTC';
    end if;
    if new.end_time is not null and new.end_time <= new.start_time then
      raise exception 'End time must be after the start time';
    end if;
  end if;

  if new.end_time is not null and new.end_time <= new.start_time then
    raise exception 'End time must be after the start time';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_schedule_validate on public.channel_schedule;
create trigger trg_schedule_validate
  before insert or update on public.channel_schedule
  for each row execute function public.validate_schedule_entry();

-- ---------------------------------------------------------------------
-- channel program queue (used by the player & "Up Next")
-- ---------------------------------------------------------------------
-- Returns ONLY the episodes that are currently ELIGIBLE for a channel,
-- in canonical playback order:
--   sort_order -> playlist position -> episode number -> created_at.
--
-- Eligibility rule: an episode is playable right now unless it is
-- "reserved" by a future one-off schedule entry (start_time not reached
-- yet). Reserved episodes are EXCLUDED so they can never play early. The
-- moment their scheduled start time arrives the reservation disappears
-- and they automatically join the continuous loop — no manual activation
-- needed by admin or player.
--
-- Comparisons are pure UTC (timestamptz), matching the storage strategy.
-- =====================================================================
create or replace function public.get_channel_program_queue(
  p_channel_id uuid,
  p_at timestamptz default now(),
  p_limit integer default 500
)
returns table (
  id uuid,
  title text,
  description text,
  youtube_video_id text,
  youtube_url text,
  thumbnail_url text,
  duration_seconds integer,
  episode_number integer,
  season_number integer,
  sort_order integer,
  youtube_playlist_id text,
  playlist_position integer,
  channel_id uuid,
  show_id uuid,
  status text,
  enabled boolean,
  air_date timestamptz,
  category_id uuid
)
language sql
stable
security definer
set search_path = public
as $$
  select
    e.id, e.title, e.description, e.youtube_video_id, e.youtube_url,
    e.thumbnail_url, e.duration_seconds, e.episode_number, e.season_number,
    e.sort_order, e.youtube_playlist_id, e.playlist_position,
    e.channel_id, e.show_id, e.status, e.enabled, e.air_date, e.category_id
  from public.episodes e
  where e.channel_id = p_channel_id
    and e.enabled = true
    and e.status = 'published'
    and not exists (
      select 1
      from public.channel_schedule cs
      where cs.channel_id = p_channel_id
        and cs.episode_id = e.id
        and cs.enabled = true
        and cs.day_of_week is null
        and cs.start_time > p_at
    )
  order by
    e.sort_order asc,
    e.playlist_position asc nulls last,
    e.episode_number asc nulls last,
    e.created_at asc
  limit greatest(1, p_limit);
$$;

comment on function public.get_channel_program_queue(uuid, timestamptz, integer) is 'Eligible episodes for a channel in canonical playback order. Episodes reserved by a future one-off schedule slot are excluded so they never play early; they automatically join the queue when their scheduled start time arrives. SECURITY DEFINER — only public-safe fields are returned (no secrets).';

-- ---------------------------------------------------------------------
-- next scheduled showtime for an episode (used by the "Up Next" card)
-- ---------------------------------------------------------------------
create or replace function public.get_next_schedule(
  p_channel_id uuid,
  p_episode_id uuid,
  p_at timestamptz default now()
)
returns table (
  schedule_id uuid,
  start_time timestamptz,
  end_time timestamptz,
  day_of_week integer
)
language sql
stable
security definer
set search_path = public
as $$
  -- One-off dated slots must be strictly in the future; recurring weekly
  -- templates are rolled forward week-by-week from their (canonical UTC)
  -- anchor so even a stale anchor predicts the next real occurrence.
  with cand as (
    select
      cs.id,
      cs.day_of_week,
      (case
        when cs.day_of_week is null then cs.start_time
        when cs.start_time > p_at then cs.start_time
        else cs.start_time
          + interval '7 days' * (floor(extract(epoch from (p_at - cs.start_time)) / 604800.0) + 1)
      end)::timestamptz as occurrence,
      (case when cs.end_time is null then interval '0' else (cs.end_time::time - cs.start_time::time) end) as dur
    from public.channel_schedule cs
    where cs.channel_id = p_channel_id
      and cs.episode_id = p_episode_id
      and cs.enabled = true
      and (
        (cs.day_of_week is null and cs.start_time > p_at)
        or cs.day_of_week is not null
      )
  )
  select c.id, c.occurrence, c.occurrence + c.dur, c.day_of_week
  from cand c
  order by c.occurrence asc
  limit 1;
$$;

-- ---------------------------------------------------------------------
-- soonest upcoming scheduled program for a channel ("announcement" card)
-- Handles BOTH one-off dated slots (must be strictly future) and weekly
-- recurring templates, which are rolled forward week-by-week from their
-- canonical UTC anchor so a stale anchor still predicts the real next
-- occurrence. Pure UTC comparisons end to end.
-- =====================================================================
create or replace function public.get_next_scheduled_program(
  p_channel_id uuid,
  p_at timestamptz default now()
)
returns table (
  episode_id uuid,
  title text,
  thumbnail_url text,
  youtube_video_id text,
  channel_number integer,
  channel_name text,
  start_time timestamptz,
  end_time timestamptz,
  day_of_week integer,
  recurring boolean
)
language sql
stable
security definer
set search_path = public
as $$
  -- "Next program" means the soonest FUTURE occurrence: one-off dated slots
  -- must be strictly ahead of p_at, and recurring weekly templates are rolled
  -- forward from their canonical UTC anchor (so stale anchors from legacy
  -- data still predict correctly).
  with cand as (
    select
      cs.id,
      e.id as episode_id,
      e.title,
      e.thumbnail_url,
      e.youtube_video_id,
      ch.channel_number,
      ch.name as channel_name,
      cs.day_of_week,
      (case
        when cs.day_of_week is null then cs.start_time
        when cs.start_time > p_at then cs.start_time
        else cs.start_time
          + interval '7 days' * (floor(extract(epoch from (p_at - cs.start_time)) / 604800.0) + 1)
      end)::timestamptz as occurrence,
      (case when cs.end_time is null then interval '0' else (cs.end_time::time - cs.start_time::time) end) as dur
    from public.channel_schedule cs
    join public.episodes e on e.id = cs.episode_id
    join public.channels ch on ch.id = cs.channel_id
    where cs.channel_id = p_channel_id
      and cs.enabled = true
      and (
        (cs.day_of_week is null and cs.start_time > p_at)
        or cs.day_of_week is not null
      )
  )
  select c.episode_id, c.title, c.thumbnail_url, c.youtube_video_id,
         c.channel_number, c.channel_name,
         c.occurrence, c.occurrence + c.dur, c.day_of_week,
         (c.day_of_week is not null)
  from cand c
  order by c.occurrence asc
  limit 1;
$$;

comment on function public.get_next_scheduled_program(uuid, timestamptz) is 'Soonest upcoming scheduled program for a channel (one-off or next weekly recurrence), returned together with episode + channel display info for the "Up Next / announcement" card. SECURITY DEFINER.';

-- ---------------------------------------------------------------------
-- reorder_episodes(channel_id, ordered episode ids)
-- Rewrites sort_order of a channel's episodes to match the given order
-- (1..N). sort_order drives canonical playback ordering. Admin-only.
-- =====================================================================
create or replace function public.reorder_episodes(
  p_channel_id uuid,
  p_episode_ids uuid[]
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  i integer;
begin
  if not public.is_admin() then
    raise exception 'Unauthorized. Admin access is required to reorder episodes.';
  end if;

  if p_episode_ids is null or array_length(p_episode_ids, 1) = 0 then
    raise exception 'No episodes provided';
  end if;

  for i in 1 .. array_length(p_episode_ids, 1)
  loop
    update public.episodes
    set sort_order = i
    where id = p_episode_ids[i] and channel_id = p_channel_id;
  end loop;
end;
$$;

-- ---------------------------------------------------------------------
-- playlist import (server-side, content-manager only)
-- ---------------------------------------------------------------------
-- Accepts the items fetched from a playlist (via the Edge Function using
-- the YouTube Data API, or the keyless RSS fallback) and upserts them
-- into episodes, deduplicating on (youtube_playlist_id, youtube_video_id).
-- Also flips a channel's default episode to the first imported video when
-- the channel had none, so an imported playlist is immediately watchable.
-- =====================================================================
create or replace function public.import_playlist_videos(
  p_channel_id uuid,
  p_playlist_id text,
  p_items jsonb,
  p_default_show_id uuid default null
)
returns table (episode_id uuid, youtube_video_id text, title text, inserted boolean, error text)
language plpgsql
security definer
set search_path = public
as $$
declare
  item jsonb;
  v_title text;
  v_video_id text;
  v_thumb text;
  v_desc text;
  v_pos integer;
  v_id uuid;
  v_inserted boolean;
  v_first_id uuid := null;
begin
  -- Authorize: content managers only (this is the sanctioned import path).
  if not public.is_content_manager() then
    raise exception 'Unauthorized. Admin access is required to import playlists.';
  end if;

  if not exists (select 1 from public.channels where id = p_channel_id) then
    raise exception 'Selected channel no longer exists. Please pick another channel.';
  end if;

  if p_playlist_id is null or p_playlist_id !~ '^[A-Za-z0-9_-]{10,}$' then
    raise exception 'Invalid YouTube playlist ID "%"', p_playlist_id;
  end if;

  for item in select * from jsonb_array_elements(p_items)
  loop
    v_video_id := item ->> 'youtube_video_id';
    v_title    := item ->> 'title';
    v_thumb    := item ->> 'thumbnail_url';
    v_desc     := item ->> 'description';
    v_pos      := coalesce((item ->> 'playlist_position')::integer, 1);

    if v_video_id is null or v_video_id = '' or v_title is null or v_title = '' then
      -- Report failed/unavailable videos instead of silently dropping them
      return query select
        cast(null as uuid), v_video_id,
        coalesce(v_title, item ->> 'error'), false,
        'Unavailable or missing video metadata';
      continue;
    end if;

    begin
      -- Manual upsert, qualified against the OUT-parameter names in the
      -- RETURNS TABLE clause so PostgreSQL never hits ambiguous column
      -- references (episodes.youtube_video_id vs the OUT param).
      select id into v_id
      from public.episodes
      where episodes.youtube_playlist_id = p_playlist_id
        and episodes.youtube_video_id = v_video_id;

      if v_id is null then
        insert into public.episodes (
          channel_id, show_id, season_number, title, description,
          youtube_video_id, youtube_url, thumbnail_url,
          youtube_playlist_id, playlist_position, status, enabled, sort_order
        )
        values (
          p_channel_id, p_default_show_id, 1, v_title, v_desc,
          v_video_id, 'https://www.youtube.com/watch?v=' || v_video_id,
          coalesce(v_thumb, public.youtube_thumb(v_video_id)),
          p_playlist_id, v_pos, 'published', true, v_pos
        )
        returning id into v_id;
        v_inserted := true;
      else
        update public.episodes
        set title             = v_title,
            description       = v_desc,
            thumbnail_url     = coalesce(v_thumb, public.youtube_thumb(v_video_id)),
            youtube_url       = 'https://www.youtube.com/watch?v=' || v_video_id,
            playlist_position = v_pos,
            channel_id        = p_channel_id,
            show_id           = p_default_show_id,
            status            = 'published',
            enabled           = true
        where episodes.id = v_id;
        v_inserted := false;
      end if;

      if v_first_id is null then
        v_first_id := v_id;
      end if;

      return query select v_id, v_video_id, v_title, v_inserted, cast(null as text);
    exception when others then
      return query select cast(null as uuid), v_video_id, v_title, false, sqlerrm;
    end;
  end loop;

  -- Wire up the channel to the playlist (first video) when it had no
  -- default episode, so the imported content is immediately watchable.
  if v_first_id is not null then
    update public.channels
    set default_episode_id = v_first_id
    where id = p_channel_id and default_episode_id is null;
  end if;
end;
$$;

-- ---------------------------------------------------------------------
-- scheduling_timezone site setting (public so the player can format
-- "Up Next" times in the very same zone the admin scheduled in).
-- =====================================================================
insert into public.site_settings (key, value, is_public)
values ('scheduling_timezone', '"UTC"', true)
on conflict (key) do nothing;