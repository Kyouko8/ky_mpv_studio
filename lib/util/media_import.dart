import 'dart:io';

import 'package:file_selector/file_selector.dart';

/// Audio container/extension whitelist used for both the file picker
/// filter and folder scanning. Lower-case, no leading dot.
const Set<String> kAudioExtensions = {
  'mp3',
  'flac',
  'm4a',
  'aac',
  'wav',
  'ogg',
  'oga',
  'opus',
  'wma',
  'aiff',
  'aif',
  'alac',
  'ape',
  'mka',
  'wv',
  'tta',
  'dsf',
  'dff',
  'mp4',
  'webm',
  'mpc',
};

/// Whether [path] looks like a playable audio file by extension.
bool isAudioPath(String path) {
  final dot = path.lastIndexOf('.');
  if (dot < 0 || dot == path.length - 1) return false;
  return kAudioExtensions.contains(path.substring(dot + 1).toLowerCase());
}

/// The file's base name without its directory or extension.
String baseNameNoExt(String path) {
  final name = path.split(RegExp(r'[/\\]')).last;
  final dot = name.lastIndexOf('.');
  return dot > 0 ? name.substring(0, dot) : name;
}

/// Opens a multi-select audio file picker. Returns the chosen absolute
/// paths (empty if the user cancelled).
Future<List<String>> pickAudioFiles() async {
  final typeGroup = XTypeGroup(
    label: 'Audio',
    extensions: kAudioExtensions.toList(),
  );
  final files = await openFiles(
    acceptedTypeGroups: [typeGroup],
    confirmButtonText: 'Add audio files',
  );
  return files.map((f) => f.path).toList();
}

/// Opens a folder picker and returns every audio file inside it,
/// recursively, sorted by path. Empty if cancelled or none found.
///
/// Folder selection is a desktop-only operation (file_selector does not
/// support it on iOS/Android); on mobile users add individual files.
Future<List<String>> pickAudioFolder() async {
  final dir = await getDirectoryPath(
    confirmButtonText: 'Add a folder of audio',
  );
  if (dir == null) return const [];
  return scanAudioFolder(dir);
}

/// Expands a set of dropped paths into playable audio files: directories
/// are scanned recursively, plain files kept if they look like audio.
/// Order is preserved; duplicates are dropped.
List<String> resolveDroppedPaths(Iterable<String> paths) {
  final out = <String>[];
  final seen = <String>{};
  void addPath(String p) {
    if (seen.add(p)) out.add(p);
  }

  for (final p in paths) {
    if (FileSystemEntity.isDirectorySync(p)) {
      scanAudioFolder(p).forEach(addPath);
    } else if (isAudioPath(p)) {
      addPath(p);
    }
  }
  return out;
}

/// Recursively lists audio files under [dirPath]. Tolerates unreadable
/// entries (permissions, broken links).
List<String> scanAudioFolder(String dirPath) {
  final dir = Directory(dirPath);
  if (!dir.existsSync()) return const [];
  final out = <String>[];
  try {
    for (final entity in dir.listSync(recursive: true, followLinks: false)) {
      if (entity is File && isAudioPath(entity.path)) {
        out.add(entity.path);
      }
    }
  } on FileSystemException {
    // Partial results are fine.
  }
  out.sort();
  return out;
}
