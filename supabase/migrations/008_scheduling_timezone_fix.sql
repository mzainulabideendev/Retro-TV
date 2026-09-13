-- =====================================================================
-- Retro TV — Migration 008: Fix recurring weekly scheduling timezone
-- =====================================================================
-- ROOT CAUSE: recurring weekly schedule slots were normalized, matched and
-- predicted entirely in UTC. When the configured scheduling timezone
-- differs from UTC, an evening slot in a timezone WEST of UTC aired a DAY
-- EARLY (and the admin/Up-Next display showed the wrong weekday):
--
--   Example: scheduling tz = America/New_York (UTC-5).
--   Admin schedules "Friday 8:00 PM" weekly (day_of_week=5).
--     * Client wall clock 20:00 Fri -> UTC 01:00 Sat.
--     * Old trigger re-anchored it to Friday 01:00 UTC.
--     * Old get_current_program matched weekday 5 + time 01:00 in UTC
--       => fires Thursday 20:00 local. One day early. Wrong.
--
-- FIX: every recurring-weekly computation now happens in the SCHEDULING
-- TIMEZONE (the same zone documented in lib/services/scheduling_timezone.dart
-- and migration 007). One-off dated slots are exact UTC instants and were
-- already correct — they are untouched.
--
-- SAFE TO RE-RUN: every object below is CREATE OR REPLACE on its own.
-- Existing recurring rows created under the old UTC-normalization will show
-- the wrong wall time after this upgrade in non-UTC zones — recreate them.
-- =====================================================================

-- ---------------------------------------------------------------------
-- scheduling timezone helper: IANA name from site_settings, default UTC
-- (handles both the JSON-encoded '"UTC"' form and a plain string).
-- ---------------------------------------------------------------------
create or replace function public.scheduling_tz()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    nullif(
      replace(
        (select value::text from public.site_settings
          where key = 'scheduling_timezone'
          limit 1),
        '"', ''
      ),
      ''
    ),
    'UTC'
  );
$$;

comment on function public.scheduling_tz() is 'Resolves the configured scheduling timezone (IANA name) used for all recurring-slot wall-clock math, falling back to UTC.';

-- ---------------------------------------------------------------------
-- next weekly occurrence helper: returns the soonest UTC instant STRICTLY
-- AFTER p_at at which a recurring anchor fires, computed in the scheduling
-- timezone so DST zones recur at the same local wall time every week.
-- ---------------------------------------------------------------------
create or replace function public.next_weekly_occurrence(
  p_anchor timestamptz,
  p_at     timestamptz default now()
)
returns timestamptz
language plpgsql
stable
set search_path = public
as $$
declare
  v_tz text := public.scheduling_tz();
  v_now timestamp;
  v_anchor timestamp;
  v_candidate timestamp;
begin
  v_now := (p_at at time zone v_tz)::timestamp;
  v_anchor := (p_anchor at time zone v_tz)::timestamp;
  -- date_trunc('week', ...) starts on MONDAY; convert the stored local
  -- weekday (0=Sunday..6=Saturday) into "days since Monday":
  --   ((dow + 6) % 7): Sun->6 Mon->0 Tue->1 ... Sat->5
  v_candidate := date_trunc('week', v_now)
                 + (((extract(dow from v_anchor))::int + 6) % 7) * interval '1 day'
                 + v_anchor::time;
  if v_candidate <= v_now then
    v_candidate := v_candidate + interval '7 days';
  end if;
  return v_candidate at time zone v_tz;
end;
$$;

comment on function public.next_weekly_occurrence(timestamptz, timestamptz) is 'Soonest future occurrence (in UTC) of a recurring weekly slot anchor, computed in the scheduling timezone.';

-- ---------------------------------------------------------------------
-- corrected schedule trigger: normalize recurring anchors in the
-- scheduling timezone so the stored time-of-day IS the intended wall-clock
-- time and the date part is this week's matching weekday in that zone.
-- ---------------------------------------------------------------------
create or replace function public.validate_schedule_entry()
returns trigger
language plpgsql
as $$
declare
  v_tz text := public.scheduling_tz();
