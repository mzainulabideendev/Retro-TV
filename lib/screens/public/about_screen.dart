import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// "About" screen — shows app info plus the developer's profile card
/// (photo, name, bio) with tappable contact links (Instagram + email).
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  static const String _developerName = 'Muhammad Zain Ul Abideen';
  static const String _developerBio =
      'Full-Stack Developer | .NET Specialist\n'
      'Building scalable websites and modern applications with .NET, '
      'while continuously learning and refining my skills.';
  static const String _instagramUrl =
      'https://www.instagram.com/m.zainulabideenofficial?igsh=MTc2MHpxOXZud3Z4NQ%3D%3D&igsi=MTc2MHpxOXZud3Z4NQ%3D%3D';
  static const String _email = 'zu4425@gmail.com';

  Future<void> _openInstagram(BuildContext context) async {
    final uri = Uri.parse(_instagramUrl);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      _showLinkError(context, 'Instagram');
    }
  }

  Future<void> _openEmail(BuildContext context) async {
    final uri = Uri(
      scheme: 'mailto',
      path: _email,
      query: 'subject=Retro TV — Favorite cartoon movie & contact',
    );
    final ok = await launchUrl(uri);
    if (!ok && context.mounted) {
      _showLinkError(context, 'email app');
    }
  }

  void _showLinkError(BuildContext context, String what) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Could not open $what on this device.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D10),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0D10),
        elevation: 0,
        title: const Text('About', style: TextStyle(letterSpacing: 2)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildAppInfoCard(),
                  const SizedBox(height: 20),
                  _buildDeveloperCard(context),
                  const SizedBox(height: 20),
                  _buildFooterNote(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAppInfoCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF16161C),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFE0A83E).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.tv, color: Color(0xFFE0A83E), size: 26),
              ),
              const SizedBox(width: 12),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'RETRO TV',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      letterSpacing: 2,
                    ),
                  ),
                  Text(
                    'Watch Classic Television',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'Retro TV brings back the nostalgic feel of switching '
            'channels on an old CRT television — pick a style, tune '
            'in, and enjoy a curated line-up of classic cartoons and '
            'shows streamed straight from YouTube.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.65),
              fontSize: 13,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeveloperCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF16161C),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'DEVELOPER',
            style: TextStyle(
              color: Colors.white38,
              fontSize: 11,
              letterSpacing: 2,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.asset(
                  'assets/images/developer_photo.jpg',
                  width: 84,
                  height: 84,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    width: 84,
                    height: 84,
                    color: Colors.white10,
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.person,
                      color: Colors.white38,
                      size: 36,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      _developerName,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _developerBio,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 12,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const Divider(color: Colors.white12, height: 1),
          const SizedBox(height: 16),
          const Text(
            'Have a favorite cartoon/movie suggestion? Contact me!',
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _contactButton(
                  icon: Icons.camera_alt_outlined,
                  label: 'Instagram',
                  color: const Color(0xFFE1306C),
                  onTap: () => _openInstagram(context),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _contactButton(
                  icon: Icons.email_outlined,
                  label: 'Email',
                  color: const Color(0xFFE0A83E),
                  onTap: () => _openEmail(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SelectableText(
            _email,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.4),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _contactButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFooterNote() {
    return Center(
      child: Text(
        '© ${DateTime.now().year} Retro TV — Crafted with Flutter',
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.25),
          fontSize: 11,
        ),
      ),
    );
  }
}
