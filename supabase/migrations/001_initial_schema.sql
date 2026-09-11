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
