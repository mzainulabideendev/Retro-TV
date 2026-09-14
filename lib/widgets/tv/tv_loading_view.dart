import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

/// Full-screen loading view shown while the app fetches channels/styles and
/// tunes in the first channel. Renders the Cat TV Lottie animation inside a
/// CRT-style card so the wait feels like part of the retro experience.
class TvLoadingView extends StatelessWidget {
  final String? caption;

  const TvLoadingView({super.key, this.caption});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 240,
            height: 240,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFF16161C),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white12),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x66000000),
                  blurRadius: 24,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Lottie.asset(
              'assets/lottie/cat_tv_loading.json',
              width: 210,
              height: 210,
              fit: BoxFit.contain,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            caption ?? 'TUNING IN CHANNELS…',
            style: const TextStyle(
              color: Color(0xFFE0A83E),
              fontSize: 12,
              letterSpacing: 3,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Loading your classic television',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.35),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}