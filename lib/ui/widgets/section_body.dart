import 'package:flutter/material.dart';

import '../tokens.dart';

/// Standard scrollable body for a section. Centres content and caps its
/// width so a wide desktop stage reads the same as a phone. The shell
/// already renders the section title above this.
class SectionBody extends StatelessWidget {
  final List<Widget> children;
  final double maxWidth;
  final EdgeInsetsGeometry padding;
  final CrossAxisAlignment crossAxisAlignment;

  const SectionBody({
    super.key,
    required this.children,
    this.maxWidth = 620,
    this.padding = const EdgeInsets.fromLTRB(
      Tokens.s20,
      Tokens.s8,
      Tokens.s20,
      Tokens.s32,
    ),
    this.crossAxisAlignment = CrossAxisAlignment.stretch,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: SingleChildScrollView(
        padding: padding,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Column(
            crossAxisAlignment: crossAxisAlignment,
            children: children,
          ),
        ),
      ),
    );
  }
}

/// A labelled group of settings rows inside a single flat card. The
/// label sits above the card in caption type; rows are separated by
/// hairlines.
class SettingsGroup extends StatelessWidget {
  final String label;
  final List<Widget> children;

  const SettingsGroup({
    super.key,
    required this.label,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) {
        rows.add(const Divider(height: 1, thickness: 1, color: Tokens.line));
      }
      rows.add(children[i]);
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: Tokens.s24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Tokens.s4,
              0,
              Tokens.s4,
              Tokens.s8,
            ),
            child: Text(label.toUpperCase(), style: Tokens.caption),
          ),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: Tokens.s16,
              vertical: Tokens.s4,
            ),
            decoration: BoxDecoration(
              color: Tokens.surface,
              borderRadius: BorderRadius.circular(Tokens.rMd),
              border: Border.all(color: Tokens.line, width: 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: rows,
            ),
          ),
        ],
      ),
    );
  }
}

/// A static label/value row for read-only info (About panel, stats).
class InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const InfoRow({super.key, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Tokens.s8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(label, style: Tokens.body)),
          const SizedBox(width: Tokens.s12),
          Flexible(
            child: Text(
              value,
              style: Tokens.numeric,
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}
