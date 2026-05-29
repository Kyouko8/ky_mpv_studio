import 'package:flutter/material.dart';

/// Top-level navigable sections. The same set drives the desktop
/// sidebar and the mobile tab bar — only the shell chrome differs.
enum Section {
  nowPlaying('Now Playing', 'Play', Icons.play_circle_outline_rounded, '/'),
  queue('Queue', 'Queue', Icons.queue_music_rounded, '/queue'),
  effects('Effects', 'FX', Icons.graphic_eq_rounded, '/effects'),
  stream('Stream', 'Stream', Icons.podcasts_rounded, '/stream'),
  settings('Settings', 'More', Icons.tune_rounded, '/settings'),
  console('Console', 'Logs', Icons.terminal_rounded, '/console');

  const Section(this.title, this.shortLabel, this.icon, this.path);

  /// Full title used in the desktop sidebar and page headers.
  final String title;

  /// Compact label used under mobile tab-bar icons.
  final String shortLabel;

  final IconData icon;

  /// Route location for this section's branch in the app [GoRouter]. The
  /// enum's declaration order also fixes each branch's index, so it must
  /// match the router's branch order.
  final String path;
}
