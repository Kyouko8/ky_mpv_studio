import 'package:flutter/material.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';

import 'app.dart';
import 'studio/mpv_studio.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MpvAudioKit.ensureInitialized();

  final studio = await MpvStudio.launch();
  runApp(MpvStudioApp(studio: studio));
}
