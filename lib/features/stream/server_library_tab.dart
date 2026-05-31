import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:infinite_scroll_pagination/infinite_scroll_pagination.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';

import '../../state/player_scope.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets/controls.dart';
import 'media_server.dart';

/// One media-server tab (Jellyfin or Plex): a connect form until
/// authenticated, then a search bar + a paginated song list styled like the
/// Queue, with the currently-playing track highlighted. Tapping a song plays
/// a queue of up to 100 tracks from that point. The session is restored on
/// launch and can be ended with Log out.
class ServerLibraryTab extends StatefulWidget {
  final MediaServer server;
  const ServerLibraryTab({super.key, required this.server});

  @override
  State<ServerLibraryTab> createState() => _ServerLibraryTabState();
}

class _ServerLibraryTabState extends State<ServerLibraryTab> {
  static const int _pageSize = 50;
  static const int _queueMax = 100;

  final _host = TextEditingController();
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _search = TextEditingController();

  Player? _player;
  StreamSubscription<Playlist>? _plSub;
  String _currentTitle = '';

  late final PagingController<int, ServerTrack> _paging;

  PlaybackMode _mode = PlaybackMode.transcode;
  TranscodeCodec _codec = TranscodeCodec.aac;
  int _bitrateKbps = 256;
  bool _restoring = true;

  /// Transcode bitrate ladder (kbps), matching the server transcoders'
  /// useful range for music.
  static const _bitrates = [64, 96, 128, 160, 192, 256];
  bool _connecting = false;
  String? _error;
  String _query = '';
  Timer? _debounce;

  MediaServer get _server => widget.server;

