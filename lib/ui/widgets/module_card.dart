import 'package:flutter/material.dart';

import '../tokens.dart';

/// A flat rack module: a header with an enable switch and an expand
/// chevron, over a collapsible body of controls. The accent hairline
/// appears only while the module is enabled, so an active effect reads
/// at a glance down a long rack.
class ModuleCard extends StatefulWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final bool enabled;
  final ValueChanged<bool> onEnabledChanged;

  /// Optional reset affordance shown in the header when expanded.
  final VoidCallback? onReset;

  final bool initiallyExpanded;
  final Widget child;

  const ModuleCard({
    super.key,
    required this.title,
    required this.icon,
    required this.enabled,
    required this.onEnabledChanged,
    required this.child,
    this.subtitle,
    this.onReset,
    this.initiallyExpanded = false,
  });

  @override
  State<ModuleCard> createState() => _ModuleCardState();
}

class _ModuleCardState extends State<ModuleCard> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: Tokens.s12),
      decoration: ShapeDecoration(
        color: Tokens.surface,
        shape: Tokens.squircle(
          Tokens.rMd,
          side: BorderSide(
            color: widget.enabled ? Tokens.accentDim : Tokens.line,
            width: 1,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              customBorder: Tokens.squircle(Tokens.rMd),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  Tokens.s16,
                  Tokens.s12,
                  Tokens.s12,
                  Tokens.s12,
                ),
                child: Row(
                  children: [
                    Icon(
                      widget.icon,
                      size: 18,
                      color: widget.enabled ? Tokens.accent : Tokens.fgDim,
                    ),
                    const SizedBox(width: Tokens.s12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(widget.title, style: Tokens.heading),
                          if (widget.subtitle != null) ...[
                            const SizedBox(height: 2),
                            Text(widget.subtitle!, style: Tokens.caption),
                          ],
                        ],
                      ),
                    ),
                    Switch(
                      value: widget.enabled,
                      onChanged: widget.onEnabledChanged,
                    ),
                    const SizedBox(width: Tokens.s4),
                    AnimatedRotation(
                      turns: _expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 150),
                      child: const Icon(
                        Icons.expand_more_rounded,
                        size: 20,
                        color: Tokens.fgDim,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox(width: double.infinity),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(
                Tokens.s16,
                0,
                Tokens.s16,
                Tokens.s16,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Divider(height: 1, thickness: 1, color: Tokens.line),
                  const SizedBox(height: Tokens.s12),
                  widget.child,
                  if (widget.onReset != null) ...[
                    const SizedBox(height: Tokens.s8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: widget.onReset,
                        icon: const Icon(Icons.restart_alt_rounded, size: 16),
                        label: const Text('Reset'),
                        style: TextButton.styleFrom(
                          foregroundColor: Tokens.fgDim,
                          textStyle: Tokens.label,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            crossFadeState: _expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 150),
          ),
        ],
      ),
    );
  }
}
