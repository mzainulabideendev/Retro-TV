/// Compile-time app configuration.
///
/// SECURITY NOTE: Only the Supabase URL and PUBLISHABLE (anon) key belong
/// here. They are safe to ship in a client/browser bundle by design — the
/// database is protected by Row Level Security, not by hiding this key.
///
/// The SECRET key / service-role key / DB password must NEVER be added to
/// this file or any other file under lib/. Those are used exclusively by
/// one-off server-side setup scripts run from the sandbox (see
/// scripts/create_admin.py) and must never ship to the client.
class AppConfig {
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://hpwxxripfztlvdruimoj.supabase.co',
  );

  static const String supabasePublishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: 'sb_publishable_oC3UQr_3U9FTgyllqSEECA_erCRFCU0',
  );
}
