<div align="center">

# 📺 Retro TV

**Watch Classic Television** — a nostalgic, CRT-styled Flutter app that brings back the feeling of tuning in to an old television set, streaming classic cartoons and shows straight from YouTube.

![Flutter](https://img.shields.io/badge/Flutter-3.9+-02569B?style=for-the-badge&logo=flutter&logoColor=white)
![Dart](https://img.shields.io/badge/Dart-SDK%20%5E3.9.2-0175C2?style=for-the-badge&logo=dart&logoColor=white)
![Supabase](https://img.shields.io/badge/Supabase-Backend-3ECF8E?style=for-the-badge&logo=supabase&logoColor=white)
![Platform](https://img.shields.io/badge/Platform-Android%20%7C%20iOS%20%7C%20Web%20%7C%20Desktop-6db33f?style=for-the-badge)

</div>

---

## ✨ About the Project

**Retro TV** is a cross-platform streaming experience that recreates the magic of watching television on a vintage CRT set. Pick a retro TV style (1950s black & white, 1970s wood-grain cabinet, playful kids sets, and more), grab the remote, and tune in to a curated lineup of classic cartoons and shows — complete with scanlines, channel-surfing static, power-up animation, and a full-featured on-screen remote control.

The app is built for **both viewers and administrators**:

- **Viewers** get an immersive, remote-controlled TV experience on their phone, tablet, or desktop.
- **Administrators** (editors, admins, super admins) manage every channel, show, episode, schedule, TV style, and user through a **dedicated web-style admin dashboard**, all backed by **Supabase (Auth + Postgres + Row Level Security)**.

## 🎯 Features

### 📺 The Viewer Experience
- **Authentic CRT rendering** — scanline overlays, screen curvature, phosphor glow, film grain, and power-on "warm-up" animation.
- **Multiple selectable TV styles** — switch between themed cabinets/skins (eras, colors, aspect ratios) in one tap.
- **On-screen remote control**:
  - Power on/off with start-up transition
  - Channel up / down navigation
  - Multi-digit channel entry (auto-confirms after a pause, like a real remote) with ENTER / CLEAR
  - Volume up/down, mute, and a volume OSD
  - **LAST** channel recall (jump back to the previous channel)
  - **RANDOM** channel surfing
  - **GUIDE** — interactive channel guide with one-tap tuning
  - **FULL** — immersive fullscreen mode with wakelock
- **Real-time programming** — the server resolves the currently-airing episode per channel (`get_current_program` RPC), with automatic progress to the next episode when one ends.
- **Smart error recovery** — if a specific YouTube upload blocks app embeds, the app skips it and advances to the next playable program automatically, so viewers never get stuck on an error screen.
- **Full keyboard support** — on desktop/web, use real keys: arrow keys (channel/volume), `M` mute, `F` fullscreen, `P` power, `G` guide, and `0–9` to type channel numbers.
- **Persistent settings** — volume, mute, and selected TV style are saved locally via `shared_preferences`.
- **About screen** — app info plus the developer's profile card with Instagram and email links.

### 🔐 Authentication & Roles
Supabase Auth with four roles enforced at the database level:
| Role | Access |
|------|--------|
| `viewer` | Watch only |
| `editor` | Manage Shows & Episodes |
| `admin` | Everything except user role changes |
| `super_admin` | Full access, including Users & role management |

> **Security note:** Role checks are enforced by **Postgres Row Level Security (RLS)** and SQL helper functions (`is_admin()`, `is_content_manager()`), *not* by client-side flags. Promotions/deactivations run through the guarded `promote_user_to_role` RPC.

### 🛠️ Admin Dashboard
A professional, sidebar-based admin console with role-aware panels:
- **Dashboard** — stats & quick overview
- **Channels** — create/tune channels (number, slug, logo, featured, kids-friendly, default episode)
- **Shows** — manage shows per channel
- **Episodes** — upload/publish episodes with YouTube video IDs, seasons & numbering; auto-wires a published episode as its channel's default program
- **Schedules** — time-based `channel_schedule` entries for scheduled programming
- **TV Styles** — visually configure retro skins (colors, era, aspect ratio, glow, effects)
- **Categories** — organize channels into categories
- **Users** — activate/deactivate and promote users (super admin only)
- **Settings** — public site settings
- **Audit Logs** — full history of admin actions via `log_admin_action`

## 🏗️ Architecture

```
lib/
├── main.dart                     # App entry, theming, Provider wiring
├── config.dart                   # Compile-time env config (Supabase URL + publishable key)
├── models/
│   ├── category.dart             # Channel categories
│   ├── channel.dart              # TV channels (number, logo, default episode…)
│   ├── episode.dart              # Episodes (YouTube ID, season/episode numbers, status)
│   ├── profile.dart              # Profiles + role enum (viewer/editor/admin/super_admin)
│   ├── schedule.dart             # channel_schedule entries
│   ├── show.dart                 # Shows
│   └── tv_style.dart             # Retro TV skins (theme config → renderer)
├── services/
│   ├── auth_service.dart         # Sign in/out, profile state
│   ├── content_service.dart      # Data-access layer (public + admin CRUD)
│   ├── supabase_service.dart     # Supabase client singleton
│   └── tv_state.dart             # Central TV state machine (power/channel/volume/playback)
├── screens/
│   ├── public/
│   │   ├── home_screen.dart              # Main viewer experience
│   │   ├── fullscreen_tv_screen.dart     # Immersive fullscreen mode
│   │   └── about_screen.dart             # About + developer card
│   └── admin/
│       ├── admin_login_screen.dart       # Secure admin sign-in
│       ├── admin_dashboard_screen.dart   # Role-aware admin shell
│       └── panels/                       # 10 admin management panels
├── utils/
│   └── youtube_utils.dart       # YouTube ID/video helpers
└── widgets/
    ├── admin/admin_shared.dart  # Shared admin UI components
    └── tv/                       # TV building blocks
        ├── channel_guide.dart
        ├── crt_overlay.dart
        ├── crt_tv_frame.dart
        ├── static_noise.dart
        ├── tv_controls.dart      # On-screen remote
        ├── tv_style_selector.dart
        └── youtube_screen_player.dart

supabase/
└── migrations/                   # 001–006 (schema → RLS → indexes → functions → seed → storage)
    └── COMBINED_MIGRATION.sql    # Single-file database setup
```

### 🔁 How "What's On" Works
1. The app powers on and tunes to a channel.
2. `get_current_program` (a Postgres RPC) resolves the airing episode — checking `channel_schedule` first, then falling back to the channel's `default_episode_id`.
3. The resolved episode plays automatically in the embedded YouTube player (a muted-start → auto-unmute strategy guarantees autoplay).
4. When an episode ends — or embeds are blocked by the uploader — `onProgramEnded` / `onProgramUnavailable` advance to the next available episode or channel with zero user input.

## 🧰 Tech Stack

| Layer | Technology |
|-------|-----------|
| Frontend | Flutter (Material 3, dark theme, monospace styling) |
| State management | Provider (`ChangeNotifier`) |
| Backend | Supabase (Auth, Postgres, RLS, Storage) |
| Video playback | `youtube_player_iframe` (muted-autoplay strategy) |
| Local persistence | `shared_preferences` |
| Utilities | `url_launcher`, `wakelock_plus`, `uuid`, `http` |

**Key packages:** `supabase_flutter 2.6.0`, `provider 6.1.5+1`, `youtube_player_iframe 6.0.2`, `shared_preferences 2.5.3`, `wakelock_plus 1.2.10`, `url_launcher 6.3.2`, `uuid 4.5.1`

## 🚀 Getting Started

### Prerequisites
- [Flutter SDK](https://docs.flutter.dev/get-started/install) `3.9` or newer
- A [Supabase](https://supabase.com) project (free tier works fine)

### Setup

**1. Clone the repository**
```bash
git clone https://github.com/mzainulabideendev/Retro-TV.git
cd Retro-TV
```

**2. Set up the Supabase database**

Apply `supabase/COMBINED_MIGRATION.sql` (or run migrations `001`–`006` in order) in your Supabase SQL editor. This creates the full schema:
- `profiles`, `tv_styles`, `categories`, `channels`, `shows`, `episodes`, `channel_schedule`, `featured_content`, `site_settings`, `audit_logs`
- RLS policies for viewer/editor/admin/super_admin access
- Indexes for performance
- Helper functions & RPCs (`get_current_program`, `promote_user_to_role`, `log_admin_action`, …)
- Seed data and a public storage bucket for media

Then create the storage bucket:
```sql
-- 006_storage_buckets.sql
insert into storage.buckets (id, name, public) values ('media', 'media', true);
```

**3. Configure environment**

Copy the example config and fill in your project's values:
```bash
cp .env.example .env
```
```ini
# .env
SUPABASE_URL=https://your-project-ref.supabase.co
SUPABASE_PUBLISHABLE_KEY=sb_publishable_xxxxxxxxxxxxxxxxxxxxxxxx
```
> Only the **URL** and **publishable (anon) key** belong in the client bundle — they are safe by design because the database is protected by RLS. The **secret/service-role key** and **database URL** must **never** be committed or shipped to the client.

You can also override the values at build time:
```bash
flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_PUBLISHABLE_KEY=...
```

**4. Create your first admin**

1. Sign up a user in your Supabase Auth dashboard (Dashboard → Authentication → Users → Add user).
2. Set their role with the guarded RPC:
```sql
select public.promote_user_to_role('USER_UUID', 'super_admin');
```

**5. Run the app**
```bash
flutter pub get
flutter run
```

### 📦 Building for release

```bash
# Android APK
flutter build apk --release

# Android app bundle (Play Store)
flutter build appbundle --release

# iOS
flutter build ios --release

# Web
flutter build web --release
```

## 🖥️ Supported Platforms

The app targets **Android, iOS, Web, macOS, Windows, and Linux**. The produce folder structure is already scaffolded for every platform (`android/`, `ios/`, `web/`, `windows/`, `macos/`, `linux/`).

## 🧪 Testing

The project ships with Flutter's standard test harness:

```bash
flutter test
```

## 🗂️ Project Structure Highlights

- **`lib/services/tv_state.dart`** — the heart of the app: a complete state machine (off → starting up → on), digit buffering, channel transition animation (static → load → play), program advancement, and persisted volume/style.
- **`lib/services/content_service.dart`** — every read is RLS-filtered and works for anonymous viewers; every write is authorized at the database level. Episodes auto-wire to channels via `_maybeSetAsChannelDefault`, fixing the "channel unavailable" bug.
- **`lib/config.dart`** — compile-time config via `String.fromEnvironment`, with a working public default so the app boots even without explicit flags.

## 🔒 Security

- **RLS is the boundary.** Client-side role flags are convenience only; every privileged operation is enforced by Postgres policies and security-definer functions.
- **Promotion writes** go through `promote_user_to_role`, restricted to super admins on the server.
- **Secrets never ship.** Only the publishable/anon key is embedded; secret keys live server-side only.

## 🤝 Contributing

Contributions, ideas, and classic-cartoon suggestions are welcome!

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📞 Contact

Have a favorite cartoon or movie suggestion, or just want to say hi?

- **Instagram:** [@m.zainulabideenofficial](https://www.instagram.com/m.zainulabideenofficial)
- **Email:** [zu4425@gmail.com](mailto:zu4425@gmail.com)

## 📄 License

Distributed under the MIT License. See `LICENSE` for more information.

---

<div align="center">
  <sub>© 2026 Retro TV — Crafted with ❤️ using Flutter</sub>
</div>