## [0.2.0] - 07-06-2026

### Added
- Resume playback (watch later): a Resume settings category to toggle resume-on-reopen, choose the watch-later directory, and save or clear the current file's resume point.
- Playback volume surface: decoder-gain clamps (min/max) and the OS per-app mixer (system volume / mute), shown as "unavailable" when the audio backend doesn't expose them.
- Streaming settings: force-seekable and HLS variant selection (off / min / max).
- Normalization: loudness-normalize surround content downmixed to fewer channels.
- Demuxer settings: an on-disk cache directory picker and a live network cache-state readout (buffered ranges, raw input rate, EOF/BOF-cached, underrun).
- "Music" media role toggle in Audio output settings (Linux PulseAudio / PipeWire routing).
- 64-bit integer (s64) sample format in the format picker.
- Cache pre-buffer-on-start toggle.
- Queue: load a playlist file or URL (.m3u / .m3u8 / .pls / .cue), and a source-playlist banner with cross-playlist navigation.
- Audio track: load or remove an external audio file as a selectable track, plus per-track source / filename / codec-profile details.
- Now Playing: long-press previous/next to force past the queue ends, an undo-last-seek control, and sample-accurate scrubbing on the waveform.

### Changed
- Updated to `mpv_audio_kit` to version `0.3.3`.

## [0.1.2] - 05-06-2026

### Changed
- Bumped `mpv_audio_kit` to version `0.3.2`.

## [0.1.1] - 05-06-2026

### Fixed
- Minor fix.

## [0.1.0] - 05-06-2026

### Added
- Initial release of MPV Studio, the standalone reference player built on `mpv_audio_kit`, for macOS, iOS, Android, Windows and Linux.
- Playback with now-playing, real-time visualizers, and a reorderable queue with gapless transitions.
- Jellyfin and Plex streaming.
- A live DSP rack to toggle and tune audio effects, each with its own interactive diagram.
- A built-in mpv command console with autocomplete and the live engine log.
- Settings to configure the player.
