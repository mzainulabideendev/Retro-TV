import 'package:flutter/material.dart';
import '../../models/tv_style.dart';

/// Horizontal picker allowing the user to select among multiple
/// colorful/retro TV styles (1950s B&W, wood console, kids colorful,
/// arcade neon, etc).
class TvStyleSelector extends StatelessWidget {
  final List<TvStyle> styles;
  final TvStyle? selected;
  final void Function(TvStyle) onSelect;

  const TvStyleSelector({
    super.key,
    required this.styles,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    if (styles.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 92,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        itemCount: styles.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final s = styles[i];
          final isSelected = selected?.id == s.id;
          return GestureDetector(
            onTap: () => onSelect(s),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 84,
              decoration: BoxDecoration(
                color: s.bodyColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected ? s.accentColor : Colors.white24,
                  width: isSelected ? 3 : 1,
                ),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: s.accentColor.withValues(alpha: 0.5),
                          blurRadius: 12,
                        ),
                      ]
                    : [],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 40,
                    height: 28,
                    decoration: BoxDecoration(
                      color: s.screenTint,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: s.bezelColor, width: 2),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      s.name,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 9,
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
