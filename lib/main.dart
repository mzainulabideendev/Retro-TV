import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'services/supabase_service.dart';
import 'services/auth_service.dart';
import 'services/tv_state.dart';
import 'screens/public/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SupabaseService.initialize();
  runApp(const RetroTvApp());
}

class RetroTvApp extends StatelessWidget {
  const RetroTvApp({super.key});

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
        home: const HomeScreen(),
      ),
    );
  }
}
