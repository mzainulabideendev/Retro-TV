import 'package:supabase_flutter/supabase_flutter.dart';
import '../config.dart';

/// Thin wrapper around the Supabase client singleton.
class SupabaseService {
  static SupabaseClient get client => Supabase.instance.client;

  static Future<void> initialize() async {
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      anonKey: AppConfig.supabasePublishableKey,
    );
  }
}
