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
