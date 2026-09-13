import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'home_screen.dart';

/// First-launch walkthrough shown before the TV. Three simple screens
/// introduce the core idea (a retro CRT channel line-up) and the controls,
/// then the TV home screen takes over. It is only shown once — completion
/// is remembered in [SharedPreferences] under `onboarding_seen`.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _page = 0;

  static const int _pageCount = 3;

  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_seen', true);
    if (!mounted) return;
    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (_) => const HomeScreen()));
  }

  void _next() {
    if (_page < _pageCount - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeInOut,
      );
    } else {
      _finish();
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D10),
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
                child: TextButton(
                  onPressed: _finish,
                  child: const Text(
                    'SKIP',
                    style: TextStyle(
                      color: Colors.white38,
                      fontSize: 12,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _pageCount,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (context, i) => _OnboardingPage(index: i),
              ),
            ),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(_pageCount, (i) {
              final active = i == _page;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: active ? 24 : 8,
                height: 8,
                decoration: BoxDecoration(
                  color: active
                      ? const Color(0xFFE0A83E)
                      : Colors.white.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(4),
                ),
              );
            }),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFE0A83E),
                foregroundColor: const Color(0xFF1A1408),
                padding: const EdgeInsets.symmetric(vertical: 14),
                textStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                ),
              ),
              onPressed: _next,
              child: Text(_page == _pageCount - 1 ? 'START WATCHING' : 'NEXT'),
            ),
          ),
        ],
      ),
    );
  }
}

class _OnboardingPage extends StatelessWidget {
  final int index;

  const _OnboardingPage({required this.index});

  @override
  Widget build(BuildContext context) {
    final accent = const Color(0xFFE0A83E);
    final (title, subtitle, icon, miniscreen) = switch (index) {
      0 => (
        'Welcome to Retro TV',
        'Nostalgic classic cartoons and shows streamed '
            'continuously — just like the TV you grew up with.',
        Icons.live_tv,
        _buildTvScreen(accent),
      ),
      1 => (
        'Tune In, Your Way',
        'Pick a retro TV style, flip through channels with the '
            'remote, or type a number to jump straight to it.',
        Icons.tune,
        _buildRemoteScreen(accent),
      ),
      _ => (
        'Never Miss a Show',
        'The Now & Up Next card tells you what\u2019s playing '
            'and exactly when the next scheduled show airs.',
        Icons.schedule,
        _buildScheduleScreen(accent),
      ),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          miniscreen,
          const SizedBox(height: 36),
          Icon(icon, color: accent, size: 34),
          const SizedBox(height: 18),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 14,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _crTvFrame(Widget screen) {
    return Container(
      width: 240,
      height: 180,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF3A2A1C),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.black38, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Container(
          color: Colors.black,
          child: Center(child: screen),
        ),
      ),
    );
  }

  Widget _buildTvScreen(Color accent) {
    return _crTvFrame(
      Container(
        color: const Color(0xFF0E1626),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.play_circle_fill,
              color: Color(0xFF8AD0FF),
              size: 42,
            ),
            const SizedBox(height: 8),
            Text(
              'NOW PLAYING',
              style: TextStyle(
                color: accent.withValues(alpha: 0.9),
                fontSize: 11,
                letterSpacing: 2,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRemoteScreen(Color accent) {
    return _crTvFrame(
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _dot(accent, Colors.redAccent),
                _dot(accent, Colors.white24),
                _dot(accent, Colors.white24),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: List.generate(
                5,
                (i) => _tinyTile(i == 0 ? accent : Colors.white24),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScheduleScreen(Color accent) {
    return _crTvFrame(
      Container(
        color: const Color(0xFF10131A),
        padding: const EdgeInsets.all(10),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.play_circle_outline, color: accent, size: 14),
                const SizedBox(width: 6),
                const Text(
                  'UP NEXT',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 10,
                    letterSpacing: 1.5,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _scheduleRow(accent, 'Classic Cartoons', '8:30 PM'),
            const SizedBox(height: 6),
            _scheduleRow(accent, 'Movie Night', '10:00 PM'),
          ],
        ),
      ),
    );
  }

  Widget _scheduleRow(Color accent, String title, String time) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white70, fontSize: 10),
            ),
          ),
          Text(
            time,
            style: TextStyle(
              color: accent,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _dot(Color accent, Color color) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }

  Widget _tinyTile(Color color) {
    return Container(
      width: 20,
      height: 18,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }
}
