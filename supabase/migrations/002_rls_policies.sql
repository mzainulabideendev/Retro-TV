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
