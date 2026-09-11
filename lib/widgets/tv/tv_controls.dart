import 'package:flutter/material.dart';
import '../../services/tv_state.dart';

/// On-screen remote-control-like control panel with power, channel,
/// volume, number pad (multi-digit entry), last-channel recall, guide,
/// random, and fullscreen buttons — all fully wired to [TvState].
class TvControls extends StatelessWidget {
  final TvState tv;
  final VoidCallback onGuide;
  final VoidCallback onFullscreen;
  final Color accentColor;
  final VoidCallback? onVolumeChanged;

  const TvControls({
    super.key,
    required this.tv,
    required this.onGuide,
    required this.onFullscreen,
    required this.accentColor,
    this.onVolumeChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C22),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _remoteButton(
                icon: Icons.power_settings_new,
                label: 'POWER',
                color: Colors.redAccent,
                onTap: tv.togglePower,
              ),
              const SizedBox(width: 8),
              _remoteButton(
                icon: tv.muted ? Icons.volume_off : Icons.volume_up,
                label: 'MUTE',
                color: tv.muted ? accentColor : Colors.white24,
                onTap: tv.isOn
                    ? () {
                        tv.toggleMute();
                        onVolumeChanged?.call();
                      }
                    : null,
              ),
              const SizedBox(width: 8),
              _remoteButton(
                icon: tv.fullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                label: tv.fullscreen ? 'EXIT' : 'FULL',
                color: tv.fullscreen ? accentColor : Colors.white24,
                onTap: tv.isOn ? onFullscreen : null,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _navColumn(
                  label: 'CH',
                  onUp: tv.isOn ? tv.channelUp : null,
                  onDown: tv.isOn ? tv.channelDown : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _navColumn(
                  label: 'VOL',
                  onUp: tv.isOn
                      ? () {
                          tv.volumeUp();
                          onVolumeChanged?.call();
                        }
                      : null,
                  onDown: tv.isOn
                      ? () {
                          tv.volumeDown();
                          onVolumeChanged?.call();
                        }
                      : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _numberPad(),
          const SizedBox(height: 12),
          Row(
            children: [
              _remoteButton(
                icon: Icons.grid_view,
                label: 'GUIDE',
                color: Colors.white24,
                onTap: onGuide,
              ),
              const SizedBox(width: 8),
              _remoteButton(
                icon: Icons.shuffle,
                label: 'RANDOM',
                color: Colors.white24,
                onTap: tv.isOn ? tv.channelSurf : null,
              ),
              const SizedBox(width: 8),
              _remoteButton(
                icon: Icons.fast_rewind,
                label: 'LAST',
                color: Colors.white24,
                onTap: (tv.isOn && tv.previousChannel != null)
                    ? tv.recallLastChannel
                    : null,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _navColumn({
    required String label,
    VoidCallback? onUp,
    VoidCallback? onDown,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 11,
              letterSpacing: 1,
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _iconBtn(Icons.remove, onDown),
              _iconBtn(Icons.add, onUp),
            ],
          ),
        ],
      ),
    );
  }

  Widget _iconBtn(IconData icon, VoidCallback? onTap) {
    return Material(
      color: Colors.white10,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(
            icon,
            color: onTap == null ? Colors.white24 : Colors.white,
            size: 18,
          ),
        ),
      ),
    );
  }

  Widget _remoteButton({
    required IconData icon,
    required String label,
    required Color color,
    VoidCallback? onTap,
  }) {
    return Expanded(
      child: Material(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(
              children: [
                Icon(
                  icon,
                  color: onTap == null ? Colors.white24 : color,
                  size: 20,
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: TextStyle(
                    color: onTap == null ? Colors.white24 : Colors.white70,
                    fontSize: 9,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _numberPad() {
    return Column(
      children: [
        GridView.count(
          crossAxisCount: 5,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
          children: List.generate(10, (i) {
            return Material(
              color: Colors.white10,
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                // Single tap = buffer digit (supports multi-digit channel
                // numbers, auto-confirms after a short pause like a real
                // remote). Long-press = jump directly to that single digit.
                onTap: tv.isOn ? () => tv.pressDigit(i) : null,
                onLongPress: tv.isOn ? () => tv.selectChannelNumber(i) : null,
                child: Center(
                  child: Text(
                    '$i',
                    style: TextStyle(
                      color: tv.isOn ? Colors.white : Colors.white24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
        if (tv.digitBuffer.isNotEmpty) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Entering: ${tv.digitBuffer}',
                  style: TextStyle(
                    color: accentColor,
                    fontSize: 11,
                    letterSpacing: 1,
                  ),
                ),
              ),
              TextButton(
                onPressed: tv.confirmDigits,
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                ),
                child: const Text('ENTER', style: TextStyle(fontSize: 11)),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: tv.clearDigitBuffer,
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                ),
                child: const Text('CLEAR', style: TextStyle(fontSize: 11)),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
