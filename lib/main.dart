import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'services/supabase_service.dart';
import 'services/auth_service.dart';
import 'services/tv_state.dart';
import 'screens/public/home_screen.dart';
import 'screens/public/onboarding_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SupabaseService.initialize();
  // First launch shows the onboarding walkthrough; afterwards it is
  // remembered so the TV goes straight to the channel line-up.
  final prefs = await SharedPreferences.getInstance();
  final onboardingSeen = prefs.getBool('onboarding_seen') ?? false;
  runApp(RetroTvApp(showOnboarding: !onboardingSeen));
}

class RetroTvApp extends StatelessWidget {
  final bool showOnboarding;

  const RetroTvApp({super.key, this.showOnboarding = false});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthService()),
        ChangeNotifierProvider(create: (_) => TvState()),
      ],
      child: MaterialApp(
        title: 'Retro TV',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFFE0A83E),
            brightness: Brightness.dark,
          ),
          scaffoldBackgroundColor: const Color(0xFF0B0B0F),
          fontFamily: 'monospace',
          cardTheme: const CardThemeData(
            color: Color(0xFF16161C),
            elevation: 4,
          ),
          dialogTheme: const DialogThemeData(
            backgroundColor: Color(0xFF16161C),
          ),
        ),
        // Cap system font scaling so every screen stays responsive and
        // never overflows when the device font size is set very large.
        builder: (context, child) {
          final mediaQuery = MediaQuery.of(context);
          return MediaQuery(
            data: mediaQuery.copyWith(
              textScaler: mediaQuery.textScaler.clamp(maxScaleFactor: 1.3),
            ),
            child: child!,
          );
        },
        home: showOnboarding ? const OnboardingScreen() : const HomeScreen(),
      ),
    );
  }
}
