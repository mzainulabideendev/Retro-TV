-- =====================================================================
-- 011_backend_airing_loop.sql
--
-- Server-side "broadcast" loop.
--
-- The channel playlist now advances on the SERVER via pg_cron, whether or
-- not any TV is open. Each enabled channel carries a small airing state:
--
--   channels.airing_episode_id  — the episode currently "on the air"
--   channels.airing_started_at  — when that episode started
--   channels.airing_ends_at     — when the current window expires
--
-- A one-minute cron job (`channel_air_tick`) walks every enabled channel
-- and:
--   * holds the current episode while its window is still open,
--   * advances to the next eligible episode (canonical order from
--     get_channel_program_queue) once the window expires, wrapping to the
--     top when looping (per-channel loop_playback override, else global
--     loop_channels_enabled),
--   * on a channel that is NOT looping it parks on the final episode
--     (the window keeps refreshing so clients never drop off),
--   * on FIRST activation it prefers the channel's default episode when it
--     is in the queue, otherwise it starts at the top of the queue.
--
-- get_current_program() is overridden to treat this airing state as the
-- single highest-priority source: an open TV takes whatever is genuinely
-- airing, then falls back to one-off schedules, recurring weekly slots and
-- finally default_episode_id. An extra `is_airing` boolean is returned so
-- clients can distinguish "this is the live server program" from a merely
-- resolved fallback.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1) Airing state columns on channels
-- ---------------------------------------------------------------------
alter table public.channels
  add column if not exists airing_episode_id uuid,
  add column if not exists airing_started_at timestamptz,
  add column if not exists airing_ends_at timestamptz;

comment on column public.channels.airing_episode_id is
  'Episode currently on the air for this channel, maintained by the server-side pg_cron loop (channel_air_tick). NULL when nothing is airing yet.';
comment on column public.channels.airing_started_at is
  'When the currently airing episode began (set by channel_air_tick).';
comment on column public.channels.airing_ends_at is
  'When the currently airing window expires; beyond this the cron job advances to the next episode.';

-- ---------------------------------------------------------------------
-- 2) pg_cron extension
-- ---------------------------------------------------------------------
create extension if not exists pg_cron;

-- ---------------------------------------------------------------------
-- 3) The tick function (security definer so it can read everything)
-- ---------------------------------------------------------------------
create or replace function public.channel_air_tick()
returns integer
language plpgsql
security definer
set search_path = public
set statement_timeout = '30s'
as $$
declare
  v_c record;
  v_ids uuid[];
  v_n integer;
  v_idx integer;
  v_found boolean;
  v_loop boolean;
  v_next uuid;
  v_dur integer;
  v_updated integer := 0;
