import 'package:flutter/material.dart';

import '../tokens.dart';

/// The app-wide caption header that sits above a group of content — the
/// uppercase label in [Tokens.caption] with the standard gutter padding.
/// One widget so every section ("FEATURED", "ALL EFFECTS", settings
/// categories, stream groups, info-sheet sections) reads identically.
class SectionHeader extends StatelessWidget {
  final String label;
  const SectionHeader(this.label, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Tokens.s4, 0, Tokens.s4, Tokens.s8),
      child: Text(label.toUpperCase(), style: Tokens.caption),
    );
  }
}
