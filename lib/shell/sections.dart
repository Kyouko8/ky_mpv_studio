import 'package:flutter/material.dart';

/// Top-level navigable sections. The same set drives the desktop
/// sidebar and the mobile tab bar — only the shell chrome differs.
enum Section {
  nowPlaying('Now Playing', 'Play', Icons.play_circle_outline_rounded),
  queue('Queue', 'Queue', Icons.queue_music_rounded),
  effects('Effects', 'FX', Icons.graphic_eq_rounded),
  stream('Stream', 'Stream', Icons.podcasts_rounded),
  settings('Settings', 'More', Icons.tune_rounded),
  console('Console', 'Logs', Icons.terminal_rounded);

  const Section(this.title, this.shortLabel, this.icon);

  /// Full title used in the desktop sidebar and page headers.
  final String title;

  /// Compact label used under mobile tab-bar icons.
  final String shortLabel;

  final IconData icon;
}
