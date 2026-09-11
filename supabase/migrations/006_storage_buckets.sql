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