begin
  if new.day_of_week is null then
    -- One-off dated slot: must be in the future. (Updates that leave the
    -- slot's own start_time untouched are allowed so admins can still
    -- edit notes/enabled on an already-aired entry.)
    if (old.start_time is null or new.start_time <> old.start_time)
       and new.start_time <= now() then
      raise exception 'The selected date and time has already passed. Choose a future date and time.';
    end if;
  else
    -- Recurring weekly template: re-anchor to THIS week's matching weekday
    -- in the scheduling timezone. The time-of-day is the admin's wall-clock
    -- time; the date part is only used for display/edit round-trips.
    new.start_time := (
      date_trunc('week', now() at time zone v_tz)
      + (((new.day_of_week + 6) % 7)::int) * interval '1 day'
      + (new.start_time at time zone v_tz)::time
    ) at time zone v_tz;
    if new.end_time is not null then
      new.end_time := (
        date_trunc('week', now() at time zone v_tz)
        + (((new.day_of_week + 6) % 7)::int) * interval '1 day'
        + (new.end_time at time zone v_tz)::time
      ) at time zone v_tz;
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
-- corrected get_current_program: recurring slots match the LOCAL weekday
-- and LOCAL time-of-day in the scheduling timezone (one-off unchanged).
-- ---------------------------------------------------------------------
create or replace function public.get_current_program(
  p_channel_id uuid,
  p_at timestamptz default now()
)
returns table (
  episode_id uuid,
  schedule_id uuid,
  start_time timestamptz,
  end_time timestamptz,
  is_default boolean
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_tz text := public.scheduling_tz();
  v_local_dow integer := extract(dow from (p_at at time zone v_tz))::integer;
begin
  -- 1) One-off dated schedule entries covering "now" (highest specificity).
  --    Pure UTC instant comparisons — exact by definition.
  return query
    select cs.episode_id, cs.id, cs.start_time, cs.end_time, false
    from public.channel_schedule cs
    where cs.channel_id = p_channel_id
      and cs.enabled = true
      and cs.day_of_week is null
      and cs.start_time <= p_at
      and (cs.end_time is null or cs.end_time > p_at)
    order by cs.priority desc, cs.start_time desc
    limit 1;

  if found then
    return;
  end if;

  -- 2) Recurring weekly slots matching the SCHEDULING TZ weekday + time.
  return query
    select cs.episode_id, cs.id, cs.start_time, cs.end_time, false
    from public.channel_schedule cs
    where cs.channel_id = p_channel_id
      and cs.enabled = true
      and cs.day_of_week = v_local_dow
      and (cs.start_time at time zone v_tz)::time <= (p_at at time zone v_tz)::time
      and (cs.end_time is null
           or (cs.end_time at time zone v_tz)::time > (p_at at time zone v_tz)::time)
    order by cs.priority desc, cs.start_time desc
    limit 1;

  if found then
    return;
  end if;

  -- 3) Fallback: channel's default_episode_id
  return query
    select c.default_episode_id, null::uuid, null::timestamptz, null::timestamptz, true
    from public.channels c
    where c.id = p_channel_id
      and c.default_episode_id is not null;
end;
$$;

comment on function public.get_current_program(uuid, timestamptz) is 'Resolves the active episode for a channel: one-off dated schedule > recurring weekly schedule (matched in the scheduling timezone) > channel default_episode_id.';

-- ---------------------------------------------------------------------
-- corrected get_next_schedule: recurring occurrences computed in the
-- scheduling timezone via next_weekly_occurrence().
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
  with cand as (
    select
      cs.id,
      cs.day_of_week,
      case
        when cs.day_of_week is null then cs.start_time
        else public.next_weekly_occurrence(cs.start_time, p_at)
      end as occurrence,
      case
        when cs.end_time is null then interval '0 seconds'
        else (cs.end_time - cs.start_time)
      end as dur
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
-- corrected get_next_scheduled_program: same scheduling-tz treatment.
-- ---------------------------------------------------------------------
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
      case
        when cs.day_of_week is null then cs.start_time
        else public.next_weekly_occurrence(cs.start_time, p_at)
      end as occurrence,
      case
        when cs.end_time is null then interval '0 seconds'
        else (cs.end_time - cs.start_time)
      end as dur
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