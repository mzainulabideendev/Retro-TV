import 'package:flutter/material.dart';
import '../../models/tv_style.dart';
import 'crt_overlay.dart';
import 'static_noise.dart';

/// The realistic retro CRT television frame: bezel, curved screen,
/// speaker grille, antenna, knobs, legs/stand, vents, brand plaque,
/// power LED, glass glare, and on-screen display (OSD) overlays for
/// channel number / volume feedback. The actual video content is passed
/// in as [screenChild].
class CrtTvFrame extends StatelessWidget {
  final TvStyle style;
  final Widget screenChild;
  final bool poweredOn;
  final bool startingUp;
  final bool channelChanging;
  final bool reduceEffects;
  final int channelNumber;
  final String channelName;
  final String digitBuffer;
  final int volume;
  final bool muted;
  final bool showVolumeOsd;

  const CrtTvFrame({
    super.key,
    required this.style,
    required this.screenChild,
    required this.poweredOn,
    required this.startingUp,
    required this.channelChanging,
    required this.reduceEffects,
    required this.channelNumber,
    required this.channelName,
    this.digitBuffer = '',
    this.volume = 50,
    this.muted = false,
    this.showVolumeOsd = false,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth.clamp(240.0, 900.0);
        return Center(
          child: SizedBox(
            width: maxWidth,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AspectRatio(aspectRatio: 0.86, child: _buildTvBody(context)),
                _buildStand(),
              ],
            ),
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------
  // TV stand / legs
  // ---------------------------------------------------------------
  Widget _buildStand() {
    return SizedBox(
      height: 16,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [_leg(), _leg()],
      ),
    );
  }

  Widget _leg() {
    return ClipPath(
      clipper: _TrapezoidClipper(),
      child: Container(width: 34, height: 14, color: style.knobColor),
    );
  }

  Widget _buildTvBody(BuildContext context) {
    final isNeon = style.isNeon;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(style.bodyColor, Colors.white, 0.06)!,
            style.bodyColor,
            Color.lerp(style.bodyColor, Colors.black, 0.15)!,
          ],
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 30,
            offset: const Offset(0, 14),
          ),
          if (isNeon)
            BoxShadow(
              color: style.accentColor.withValues(alpha: 0.4),
              blurRadius: 30,
              spreadRadius: 2,
            ),
        ],
        border: isNeon
            ? Border.all(
                color: style.accentColor.withValues(alpha: 0.6),
                width: 2,
              )
            : Border.all(color: Colors.black.withValues(alpha: 0.25), width: 1),
      ),
      child: Column(
        children: [
          // Top row: vents + antenna + vents
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sideVents(),
              Expanded(child: _buildAntenna()),
              _sideVents(),
            ],
          ),
          const SizedBox(height: 6),
          // Screen area
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(child: _buildScreen(context)),
                // Channel number display (top-right overlay)
                Positioned(top: 10, right: 10, child: _buildChannelBadge()),
                // Volume OSD (bottom-left, transient)
                Positioned(left: 10, bottom: 10, child: _buildVolumeOsd()),
                // Multi-digit entry OSD (top-left)
                if (digitBuffer.isNotEmpty && poweredOn)
                  Positioned(top: 10, left: 10, child: _buildDigitOsd()),
              ],
            ),
          ),
          const SizedBox(height: 10),
          // Brand plaque
          _buildBrandPlaque(),
          const SizedBox(height: 8),
          // Control panel: speaker grille + knobs + power LED
          _buildControlPanel(),
        ],
      ),
    );
  }

  Widget _sideVents() {
    return SizedBox(
      width: 18,
      height: 22,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(4, (i) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 1.5),
            child: Container(
              height: 2,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildAntenna() {
    return SizedBox(
      height: 22,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          Positioned(
            left: 0,
            bottom: 0,
            child: Transform.rotate(
              angle: -0.5,
              child: Container(width: 3, height: 26, color: style.knobColor),
            ),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Transform.rotate(
              angle: 0.5,
              child: Container(width: 3, height: 26, color: style.knobColor),
            ),
          ),
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: style.knobColor,
              shape: BoxShape.circle,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScreen(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(style.curvature * 100),
        border: Border.all(color: style.bezelColor, width: 10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.6),
            blurRadius: 8,
            spreadRadius: -2,
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (!poweredOn)
            Container(
              color: Colors.black,
              alignment: Alignment.center,
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: style.knobColor.withValues(alpha: 0.6),
                  shape: BoxShape.circle,
                ),
              ),
            )
          else if (startingUp)
            Stack(
              fit: StackFit.expand,
              children: [
                Container(color: Colors.black),
                const StaticNoise(active: true),
                Center(
                  child: Container(
                    width: double.infinity,
                    height: 3,
                    color: style.glowColor.withValues(alpha: 0.8),
                  ),
                ),
              ],
            )
          else
            Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(color: style.screenTint.withValues(alpha: 0.06)),
                // Inert picture: touching the screen can never skip, pause,
                // or bring up the embedded player's own controls.
                AbsorbPointer(child: screenChild),
                StaticNoise(active: channelChanging),
                CrtOverlay(
                  scanlineOpacity: reduceEffects
                      ? style.scanlineOpacity * 0.3
                      : style.scanlineOpacity,
                  glowColor: style.glowColor,
                  reduceMotion: reduceEffects,
                  enabled: true,
                ),
              ],
            ),
          // Glass glare: diagonal light streak overlay for a "real glass"
          // feel, rendered on top of everything including when off.
          IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white.withValues(alpha: 0.08),
                    Colors.transparent,
                    Colors.transparent,
                    Colors.white.withValues(alpha: 0.03),
                  ],
                  stops: const [0.0, 0.35, 0.75, 1.0],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChannelBadge() {
    if (!poweredOn) return const SizedBox.shrink();
    return AnimatedOpacity(
      opacity: 1,
      duration: const Duration(milliseconds: 200),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.65),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: style.glowColor.withValues(alpha: 0.5)),
        ),
        child: Text(
          'CH ${channelNumber.toString().padLeft(2, '0')}',
          style: TextStyle(
            color: style.glowColor,
            fontFamily: 'monospace',
            fontWeight: FontWeight.bold,
            fontSize: 14,
            letterSpacing: 1.5,
          ),
        ),
      ),
    );
  }

  Widget _buildDigitOsd() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: style.glowColor.withValues(alpha: 0.6)),
      ),
      child: Text(
        digitBuffer.padRight(3, '_'),
        style: TextStyle(
          color: style.glowColor,
          fontFamily: 'monospace',
          fontWeight: FontWeight.bold,
          fontSize: 18,
          letterSpacing: 3,
        ),
      ),
    );
  }

  Widget _buildVolumeOsd() {
    if (!poweredOn || !showVolumeOsd) return const SizedBox.shrink();
    return AnimatedOpacity(
      opacity: showVolumeOsd ? 1 : 0,
      duration: const Duration(milliseconds: 200),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.65),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: style.glowColor.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              muted ? Icons.volume_off : Icons.volume_up,
              size: 14,
              color: style.glowColor,
            ),
            const SizedBox(width: 6),
            SizedBox(
              width: 60,
              height: 6,
              child: Row(
                children: List.generate(10, (i) {
                  final filled = !muted && (i < (volume / 10).round());
                  return Expanded(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 1),
                      color: filled
                          ? style.glowColor
                          : Colors.white.withValues(alpha: 0.15),
                    ),
                  );
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBrandPlaque() {
    return Opacity(
      opacity: 0.55,
      child: Text(
        style.era != null
            ? 'RETROVISION · ${style.era!.toUpperCase()}'
            : 'RETROVISION',
        style: TextStyle(
          color: style.knobColor.computeLuminance() > 0.5
              ? Colors.black
              : Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.w600,
          letterSpacing: 2,
        ),
      ),
    );
  }

  Widget _buildControlPanel() {
    return SizedBox(
      height: 34,
      child: Row(
        children: [
          // Power LED
          Container(
            width: 7,
            height: 7,
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: poweredOn
                  ? const Color(0xFF3CFF6E)
                  : const Color(0xFF6A1A1A),
              boxShadow: poweredOn
                  ? [
                      BoxShadow(
                        color: const Color(0xFF3CFF6E).withValues(alpha: 0.7),
                        blurRadius: 6,
                        spreadRadius: 1,
                      ),
                    ]
                  : [],
            ),
          ),
          // Speaker grille (dots)
          Expanded(
            child: Wrap(
              spacing: 4,
              runSpacing: 4,
              children: List.generate(12, (i) {
                return Container(
                  width: 4,
                  height: 4,
                  decoration: BoxDecoration(
                    color: style.bezelColor,
                    shape: BoxShape.circle,
                  ),
                );
              }),
            ),
          ),
          const SizedBox(width: 10),
          // Knobs
          _knob(),
          const SizedBox(width: 8),
          _knob(),
        ],
      ),
    );
  }

  Widget _knob() {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        gradient: RadialGradient(
          colors: [
            Color.lerp(style.knobColor, Colors.white, 0.25)!,
            style.knobColor,
          ],
        ),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.black26, width: 1),
      ),
      child: Center(
        child: Container(width: 2, height: 9, color: Colors.white38),
      ),
    );
  }
}

/// Simple trapezoid clip used to render tapered TV legs/feet.
class _TrapezoidClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.moveTo(size.width * 0.2, 0);
    path.lineTo(size.width * 0.8, 0);
    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}
