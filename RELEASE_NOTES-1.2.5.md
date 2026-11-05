# Retro TV — Release Notes

## Version 1.2.5 (Android versionCode 10 / Windows 1.2.5.0)

### Google Play — "What's new" (paste into Release notes)

```
Channel Guide just got smarter 📺

• Search any channel by name or number
• New language filter — watch cartoons in Hindi, English, Urdu, Arabic and more
• Admins can tag each channel with its cartoon / audio language
• Fixed channel logos showing the wrong cartoon in search results
• Faster guide loading and smoother scrolling
```

### Microsoft Store — "What's new in this version"

```
Channel Guide improvements

• Search: find any channel instantly by name or channel number.
• Language filter: choose your preferred cartoon / audio language (Hindi, English, Urdu, Arabic and more) to see only the channels that match.
• Admin: each channel can now be tagged with its cartoon / audio language when adding or editing it.
• Fixed an issue where a search result could display another cartoon's thumbnail. Every channel now always shows its own logo.
• Faster Channel Guide loading and smoother scrolling.

Thank you for watching Retro TV!
```

### Short summary (one line, for dashboards / social)

```
Retro TV 1.2.5 — searchable Channel Guide, language filtering, and correct channel logos.
```

### Technical / internal notes

- `channels.language` (nullable text) added to Supabase with index `idx_channels_language`;
  `NULL` means "Unspecified" and channels still appear under "All languages".
- Shared language list in `lib/models/channel_language.dart`, used by both the admin
  channel editor and the viewer language filter.
- Web channel logos now render through a channel-unique `HtmlElementView` view type
  (`rtv-channel-logo-<id>-<urlHash>`) instead of the shared Flutter `<img>` platform view,
  which previously reused another channel's `src` after filtering.
- Android: versionCode 10, versionName 1.2.5, signed with the upload keystore.
- Windows MSIX: 1.2.5.0, x64, identity `MZainUlAbideen.RetroTV`, Store ID `9N5PSC0V6632`.
