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
    return SafeArea(
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
    return Container(
      decoration: const BoxDecoration(
        color: Tokens.surface,
        border: Border(top: BorderSide(color: Tokens.line2, width: 1)),
      ),
      padding: const EdgeInsets.symmetric(vertical: Tokens.s8),
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
  const _Tab({required this.section, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = active ? Tokens.accent : Tokens.fgFaint;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Tokens.s4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(section.icon, size: 22, color: color),
              const SizedBox(height: 3),
              Text(
                section.shortLabel,
                style: TextStyle(fontSize: 9.5, color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
