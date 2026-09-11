-- =====================================================================
-- Retro TV — Migration 001: Initial Schema
-- =====================================================================
-- NOTE: This project's Supabase database previously contained unrelated
-- demo tables (`cartoons`, `episodes`) from an earlier template that do
-- NOT match the Retro TV schema. We drop them here to avoid a naming
-- collision with our own `episodes` table. If you need that old data,
-- back it up BEFORE running this migration.
-- =====================================================================

drop table if exists public.episodes cascade;
drop table if exists public.cartoons cascade;

create extension if not exists "uuid-ossp";
create extension if not exists "pgcrypto";

-- ---------------------------------------------------------------------
-- Generic updated_at trigger function
-- ---------------------------------------------------------------------
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- ---------------------------------------------------------------------
-- profiles (extends auth.users)
-- ---------------------------------------------------------------------
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text not null,
  display_name text,
  role text not null default 'viewer' check (role in ('super_admin', 'admin', 'editor', 'viewer')),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.profiles is 'Extends auth.users with app role and profile info. role drives all admin authorization.';

create trigger trg_profiles_updated_at
  before update on public.profiles
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------
-- tv_styles — multiple selectable retro TV skins/themes
-- ---------------------------------------------------------------------
create table public.tv_styles (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  slug text unique not null,
  description text,
  era text,
  preview_image text,
  theme_config jsonb not null default '{}'::jsonb,
  screen_aspect_ratio text default '4:3',
  default_volume integer not null default 50 check (default_volume between 0 and 100),
  default_channel_number integer,
  enabled boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.tv_styles is 'Selectable retro TV visual styles/skins (e.g. 1950s B&W, kids colorful, arcade). theme_config stores colors/CSS-like config as JSON consumed by the Flutter renderer.';

create trigger trg_tv_styles_updated_at
  before update on public.tv_styles
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------
-- categories
-- ---------------------------------------------------------------------
create table public.categories (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  slug text unique not null,
  description text,
  enabled boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now()
);

comment on table public.categories is 'Content/channel categories, e.g. Kids, Cartoons, Classic TV, Comedy, Educational, Music, Retro, Movies, General.';

-- ---------------------------------------------------------------------
-- channels
-- ---------------------------------------------------------------------
create table public.channels (
  id uuid primary key default gen_random_uuid(),
  channel_number integer unique not null check (channel_number >= 1),
  name text not null,
  slug text unique not null,
  description text,
  logo_url text,
  banner_url text,
  category_id uuid references public.categories(id) on delete set null,
  channel_type text not null default 'general' check (
    channel_type in ('kids','cartoons','animation','classic_tv','comedy','educational','music','retro','movies','general')
  ),
  default_episode_id uuid, -- FK added after episodes table is created (avoids circular dependency at creation time)
  enabled boolean not null default true,
  featured boolean not null default false,
  is_kids_friendly boolean not null default false,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.channels is 'TV channels. default_episode_id points to episodes(id) and is added as an FK after episodes table exists to avoid a circular FK definition.';
comment on column public.channels.is_kids_friendly is 'Admin-controlled classification flag — content is NOT assumed child-appropriate merely by category.';

create trigger trg_channels_updated_at
  before update on public.channels
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------
-- shows
-- ---------------------------------------------------------------------
create table public.shows (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  slug text unique not null,
  description text,
  poster_url text,
  banner_url text,
  category_id uuid references public.categories(id) on delete set null,
  channel_id uuid references public.channels(id) on delete set null,
  release_year integer check (release_year is null or (release_year between 1900 and 2100)),
  enabled boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.shows is 'A Show groups multiple Episodes across seasons, e.g. "Classic Cartoon Show".';

create trigger trg_shows_updated_at
  before update on public.shows
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------
-- episodes
-- ---------------------------------------------------------------------
create table public.episodes (
  id uuid primary key default gen_random_uuid(),
  show_id uuid references public.shows(id) on delete cascade,
  channel_id uuid references public.channels(id) on delete set null,
  season_number integer not null default 1 check (season_number >= 1),
  episode_number integer check (episode_number is null or episode_number >= 1),
  title text not null,
  description text,
  youtube_video_id text not null check (char_length(youtube_video_id) between 8 and 20),
  youtube_url text,
  thumbnail_url text,
  duration_seconds integer check (duration_seconds is null or duration_seconds >= 0),
  release_year integer,
  air_date timestamptz,
  published_at timestamptz,
  category_id uuid references public.categories(id) on delete set null,
  status text not null default 'draft' check (status in ('draft','published','disabled')),
  enabled boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  -- prevent duplicate episode numbers inside the same show/season (NULL show_id rows are exempt)
  constraint uq_show_season_episode unique (show_id, season_number, episode_number)
);

comment on table public.episodes is 'Individual YouTube-backed video entries. youtube_video_id is the normalized 11-char (approx) YouTube ID extracted server-side from any accepted URL format.';

create trigger trg_episodes_updated_at
  before update on public.episodes
  for each row execute function public.set_updated_at();

-- Now that episodes exists, add the deferred FK on channels.default_episode_id
alter table public.channels
  add constraint fk_channels_default_episode
  foreign key (default_episode_id) references public.episodes(id) on delete set null;

-- ---------------------------------------------------------------------
-- channel_schedule
-- ---------------------------------------------------------------------
create table public.channel_schedule (
  id uuid primary key default gen_random_uuid(),
  channel_id uuid not null references public.channels(id) on delete cascade,
  episode_id uuid not null references public.episodes(id) on delete cascade,
  start_time timestamptz not null,
  end_time timestamptz,
  day_of_week integer check (day_of_week is null or (day_of_week between 0 and 6)),
  priority integer not null default 0,
  enabled boolean not null default true,
  created_at timestamptz not null default now(),
  constraint chk_schedule_time_range check (end_time is null or end_time > start_time)
);

comment on table public.channel_schedule is 'Programs the schedule for a channel. day_of_week (0=Sunday..6=Saturday) supports recurring weekly slots; NULL means a one-off dated slot governed by start_time/end_time.';

-- ---------------------------------------------------------------------
-- channel_favorites (per-user favorites)
-- ---------------------------------------------------------------------
create table public.channel_favorites (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  channel_id uuid not null references public.channels(id) on delete cascade,
  created_at timestamptz not null default now(),
  constraint uq_user_channel_favorite unique (user_id, channel_id)
);

comment on table public.channel_favorites is 'Lets an authenticated user favorite channels.';

-- ---------------------------------------------------------------------
-- site_settings
-- ---------------------------------------------------------------------
create table public.site_settings (
  id uuid primary key default gen_random_uuid(),
  key text unique not null,
  value jsonb not null default '{}'::jsonb,
  is_public boolean not null default true,
  updated_at timestamptz not null default now()
);

comment on table public.site_settings is 'Key/value platform settings. is_public=true rows are readable by anonymous users (e.g. site title); is_public=false rows are admin-only (internal config).';

create trigger trg_site_settings_updated_at
  before update on public.site_settings
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------
-- featured_content
-- ---------------------------------------------------------------------
create table public.featured_content (
  id uuid primary key default gen_random_uuid(),
  content_type text not null check (content_type in ('channel','show','episode','tv_style')),
  content_id uuid not null,
  title_override text,
  sort_order integer not null default 0,
  enabled boolean not null default true,
  created_at timestamptz not null default now()
);

comment on table public.featured_content is 'Polymorphic reference (content_type + content_id) to featured items shown on the homepage. Referential integrity is enforced at the application layer since content_id can point to different tables.';

-- ---------------------------------------------------------------------
-- audit_logs
-- ---------------------------------------------------------------------
create table public.audit_logs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete set null,
  action text not null,
  entity_type text,
  entity_id uuid,
  metadata jsonb default '{}'::jsonb,
  ip_address inet,
  created_at timestamptz not null default now()
);

comment on table public.audit_logs is 'Immutable trail of privileged admin actions (ADMIN_CREATED_CHANNEL, ADMIN_UPDATED_EPISODE, etc). Rows are insert-only; no update/delete policy is granted to any client role.';

-- ---------------------------------------------------------------------
-- admin_activity (lightweight "last seen / last action" per admin)
-- ---------------------------------------------------------------------
create table public.admin_activity (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  last_action text,
  last_seen_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

comment on table public.admin_activity is 'Tracks last-seen/last-action per admin user for the dashboard "activity" widget.';
-- =====================================================================
-- Retro TV — Migration 002: Row Level Security Policies
-- =====================================================================
-- Security model:
--   * Every table has RLS ENABLED. Nothing is left open by default.
--   * Public/anonymous users may only SELECT rows that are "enabled"
--     (or is_public=true for settings), on a small whitelist of tables.
--   * All INSERT/UPDATE/DELETE on content tables require the requesting
--     user to be an authenticated admin (super_admin/admin/editor per
--     the permission matrix below), verified via the is_admin()/has_role()
--     SECURITY DEFINER functions — NEVER via frontend checks.
--   * profiles.role can only be changed by a super_admin (prevents users
--     escalating their own privileges through normal client requests).
--   * audit_logs is insert-only for admins; nobody can update/delete rows.
-- =====================================================================

alter table public.profiles enable row level security;
alter table public.tv_styles enable row level security;
alter table public.categories enable row level security;
alter table public.channels enable row level security;
alter table public.shows enable row level security;
alter table public.episodes enable row level security;
alter table public.channel_schedule enable row level security;
alter table public.channel_favorites enable row level security;
alter table public.site_settings enable row level security;
alter table public.featured_content enable row level security;
alter table public.audit_logs enable row level security;
alter table public.admin_activity enable row level security;

-- ---------------------------------------------------------------------
-- profiles policies
-- ---------------------------------------------------------------------

-- Any authenticated user can read their own profile.
create policy profiles_select_own
  on public.profiles for select
  to authenticated
  using (id = auth.uid());

-- Admins (any admin role) can read all profiles (needed for the Users admin page).
create policy profiles_select_admin
  on public.profiles for select
  to authenticated
  using (public.is_admin());

-- A user may update their own profile EXCEPT the role/is_active columns.
-- We enforce this by requiring the row's role/is_active to be unchanged
-- unless the requester is a super_admin (checked in the WITH CHECK clause).
create policy profiles_update_own_non_privileged
  on public.profiles for update
  to authenticated
  using (id = auth.uid())
  with check (
    id = auth.uid()
    and (
      public.is_super_admin()
      or (
        role = (select p.role from public.profiles p where p.id = auth.uid())
        and is_active = (select p.is_active from public.profiles p where p.id = auth.uid())
      )
    )
  );

-- Only super_admin can change ANY profile's role/is_active (user management).
create policy profiles_update_super_admin
  on public.profiles for update
  to authenticated
  using (public.is_super_admin())
  with check (public.is_super_admin());

-- Profile rows are created automatically by the handle_new_user trigger
-- (SECURITY DEFINER) — no direct insert policy is granted to clients.
-- Only super_admin may delete a profile (deactivating admin accounts).
create policy profiles_delete_super_admin
  on public.profiles for delete
  to authenticated
  using (public.is_super_admin());

-- ---------------------------------------------------------------------
-- tv_styles policies
-- ---------------------------------------------------------------------
create policy tv_styles_public_read
  on public.tv_styles for select
  to anon, authenticated
  using (enabled = true);

create policy tv_styles_admin_read_all
  on public.tv_styles for select
  to authenticated
  using (public.is_admin());

create policy tv_styles_admin_write
  on public.tv_styles for insert
  to authenticated
  with check (public.is_admin());

create policy tv_styles_admin_update
  on public.tv_styles for update
  to authenticated
  using (public.is_admin())
  with check (public.is_admin());

create policy tv_styles_admin_delete
  on public.tv_styles for delete
  to authenticated
  using (public.is_admin());

-- ---------------------------------------------------------------------
-- categories policies
-- ---------------------------------------------------------------------
create policy categories_public_read
  on public.categories for select
  to anon, authenticated
  using (enabled = true);

create policy categories_admin_read_all
  on public.categories for select
  to authenticated
  using (public.is_admin());

create policy categories_admin_write
  on public.categories for insert
  to authenticated
  with check (public.is_admin());

create policy categories_admin_update
  on public.categories for update
  to authenticated
  using (public.is_admin())
  with check (public.is_admin());

create policy categories_admin_delete
  on public.categories for delete
  to authenticated
  using (public.is_admin());

-- ---------------------------------------------------------------------
-- channels policies
-- ---------------------------------------------------------------------
create policy channels_public_read
  on public.channels for select
  to anon, authenticated
  using (enabled = true);

create policy channels_admin_read_all
  on public.channels for select
  to authenticated
  using (public.is_admin());

create policy channels_admin_write
  on public.channels for insert
  to authenticated
  with check (public.is_admin());

create policy channels_admin_update
  on public.channels for update
  to authenticated
  using (public.is_admin())
  with check (public.is_admin());

create policy channels_admin_delete
  on public.channels for delete
  to authenticated
  using (public.is_admin());

-- ---------------------------------------------------------------------
-- shows policies (editors may manage shows too)
-- ---------------------------------------------------------------------
create policy shows_public_read
  on public.shows for select
  to anon, authenticated
  using (enabled = true);

create policy shows_admin_read_all
  on public.shows for select
  to authenticated
  using (public.is_content_manager());

create policy shows_content_write
  on public.shows for insert
  to authenticated
  with check (public.is_content_manager());

create policy shows_content_update
  on public.shows for update
  to authenticated
  using (public.is_content_manager())
  with check (public.is_content_manager());

create policy shows_content_delete
  on public.shows for delete
  to authenticated
  using (public.is_content_manager());

-- ---------------------------------------------------------------------
-- episodes policies (editors may manage episodes too)
-- ---------------------------------------------------------------------
create policy episodes_public_read
  on public.episodes for select
  to anon, authenticated
  using (enabled = true and status = 'published');

create policy episodes_admin_read_all
  on public.episodes for select
  to authenticated
  using (public.is_content_manager());

create policy episodes_content_write
  on public.episodes for insert
  to authenticated
  with check (public.is_content_manager());

create policy episodes_content_update
  on public.episodes for update
  to authenticated
  using (public.is_content_manager())
  with check (public.is_content_manager());

create policy episodes_content_delete
  on public.episodes for delete
  to authenticated
  using (public.is_content_manager());

-- ---------------------------------------------------------------------
-- channel_schedule policies
-- ---------------------------------------------------------------------
create policy schedule_public_read
  on public.channel_schedule for select
  to anon, authenticated
  using (enabled = true);

create policy schedule_admin_read_all
  on public.channel_schedule for select
  to authenticated
  using (public.is_admin());

create policy schedule_admin_write
  on public.channel_schedule for insert
  to authenticated
  with check (public.is_admin());

create policy schedule_admin_update
  on public.channel_schedule for update
  to authenticated
  using (public.is_admin())
  with check (public.is_admin());

create policy schedule_admin_delete
  on public.channel_schedule for delete
  to authenticated
  using (public.is_admin());

-- ---------------------------------------------------------------------
-- channel_favorites policies (self-service, per-user)
-- ---------------------------------------------------------------------
create policy favorites_select_own
  on public.channel_favorites for select
  to authenticated
  using (user_id = auth.uid());

create policy favorites_insert_own
  on public.channel_favorites for insert
  to authenticated
  with check (user_id = auth.uid());

create policy favorites_delete_own
  on public.channel_favorites for delete
  to authenticated
  using (user_id = auth.uid());

-- ---------------------------------------------------------------------
-- site_settings policies
-- ---------------------------------------------------------------------
create policy settings_public_read
  on public.site_settings for select
  to anon, authenticated
  using (is_public = true);

create policy settings_admin_read_all
  on public.site_settings for select
  to authenticated
  using (public.is_admin());

create policy settings_admin_write
  on public.site_settings for insert
  to authenticated
  with check (public.is_admin());

create policy settings_admin_update
  on public.site_settings for update
  to authenticated
  using (public.is_admin())
  with check (public.is_admin());

create policy settings_admin_delete
  on public.site_settings for delete
  to authenticated
  using (public.is_admin());

-- ---------------------------------------------------------------------
-- featured_content policies
-- ---------------------------------------------------------------------
create policy featured_public_read
  on public.featured_content for select
  to anon, authenticated
  using (enabled = true);

create policy featured_admin_read_all
  on public.featured_content for select
  to authenticated
  using (public.is_admin());

create policy featured_admin_write
  on public.featured_content for insert
  to authenticated
  with check (public.is_admin());

create policy featured_admin_update
  on public.featured_content for update
  to authenticated
  using (public.is_admin())
  with check (public.is_admin());

create policy featured_admin_delete
  on public.featured_content for delete
  to authenticated
  using (public.is_admin());

-- ---------------------------------------------------------------------
-- audit_logs policies (insert-only for admins; read for admins; NO update/delete for anyone)
-- ---------------------------------------------------------------------
create policy audit_admin_read
  on public.audit_logs for select
  to authenticated
  using (public.is_admin());

create policy audit_admin_insert
  on public.audit_logs for insert
  to authenticated
  with check (public.is_admin() and (user_id = auth.uid() or user_id is null));

-- Intentionally NO update or delete policy on audit_logs — logs are immutable.

-- ---------------------------------------------------------------------
-- admin_activity policies
-- ---------------------------------------------------------------------
create policy admin_activity_read
  on public.admin_activity for select
  to authenticated
  using (public.is_admin());

create policy admin_activity_upsert_own
  on public.admin_activity for insert
  to authenticated
  with check (user_id = auth.uid() and public.is_admin());

create policy admin_activity_update_own
  on public.admin_activity for update
  to authenticated
  using (user_id = auth.uid() and public.is_admin())
  with check (user_id = auth.uid() and public.is_admin());
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
-- =====================================================================
-- Retro TV — Migration 005: Seed Data
-- =====================================================================
-- All YouTube IDs below are Blender Foundation open movies, released
-- under Creative Commons (CC-BY) and officially published on YouTube by
-- the Blender Foundation. They are used here purely as clearly-labeled
-- SAMPLE/DEMO content so the app is functional out of the box. Replace
-- with your own authorized content via the Admin Dashboard.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Categories
-- ---------------------------------------------------------------------
insert into public.categories (id, name, slug, description, enabled, sort_order) values
  ('a0000000-0000-0000-0000-000000000001','Kids','kids','Child-friendly programming',true,1),
  ('a0000000-0000-0000-0000-000000000002','Cartoons','cartoons','Animated cartoon shows',true,2),
  ('a0000000-0000-0000-0000-000000000003','Animation','animation','General animation content',true,3),
  ('a0000000-0000-0000-0000-000000000004','Classic TV','classic-tv','Classic television programming',true,4),
  ('a0000000-0000-0000-0000-000000000005','Retro','retro','Retro-styled content',true,5),
  ('a0000000-0000-0000-0000-000000000006','Comedy','comedy','Comedy shows',true,6),
  ('a0000000-0000-0000-0000-000000000007','Educational','educational','Educational programming',true,7),
  ('a0000000-0000-0000-0000-000000000008','Music','music','Music programming',true,8);

-- ---------------------------------------------------------------------
-- TV Styles — multiple selectable retro TV skins (colorful + classic)
-- ---------------------------------------------------------------------
insert into public.tv_styles (id, name, slug, description, era, theme_config, screen_aspect_ratio, default_volume, enabled, sort_order) values
(
  'b0000000-0000-0000-0000-000000000001',
  '1950s Black & White',
  '1950s-bw',
  'Classic monochrome cathode-ray television from the golden age of TV.',
  '1950s',
  '{"bodyColor":"#2b2b2b","bezelColor":"#1a1a1a","screenTint":"#c9c9c9","accentColor":"#8a8a8a","knobColor":"#4a4a4a","grain":true,"scanlineOpacity":0.35,"curvature":0.12,"glow":"#d8d8d8"}',
  '4:3', 45, true, 1
),
(
  'b0000000-0000-0000-0000-000000000002',
  '1960s Wooden Console',
  '1960s-wood',
  'Warm wood-panel console television, a centerpiece of the family living room.',
  '1960s',
  '{"bodyColor":"#6b4226","bezelColor":"#4a2c17","screenTint":"#e8dcc0","accentColor":"#c9a15a","knobColor":"#3d2410","grain":true,"scanlineOpacity":0.25,"curvature":0.14,"glow":"#f0d9a0"}',
  '4:3', 50, true, 2
),
(
  'b0000000-0000-0000-0000-000000000003',
  '1970s Color TV',
  '1970s-color',
  'The first generation of color broadcast television, warm and groovy.',
  '1970s',
  '{"bodyColor":"#8a5a2b","bezelColor":"#6b3f1a","screenTint":"#fff2d6","accentColor":"#e07a3f","knobColor":"#3a2410","grain":true,"scanlineOpacity":0.2,"curvature":0.13,"glow":"#ffcf8a"}',
  '4:3', 50, true, 3
),
(
  'b0000000-0000-0000-0000-000000000004',
  '1980s CRT TV',
  '1980s-crt',
  'The iconic boxy 80s CRT with plastic housing and chunky buttons.',
  '1980s',
  '{"bodyColor":"#4a4a52","bezelColor":"#33333a","screenTint":"#e6f0ff","accentColor":"#ff5f6d","knobColor":"#20202a","grain":true,"scanlineOpacity":0.22,"curvature":0.16,"glow":"#8ad0ff"}',
  '4:3', 55, true, 4
),
(
  'b0000000-0000-0000-0000-000000000005',
  '1990s CRT TV',
  '1990s-crt',
  'Sleeker 90s CRT set with digital channel display.',
  '1990s',
  '{"bodyColor":"#2b2b3a","bezelColor":"#1c1c28","screenTint":"#eef2ff","accentColor":"#5ad1e6","knobColor":"#111118","grain":false,"scanlineOpacity":0.18,"curvature":0.1,"glow":"#5ad1e6"}',
  '4:3', 55, true, 5
),
(
  'b0000000-0000-0000-0000-000000000006',
  'Small Portable TV',
  'portable',
  'A compact portable television with a carry handle and short antenna.',
  '1980s',
  '{"bodyColor":"#c94f4f","bezelColor":"#9c3a3a","screenTint":"#fff5f0","accentColor":"#ffd166","knobColor":"#5a2020","grain":true,"scanlineOpacity":0.2,"curvature":0.18,"glow":"#ffd166"}',
  '4:3', 45, true, 6
),
(
  'b0000000-0000-0000-0000-000000000007',
  'Kids Colorful TV',
  'kids-colorful',
  'A bright, playful, oversized-button television designed for children.',
  'Modern Retro',
  '{"bodyColor":"#ff4d6d","bezelColor":"#ff8fa3","screenTint":"#fffdf5","accentColor":"#ffd60a","knobColor":"#3a86ff","grain":false,"scanlineOpacity":0.1,"curvature":0.1,"glow":"#ffd60a","playful":true}',
  '4:3', 60, true, 7
),
(
  'b0000000-0000-0000-0000-000000000008',
  'Vintage Bedroom TV',
  'vintage-bedroom',
  'A soft pastel-toned bedside television with rounded corners.',
  '1970s',
  '{"bodyColor":"#d9b8a3","bezelColor":"#b9906f","screenTint":"#fbe9dd","accentColor":"#e8a798","knobColor":"#7a5445","grain":true,"scanlineOpacity":0.2,"curvature":0.15,"glow":"#f4c9b8"}',
  '4:3', 40, true, 8
),
(
  'b0000000-0000-0000-0000-000000000009',
  'Arcade-Style TV',
  'arcade',
  'Neon-lit arcade cabinet inspired television with glowing trim.',
  '1980s Arcade',
  '{"bodyColor":"#1a1a2e","bezelColor":"#0f0f1e","screenTint":"#0d0221","accentColor":"#ff00d4","knobColor":"#00f5ff","grain":true,"scanlineOpacity":0.3,"curvature":0.2,"glow":"#00f5ff","neon":true}',
  '4:3', 60, true, 9
);

-- ---------------------------------------------------------------------
-- Channels
-- ---------------------------------------------------------------------
insert into public.channels (id, channel_number, name, slug, description, category_id, channel_type, enabled, featured, is_kids_friendly, sort_order) values
('c0000000-0000-0000-0000-000000000001', 1, 'Retro Cartoons', 'retro-cartoons', 'Classic cartoon shorts around the clock.', 'a0000000-0000-0000-0000-000000000002', 'cartoons', true, true, true, 1),
('c0000000-0000-0000-0000-000000000002', 2, 'Kids Classics', 'kids-classics', 'Timeless kids programming.', 'a0000000-0000-0000-0000-000000000001', 'kids', true, true, true, 2),
('c0000000-0000-0000-0000-000000000003', 3, 'Classic Animation', 'classic-animation', 'Beautifully animated feature shorts.', 'a0000000-0000-0000-0000-000000000003', 'animation', true, false, true, 3),
('c0000000-0000-0000-0000-000000000004', 4, 'Retro Shows', 'retro-shows', 'Classic-style television shows.', 'a0000000-0000-0000-0000-000000000004', 'classic_tv', true, false, false, 4);

-- ---------------------------------------------------------------------
-- Shows
-- ---------------------------------------------------------------------
insert into public.shows (id, title, slug, description, category_id, channel_id, release_year, enabled) values
('d0000000-0000-0000-0000-000000000001', 'Big Buck Bunny Shorts', 'big-buck-bunny-shorts', 'Sample open-movie cartoon shorts (Blender Foundation, CC-BY).', 'a0000000-0000-0000-0000-000000000002', 'c0000000-0000-0000-0000-000000000001', 2008, true),
('d0000000-0000-0000-0000-000000000002', 'Sintel Adventures', 'sintel-adventures', 'Sample open-movie fantasy shorts (Blender Foundation, CC-BY).', 'a0000000-0000-0000-0000-000000000003', 'c0000000-0000-0000-0000-000000000003', 2010, true),
('d0000000-0000-0000-0000-000000000003', 'Tears of Steel Classics', 'tears-of-steel-classics', 'Sample open-movie sci-fi shorts (Blender Foundation, CC-BY).', 'a0000000-0000-0000-0000-000000000004', 'c0000000-0000-0000-0000-000000000004', 2012, true);

-- ---------------------------------------------------------------------
-- Episodes (using Blender Foundation Creative-Commons open movies as
-- clearly-labeled sample/demo content)
-- ---------------------------------------------------------------------
insert into public.episodes (id, show_id, channel_id, season_number, episode_number, title, description, youtube_video_id, thumbnail_url, duration_seconds, release_year, status, enabled, sort_order) values
('e0000000-0000-0000-0000-000000000001','d0000000-0000-0000-0000-000000000001','c0000000-0000-0000-0000-000000000001',1,1,'Big Buck Bunny (Sample)','Sample demo episode — Creative Commons open movie by Blender Foundation.','aqz-KE-bpKQ','https://img.youtube.com/vi/aqz-KE-bpKQ/hqdefault.jpg',596,2008,'published',true,1),
('e0000000-0000-0000-0000-000000000002','d0000000-0000-0000-0000-000000000002','c0000000-0000-0000-0000-000000000003',1,1,'Sintel (Sample)','Sample demo episode — Creative Commons open movie by Blender Foundation.','eRsGyueVLvQ','https://img.youtube.com/vi/eRsGyueVLvQ/hqdefault.jpg',888,2010,'published',true,1),
('e0000000-0000-0000-0000-000000000003','d0000000-0000-0000-0000-000000000003','c0000000-0000-0000-0000-000000000004',1,1,'Tears of Steel (Sample)','Sample demo episode — Creative Commons open movie by Blender Foundation.','R6MlUcmOul8','https://img.youtube.com/vi/R6MlUcmOul8/hqdefault.jpg',734,2012,'published',true,1),
('e0000000-0000-0000-0000-000000000004','d0000000-0000-0000-0000-000000000001','c0000000-0000-0000-0000-000000000002',1,2,'Big Buck Bunny Encore (Sample)','Sample demo episode replay for Kids Classics channel.','aqz-KE-bpKQ','https://img.youtube.com/vi/aqz-KE-bpKQ/hqdefault.jpg',596,2008,'published',true,2);

-- Set channel default episodes now that episodes exist
update public.channels set default_episode_id = 'e0000000-0000-0000-0000-000000000001' where id = 'c0000000-0000-0000-0000-000000000001';
update public.channels set default_episode_id = 'e0000000-0000-0000-0000-000000000004' where id = 'c0000000-0000-0000-0000-000000000002';
update public.channels set default_episode_id = 'e0000000-0000-0000-0000-000000000002' where id = 'c0000000-0000-0000-0000-000000000003';
update public.channels set default_episode_id = 'e0000000-0000-0000-0000-000000000003' where id = 'c0000000-0000-0000-0000-000000000004';

-- ---------------------------------------------------------------------
-- Site Settings
-- ---------------------------------------------------------------------
insert into public.site_settings (key, value, is_public) values
('site_title', '"Retro TV — Watch Classic Television"', true),
('site_description', '"A nostalgic virtual television experience. Turn it on and tune in."', true),
('heavy_effects_enabled_default', 'true', true),
('max_volume', '100', true),
('featured_channel_ids', '["c0000000-0000-0000-0000-000000000001","c0000000-0000-0000-0000-000000000002"]', true);

-- ---------------------------------------------------------------------
-- Featured Content
-- ---------------------------------------------------------------------
insert into public.featured_content (content_type, content_id, sort_order, enabled) values
('channel', 'c0000000-0000-0000-0000-000000000001', 1, true),
('channel', 'c0000000-0000-0000-0000-000000000002', 2, true),
('tv_style', 'b0000000-0000-0000-0000-000000000007', 1, true);
-- =====================================================================
-- Retro TV — Migration 006: Storage Buckets & Policies
-- =====================================================================
-- Creates public-read storage buckets for TV style previews, channel
-- logos/banners, show posters/banners, and episode thumbnails. Only
-- admins (is_admin()) may upload/update/delete objects; anyone may
-- read objects in these buckets since they back public-facing images.
-- =====================================================================

insert into storage.buckets (id, name, public)
values
  ('tv-styles', 'tv-styles', true),
  ('channel-logos', 'channel-logos', true),
  ('channel-banners', 'channel-banners', true),
  ('show-posters', 'show-posters', true),
  ('show-banners', 'show-banners', true),
  ('thumbnails', 'thumbnails', true)
on conflict (id) do nothing;

-- Public read access for all six buckets
create policy storage_public_read
  on storage.objects for select
  to anon, authenticated
  using (bucket_id in ('tv-styles','channel-logos','channel-banners','show-posters','show-banners','thumbnails'));

-- Only admins can upload
create policy storage_admin_insert
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id in ('tv-styles','channel-logos','channel-banners','show-posters','show-banners','thumbnails')
    and public.is_admin()
  );

-- Only admins can update/replace
create policy storage_admin_update
  on storage.objects for update
  to authenticated
  using (
    bucket_id in ('tv-styles','channel-logos','channel-banners','show-posters','show-banners','thumbnails')
    and public.is_admin()
  );

-- Only admins can delete
create policy storage_admin_delete
  on storage.objects for delete
  to authenticated
  using (
    bucket_id in ('tv-styles','channel-logos','channel-banners','show-posters','show-banners','thumbnails')
    and public.is_admin()
  );
