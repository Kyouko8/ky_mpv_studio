import 'package:flutter/material.dart';

import '../ui/tokens.dart';
import 'sections.dart';

/// Mobile chrome: a slim top bar (section title), the section body, and a
/// bottom tab bar. Every top-level view — including the Console — is a tab.
class MobileShell extends StatelessWidget {
  final Section section;
  final ValueChanged<Section> onSelect;
  final Widget body;

  const MobileShell({
    super.key,
    required this.section,
    required this.onSelect,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    // Top/sides are inset normally, but NOT the bottom: the tab bar itself
    // fills the bottom inset (home indicator) with its own surface so the bar
    // reads as continuous to the screen edge instead of leaving a bare gap.
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          Expanded(
            child: Material(type: MaterialType.transparency, child: body),
          ),
          _TabBar(section: section, onSelect: onSelect),
        ],
      ),
    );
  }
}

class _TabBar extends StatelessWidget {
  final Section section;
  final ValueChanged<Section> onSelect;
  const _TabBar({required this.section, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    // Pad the content above the home indicator while the surface colour fills
    // the inset, so the bar runs continuously to the screen edge.
    final bottomInset = MediaQuery.of(context).viewPadding.bottom;
    return Container(
      decoration: const BoxDecoration(
        color: Tokens.surface,
        border: Border(top: BorderSide(color: Tokens.line)),
      ),
      padding: EdgeInsets.only(
        top: Tokens.s8,
        bottom: Tokens.s8 + bottomInset,
      ),
      child: Row(
        children: [
          for (final s in Section.values)
            Expanded(
              child: _Tab(
                section: s,
                active: s == section,
                onTap: () => onSelect(s),
              ),
            ),
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  final Section section;
  final bool active;
  final VoidCallback onTap;
  const _Tab(
      {required this.section, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    // Mirror the desktop sidebar's _NavItem: a solid-accent squircle pill for
    // the active tab with onAccent contents, inactive tabs in fgDim.
    final color = active ? Tokens.onAccent : Tokens.fgDim;
    // The inter-pill gap is a Padding OUTSIDE the InkWell so the ink/hover
    // area (clipped to the same squircle) lines up exactly with the visible
    // pill — a margin inside the InkWell would make the highlight overshoot.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Tokens.s4),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          customBorder: Tokens.squircle(Tokens.rSm),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(vertical: Tokens.s8),
            decoration: ShapeDecoration(
              color: active ? Tokens.accent : Colors.transparent,
              shape: Tokens.squircle(Tokens.rSm),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(section.icon, size: 22, color: color),
                const SizedBox(height: 3),
                Text(
                  section.shortLabel,
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