  @override
  void initState() {
    super.initState();
    // The page key IS the start offset (= items already loaded), so the
    // first page starts at 0. (Using `nextIntPageKey`, which is 1-based,
    // with `key * pageSize` skipped the first page — searches with few
    // results then queried past the end and showed nothing.)
    _paging = PagingController<int, ServerTrack>(
      getNextPageKey: (state) =>
          state.lastPageIsEmpty ? null : (state.items?.length ?? 0),
      fetchPage: (startIndex) async {
        final page = await _server.fetchTracks(
          startIndex: startIndex,
          pageSize: _pageSize,
          query: _query,
        );
        return page.tracks;
      },
    );
    _restore();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_player != null) return;
    _player = PlayerScope.of(context);
    // Highlight the playing row by matching the *queued* title we set in
    // extras — reliable even for transcoded streams that carry no metadata.
    _currentTitle = _titleOf(_player!.state.playlist);
    _plSub = _player!.stream.playlist.listen((pl) {
      final t = _titleOf(pl);
      if (mounted && t != _currentTitle) setState(() => _currentTitle = t);
    });
  }

  static String _titleOf(Playlist pl) {
    if (pl.items.isEmpty || pl.index < 0 || pl.index >= pl.items.length) {
      return '';
    }
    return (pl.items[pl.index].extras?['title'] as String?) ?? '';
  }

  Future<void> _restore() async {
    final ok = await _server.tryRestore();
    if (!mounted) return;
    setState(() => _restoring = false);
    if (ok) _paging.refresh();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _plSub?.cancel();
    _host.dispose();
    _user.dispose();
    _pass.dispose();
    _search.dispose();
    _paging.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    setState(() {
      _connecting = true;
      _error = null;
    });
    try {
      await _server.connect(
        host: _host.text,
        username: _user.text,
        password: _pass.text,
      );
      if (!mounted) return;
      setState(() => _connecting = false);
      _paging.refresh();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _connecting = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _logout() async {
    await _server.logout();
    if (!mounted) return;
    _search.clear();
    _query = '';
    setState(() {});
  }

  void _onSearch(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      final next = q.trim();
      if (next == _query) return;
      _query = next;
      _paging.refresh();
    });
  }

  void _play(int index) {
    final items = _paging.value.items ?? const <ServerTrack>[];
    if (index < 0 || index >= items.length) return;
    final window =
        items.sublist(index, math.min(index + _queueMax, items.length));
    final segment = _server.segmentContainer(_mode, codec: _codec.value);
    final medias = [
      for (final t in window)
        Media(
          _server.streamUrl(
            t,
            _mode,
            codec: _codec.value,
            bitrateKbps: _bitrateKbps,
          ),
          extras: {
            'title': t.title,
            'artist': t.artist,
            'album': t.album,
            if (t.artUrl != null) 'art': t.artUrl,
            if (segment != null) 'segment': segment,
          },
        ),
    ];
    _player?.openAll(medias, play: true, index: 0);
  }

  @override
  Widget build(BuildContext context) {
    if (_restoring) return const _Spinner();
    return _server.isConnected ? _library() : _connectForm();
  }

  // ── Connect form ────────────────────────────────────────────────────

  Widget _connectForm() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Tokens.s24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Connect to ${_server.name}',
                  style: Tokens.heading, textAlign: TextAlign.center),
              const SizedBox(height: Tokens.s4),
              Text(
                _server.name == 'Plex'
                    ? 'Server IP (account auth via plex.tv)'
                    : 'Server IP or URL',
                style: Tokens.caption,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: Tokens.s20),
              _Field(
                controller: _host,
                hint: _server.name == 'Plex'
                    ? '192.168.1.10:32400'
                    : '192.168.1.10:8096',
                icon: Icons.dns_outlined,
              ),
              const SizedBox(height: Tokens.s8),
              _Field(
                  controller: _user,
                  hint: 'Username',
                  icon: Icons.person_outline_rounded),
              const SizedBox(height: Tokens.s8),
              _Field(
                controller: _pass,
                hint: 'Password',
                icon: Icons.lock_outline_rounded,
                obscure: true,
                onSubmitted: (_) => _connect(),
              ),
              if (_error != null) ...[
                const SizedBox(height: Tokens.s12),
                Text(_error!,
                    style: Tokens.caption.copyWith(color: Tokens.red),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis),
              ],
              const SizedBox(height: Tokens.s16),
              _ConnectButton(busy: _connecting, onTap: _connect),
            ],
          ),
        ),
      ),
    );
  }

  // ── Connected library ──────────────────────────────────────────────

  Widget _library() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
              Tokens.s16, Tokens.s8, Tokens.s12, Tokens.s8),
          child: Row(
            children: [
              Expanded(
                child: _Field(
                  controller: _search,
                  hint: 'Search songs',
                  icon: Icons.search_rounded,
                  onChanged: _onSearch,
                ),
              ),
              const SizedBox(width: Tokens.s8),
              SizedBox(
                width: 168,
                child: SegmentedControl<PlaybackMode>(
                  selected: _mode,
                  onSelect: (m) => setState(() => _mode = m),
                  options: const [
                    SegmentOption(PlaybackMode.direct, 'Direct'),
                    SegmentOption(PlaybackMode.transcode, 'Transcode'),
                  ],
                ),
              ),
              // Codec + bitrate apply only to a transcode, so they appear
              // only when Transcode is selected.
              if (_mode == PlaybackMode.transcode) ...[
                const SizedBox(width: Tokens.s8),
                SizedBox(
                  width: 84,
                  child: AppDropdown<TranscodeCodec>(
                    value: _codec,
                    items: [
                      for (final c in TranscodeCodec.values)
                        DropdownMenuItem(value: c, child: Text(c.label)),
                    ],
                    onChanged: (c) {
                      if (c != null) setState(() => _codec = c);
                    },
                  ),
                ),
                const SizedBox(width: Tokens.s8),
                SizedBox(
                  width: 110,
                  child: AppDropdown<int>(
                    value: _bitrateKbps,
                    items: [
                      for (final b in _bitrates)
                        DropdownMenuItem(value: b, child: Text('$b kbps')),
                    ],
                    onChanged: (b) {
                      if (b != null) setState(() => _bitrateKbps = b);
                    },
                  ),
                ),
              ],
              const SizedBox(width: Tokens.s4),
              IconButton(
                onPressed: _logout,
                icon: const Icon(Icons.logout_rounded, size: 18),
                color: Tokens.fgDim,
                splashRadius: 18,
                tooltip: 'Log out',
              ),
            ],
          ),
        ),
        Expanded(
          child: PagingListener<int, ServerTrack>(
            controller: _paging,
            builder: (context, state, fetchNextPage) =>
                PagedListView<int, ServerTrack>(
              state: state,
              fetchNextPage: fetchNextPage,
              padding: const EdgeInsets.fromLTRB(
                  Tokens.s12, Tokens.s8, Tokens.s12, Tokens.s12),
              builderDelegate: PagedChildBuilderDelegate<ServerTrack>(
                itemBuilder: (context, track, index) => _TrackTile(
                  track: track,
                  current: track.title.isNotEmpty &&
                      track.title == _currentTitle,
                  onTap: () => _play(index),
                ),
                firstPageProgressIndicatorBuilder: (_) => const _Spinner(),
                newPageProgressIndicatorBuilder: (_) => const _Spinner(),
                firstPageErrorIndicatorBuilder: (_) => _ErrorState(
                  message:
                      _paging.value.error?.toString() ?? 'Failed to load.',
                  onRetry: _paging.refresh,
                ),
                noItemsFoundIndicatorBuilder: (_) => const Center(
                  child: Padding(
                    padding: EdgeInsets.all(Tokens.s24),
                    child: Text('No songs found.', style: Tokens.caption),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Pieces ────────────────────────────────────────────────────────────

/// A song row in the Queue's card style: a squircle surface card; the
/// currently-playing track gets the accent wash, border, colour, and a
/// speaker glyph instead of the music note.
class _TrackTile extends StatelessWidget {
  final ServerTrack track;
  final bool current;
  final VoidCallback onTap;
  const _TrackTile(
      {required this.track, required this.current, required this.onTap});

  static String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final sub =
        [track.artist, track.album].where((e) => e.isNotEmpty).join('  ·  ');
    return Padding(
      padding: const EdgeInsets.only(bottom: Tokens.s6),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          customBorder: Tokens.squircle(Tokens.rSm),
          // Ink so the hover highlight shows over the card surface.
          child: Ink(
            padding: const EdgeInsets.fromLTRB(
                Tokens.s12, Tokens.s8, Tokens.s12, Tokens.s8),
            decoration: ShapeDecoration(
              color: current ? Tokens.accentWash : Tokens.surface,
              shape: Tokens.squircle(Tokens.rSm),
            ),
            child: Row(
              children: [
                if (current) ...[
                  const Icon(Icons.volume_up_rounded,
                      size: 16, color: Tokens.accent),
                  const SizedBox(width: Tokens.s12),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Tokens.body.copyWith(
                          color: current ? Tokens.accent : Tokens.fg,
                          fontWeight:
                              current ? FontWeight.w600 : FontWeight.w400,
                        ),
                      ),
                      if (sub.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(sub,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Tokens.caption),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: Tokens.s12),
                Text(_fmt(track.duration), style: Tokens.numeric),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final bool obscure;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  const _Field({
    required this.controller,
    required this.hint,
    required this.icon,
    this.obscure = false,
    this.onChanged,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: Tokens.controlH,
      decoration: ShapeDecoration(
        color: Tokens.surface2,
        shape: Tokens.squircle(Tokens.rSm),
      ),
      padding: const EdgeInsets.symmetric(horizontal: Tokens.s12),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Tokens.fgFaint),
          const SizedBox(width: Tokens.s8),
          Expanded(
            child: TextField(
              controller: controller,
              obscureText: obscure,
              onChanged: onChanged,
              onSubmitted: onSubmitted,
              style: const TextStyle(
                  fontFamily: Tokens.mono, fontSize: 12.5, color: Tokens.fg),
              cursorColor: Tokens.accent,
              decoration: InputDecoration(
                isDense: true,
                hintText: hint,
                hintStyle: Tokens.caption,
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnectButton extends StatelessWidget {
  final bool busy;
  final VoidCallback onTap;
  const _ConnectButton({required this.busy, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: busy ? null : onTap,
        customBorder: Tokens.squircle(Tokens.rSm),
        child: Container(
          height: 44,
          alignment: Alignment.center,
          decoration: ShapeDecoration(
            color: busy ? Tokens.surface3 : Tokens.accent,
            shape: Tokens.squircle(Tokens.rSm),
          ),
          child: busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Tokens.fgDim),
                )
              : const Text('Connect',
                  style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: Tokens.onAccent)),
        ),
      ),
    );
  }
}

class _Spinner extends StatelessWidget {
  const _Spinner();
  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.all(Tokens.s16),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: Tokens.accentDim),
          ),
        ),
      );
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Tokens.s24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message,
                style: Tokens.caption.copyWith(color: Tokens.red),
                textAlign: TextAlign.center,
                maxLines: 4,
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: Tokens.s12),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