begin
  for v_c in
    select c.id, c.airing_episode_id, c.airing_ends_at,
           c.default_episode_id, c.loop_playback
    from public.channels c
    where c.enabled = true
  loop
    -- Canonical eligible queue in playback order (episodes reserved by a
    -- future one-off slot are excluded server-side).
    select array_agg(t.id order by t.ord) into v_ids
    from (
      select q.id, row_number() over () as ord
      from public.get_channel_program_queue(v_c.id, now()) q
    ) t;

    v_n := 0;
    if v_ids is not null then
      v_n := cardinality(v_ids);
    end if;

    -- Per-channel override wins, otherwise the global site setting.
    v_loop := coalesce(
      v_c.loop_playback,
      (select (s.value #>> '{}')::boolean
         from public.site_settings s
        where s.key = 'loop_channels_enabled')
    );

    v_next := null;

    if v_n > 0 then
      if v_c.airing_episode_id is not null
         and (v_c.airing_ends_at is null or v_c.airing_ends_at > now()) then
        -- Current episode is still within its window: hold it.
        v_next := v_c.airing_episode_id;
      elsif v_c.airing_episode_id is not null then
        -- Window expired: advance to the next episode after the current.
        v_found := false;
        for v_idx in 1..v_n loop
          if v_ids[v_idx] = v_c.airing_episode_id then
            v_found := true;
            if v_idx < v_n then
              v_next := v_ids[v_idx + 1];
            elsif v_loop then
              v_next := v_ids[1];           -- loop back to the top
            else
              v_next := v_c.airing_episode_id; -- park on the final episode
            end if;
            exit;
          end if;
        end loop;
        if not v_found then
          -- Current no longer eligible (disabled/removed): restart at top.
          v_next := v_ids[1];
        end if;
      else
        -- First activation: prefer the channel's default episode when it is
        -- in the queue, otherwise start at the top of the queue.
        v_next := v_ids[1];
        if v_c.default_episode_id is not null then
          for v_idx in 1..v_n loop
            if v_ids[v_idx] = v_c.default_episode_id then
              v_next := v_ids[v_idx];
              exit;
            end if;
          end loop;
        end if;
      end if;

      if v_next is distinct from v_c.airing_episode_id then
        select e.duration_seconds into v_dur
        from public.episodes e where e.id = v_next;
        v_dur := greatest(coalesce(v_dur, 1800), 60);
        update public.channels c set
          airing_episode_id = v_next,
          airing_started_at = now(),
          airing_ends_at = now() + make_interval(secs => v_dur)
        where c.id = v_c.id;
        v_updated := v_updated + 1;
      elsif v_c.airing_ends_at is null then
        -- Same episode still airing but the window timestamp is missing:
        -- backfill it so clients/gateways can rely on the window.
        select e.duration_seconds into v_dur
        from public.episodes e where e.id = v_next;
        v_dur := greatest(coalesce(v_dur, 1800), 60);
        update public.channels c
        set airing_ends_at = now() + make_interval(secs => v_dur)
        where c.id = v_c.id;
      end if;
    else
      -- No eligible episodes at all: nothing can be airing.
      if v_c.airing_episode_id is not null then
        update public.channels c
        set airing_episode_id = null,
            airing_started_at = null,
            airing_ends_at = null
        where c.id = v_c.id;
        v_updated := v_updated + 1;
      end if;
    end if;
  end loop;

  return v_updated;
end;
$$;

comment on function public.channel_air_tick() is
  'Advances the server-side broadcast loop one step for every enabled channel. Returns the number of channels whose airing state changed. Run by pg_cron every minute.';

-- ---------------------------------------------------------------------
-- 4) One-minute cron schedule (idempotent)
-- ---------------------------------------------------------------------
do $$
begin
  if not exists (select 1 from cron.job where jobname = 'retro-tv-airing') then
    perform cron.schedule(
      'retro-tv-airing',
      '* * * * *',
      'select public.channel_air_tick()'
    );
  end if;
end;
$$;

-- ---------------------------------------------------------------------
-- 5) get_current_program override: server airing is the top priority
-- ---------------------------------------------------------------------
-- OUT-param row type changed (added `is_airing`), so the old signature
-- must be dropped before the CREATE OR REPLACE.
drop function if exists public.get_current_program(uuid, timestamptz);

create or replace function public.get_current_program(
  p_channel_id uuid,
  p_at timestamptz default now()
)
returns table (
  episode_id uuid,
  schedule_id uuid,
  start_time timestamptz,
  end_time timestamptz,
  is_default boolean,
  is_airing boolean
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
  -- 0) Server-side broadcast airing (backend loop): the single source of
  --    truth for "what is genuinely on the air right now".
  return query
    select c.airing_episode_id,
           null::uuid,
           c.airing_started_at,
           c.airing_ends_at,
           false,
           true
    from public.channels c
    where c.id = p_channel_id
      and c.airing_episode_id is not null
      and c.airing_started_at is not null
      and (c.airing_ends_at is null or c.airing_ends_at > p_at);

  if found then
    return;
  end if;

  -- 1) One-off dated schedule entries covering "now". Pure UTC instant
  --    comparisons — exact by definition.
  return query
    select cs.episode_id, cs.id, cs.start_time, cs.end_time, false, false
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
    select cs.episode_id, cs.id, cs.start_time, cs.end_time, false, false
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
    select c.default_episode_id, null::uuid, null::timestamptz, null::timestamptz, true, false
    from public.channels c
    where c.id = p_channel_id
      and c.default_episode_id is not null;
end;
$$;

comment on function public.get_current_program(uuid, timestamptz) is
  'Resolves the active episode for a channel: server-side broadcast airing (backend loop) > one-off schedule > recurring weekly (in the scheduling timezone) > default_episode_id. `is_airing` flags episodes produced by the backend loop.';