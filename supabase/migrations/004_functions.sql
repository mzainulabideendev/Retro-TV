-- =====================================================================
-- Retro TV — Migration 004: Functions & Triggers
-- =====================================================================
-- IMPORTANT: All authorization functions below are SECURITY DEFINER and
-- read only from public.profiles using auth.uid(). They are the ONLY
-- source of truth for admin authorization. Never hardcode admin emails
-- anywhere in application code — roles live exclusively in the database.
-- =====================================================================

-- ---------------------------------------------------------------------
-- has_role(required_roles text[])
-- Returns true if the CURRENT authenticated user's profile.role is
-- one of the given roles AND the profile is_active = true.
-- ---------------------------------------------------------------------
create or replace function public.has_role(required_roles text[])
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1 from public.profiles p
    where p.id = auth.uid()
      and p.is_active = true
      and p.role = any(required_roles)
  );
$$;

comment on function public.has_role(text[]) is 'Core role-check primitive. SECURITY DEFINER so it can read profiles regardless of RLS on profiles itself.';

-- ---------------------------------------------------------------------
-- is_super_admin() — full access
-- ---------------------------------------------------------------------
create or replace function public.is_super_admin()
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select public.has_role(array['super_admin']);
$$;

-- ---------------------------------------------------------------------
-- is_admin() — super_admin or admin (channels, shows, episodes, schedules, tv styles, settings)
-- ---------------------------------------------------------------------
create or replace function public.is_admin()
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select public.has_role(array['super_admin', 'admin']);
$$;

comment on function public.is_admin() is 'True for super_admin and admin roles. Used to gate management of channels/shows/episodes/schedules/tv_styles/settings/users(read)/audit_logs.';

-- ---------------------------------------------------------------------
-- is_content_manager() — super_admin, admin, or editor (shows/episodes only)
-- ---------------------------------------------------------------------
create or replace function public.is_content_manager()
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select public.has_role(array['super_admin', 'admin', 'editor']);
$$;

comment on function public.is_content_manager() is 'True for super_admin, admin, and editor. Editors are restricted to shows/episodes content only (never channels/users/settings) via which tables grant this check.';

-- ---------------------------------------------------------------------
-- handle_new_user() — auto-create a profile row when a new auth user signs up.
-- New users default to role=''viewer'' (NOT admin). Admin roles must be
-- granted explicitly via the secure admin-setup process (see ADMIN_SETUP.md).
-- ---------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, email, display_name, role, is_active)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data->>'display_name', split_part(new.email, '@', 1)),
    'viewer',
    true
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------
-- promote_user_to_role() — callable ONLY by a super_admin (enforced inside).
-- Lets a super_admin safely change another user's role without giving
-- blanket UPDATE rights on profiles from the client.
-- ---------------------------------------------------------------------
create or replace function public.promote_user_to_role(target_user_id uuid, new_role text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_super_admin() then
    raise exception 'Only super_admin can change user roles';
  end if;

  if new_role not in ('super_admin','admin','editor','viewer') then
    raise exception 'Invalid role: %', new_role;
  end if;

  update public.profiles
  set role = new_role
  where id = target_user_id;

  insert into public.audit_logs (user_id, action, entity_type, entity_id, metadata)
  values (auth.uid(), 'ADMIN_CHANGED_ROLE', 'profile', target_user_id, jsonb_build_object('new_role', new_role));
end;
$$;

-- ---------------------------------------------------------------------
-- normalize_youtube_id(input text) — extracts an 11-char-ish YouTube
-- video ID from any of the accepted URL formats, or returns the input
-- unchanged if it already looks like a bare video ID.
-- Used as a defensive server-side check; the Flutter app performs the
-- same extraction client-side for immediate form feedback.
-- ---------------------------------------------------------------------
create or replace function public.normalize_youtube_id(input text)
returns text
language plpgsql
immutable
as $$
declare
  m text[];
begin
  if input is null or length(trim(input)) = 0 then
    return null;
  end if;

  -- youtube.com/watch?v=ID
  m := regexp_match(input, 'watch\?v=([A-Za-z0-9_-]{6,})');
  if m is not null then return m[1]; end if;

  -- youtu.be/ID
  m := regexp_match(input, 'youtu\.be/([A-Za-z0-9_-]{6,})');
  if m is not null then return m[1]; end if;

  -- youtube.com/embed/ID or youtube-nocookie.com/embed/ID
  m := regexp_match(input, 'embed/([A-Za-z0-9_-]{6,})');
  if m is not null then return m[1]; end if;

  -- youtube.com/shorts/ID
  m := regexp_match(input, 'shorts/([A-Za-z0-9_-]{6,})');
  if m is not null then return m[1]; end if;

  -- already a bare ID
  if input ~ '^[A-Za-z0-9_-]{6,20}$' then
    return input;
  end if;

  return null;
end;
$$;

comment on function public.normalize_youtube_id(text) is 'Server-side defensive YouTube ID extractor supporting watch?v=, youtu.be/, embed/, shorts/ formats and bare IDs. Returns NULL for anything unrecognized so the caller can reject it.';

-- ---------------------------------------------------------------------
-- get_current_program(p_channel_id uuid, p_at timestamptz default now())
-- Resolves the currently active scheduled episode for a channel at a
-- given time, honoring priority + day_of_week recurring slots + one-off
-- dated slots. Falls back to the channel's default_episode_id if no
-- schedule entry matches.
-- ---------------------------------------------------------------------
create or replace function public.get_current_program(p_channel_id uuid, p_at timestamptz default now())
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
  v_dow integer := extract(dow from p_at)::integer;
begin
  -- 1) One-off dated schedule entries covering "now" (highest specificity)
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

  -- 2) Recurring weekly slots matching day_of_week, comparing time-of-day
  return query
    select cs.episode_id, cs.id, cs.start_time, cs.end_time, false
    from public.channel_schedule cs
    where cs.channel_id = p_channel_id
      and cs.enabled = true
      and cs.day_of_week = v_dow
      and cs.start_time::time <= p_at::time
      and (cs.end_time is null or cs.end_time::time > p_at::time)
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

comment on function public.get_current_program(uuid, timestamptz) is 'Resolves the active episode for a channel: one-off dated schedule > recurring weekly schedule > channel default_episode_id.';

-- ---------------------------------------------------------------------
-- log_admin_action() convenience RPC for the Flutter app to write
-- structured audit entries without granting blanket table access.
-- ---------------------------------------------------------------------
create or replace function public.log_admin_action(
  p_action text,
  p_entity_type text default null,
  p_entity_id uuid default null,
  p_metadata jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  if not public.is_content_manager() then
    raise exception 'Unauthorized';
  end if;

  insert into public.audit_logs (user_id, action, entity_type, entity_id, metadata)
  values (auth.uid(), p_action, p_entity_type, p_entity_id, p_metadata)
  returning id into v_id;

  return v_id;
end;
$$;
