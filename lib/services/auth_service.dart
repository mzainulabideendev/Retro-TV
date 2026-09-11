import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/profile.dart';
import 'supabase_service.dart';

/// Handles Supabase Auth sign-in/out and exposes the current user's
/// profile (including role) as observable state.
///
/// IMPORTANT: This class is a convenience layer for the UI only. The
/// *real* authorization boundary is enforced by Postgres RLS policies
/// and the is_admin()/is_content_manager() SQL functions — never trust
/// isAdmin/isEditor flags here as a security mechanism by themselves.
class AuthService extends ChangeNotifier {
  Profile? _profile;
  bool _loading = true;
  String? _error;

  Profile? get profile => _profile;
  bool get loading => _loading;
  String? get error => _error;
  bool get isSignedIn => SupabaseService.client.auth.currentUser != null;
  User? get currentUser => SupabaseService.client.auth.currentUser;

  AuthService() {
    _init();
  }

  Future<void> _init() async {
    SupabaseService.client.auth.onAuthStateChange.listen((data) async {
      if (data.event == AuthChangeEvent.signedOut) {
        _profile = null;
        notifyListeners();
      } else if (data.session != null) {
        await _loadProfile();
      }
    });
    if (isSignedIn) {
      await _loadProfile();
    } else {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> _loadProfile() async {
    _loading = true;
    notifyListeners();
    try {
      final userId = SupabaseService.client.auth.currentUser?.id;
      if (userId == null) {
        _profile = null;
        return;
      }
      final res = await SupabaseService.client
          .from('profiles')
          .select()
          .eq('id', userId)
          .maybeSingle();
      if (res != null) {
        _profile = Profile.fromMap(res);
      }
    } catch (e) {
      _error = 'Failed to load profile';
      if (kDebugMode) debugPrint('AuthService._loadProfile error: $e');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<String?> signInWithPassword(String email, String password) async {
    try {
      _error = null;
      await SupabaseService.client.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
      await _loadProfile();
      return null;
    } on AuthException catch (e) {
      return e.message;
    } catch (e) {
      return 'Unable to sign in. Please try again.';
    }
  }

  Future<void> signOut() async {
    await SupabaseService.client.auth.signOut();
    _profile = null;
    notifyListeners();
  }

  Future<void> refreshProfile() => _loadProfile();
}
