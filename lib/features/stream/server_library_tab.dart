import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:infinite_scroll_pagination/infinite_scroll_pagination.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';

import '../../studio/player_scope.dart';
import '../../studio/queue_manager.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets/controls.dart';
import 'favorites_controller.dart';
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
  QueueManager? _queueManager;
  StreamSubscription<Playlist>? _plSub;
  // The playing track's server id + server name (from its Media extras). Match
  // on the id, NOT the title — two songs with the same title must not both
  // light up; and the server name keeps a Jellyfin id from matching a Plex row.
  String _currentId = '';
  String _currentServer = '';

  late final PagingController<int, ServerTrack> _paging;

  PlaybackMode _mode = PlaybackMode.transcode;
  TranscodeCodec _codec = TranscodeCodec.aac;
  int _bitrateKbps = 256;
  StreamTransport _transport = StreamTransport.fmp4;
  // Plex defaults to DASH (its documented audio path); Jellyfin is HLS-only,
  // so DASH is greyed out there (see [_protocolDropdown]).
  late StreamProtocol _protocol = widget.server.kind == ServerKind.plex
      ? StreamProtocol.dash
      : StreamProtocol.hls;
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
        try {
          final page = await _server.fetchTracks(
            startIndex: startIndex,
            pageSize: _pageSize,
            query: _query,
          );
          return page.tracks;
        } catch (e) {
          // A 401/403 means the session token is dead (commonly a stale token
          // restored on launch — see tryRestore). Drop it and fall back to the
          // connect form so the user can re-authenticate, instead of leaving a
          // raw, un-retryable error with a Retry that just 401s again.
          if (_server.isAuthError(e)) await _expireSession();
          rethrow;
        }
      },
    );
    _restore();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_player != null) return;
    _player = PlayerScope.of(context);
    _queueManager = PlayerScope.queueManagerOf(context);
    final (id, srv) = _currentOf(_player!.state.playlist);
    _currentId = id;
    _currentServer = srv;
    _plSub = _player!.stream.playlist.listen((pl) {
      final (id, srv) = _currentOf(pl);
      if (mounted && (id != _currentId || srv != _currentServer)) {
        setState(() {
          _currentId = id;
          _currentServer = srv;
        });
      }
    });
  }

  /// The playing track's `(serverId, server)` from its Media extras, or empty
  /// strings when nothing server-backed is playing.
  static (String, String) _currentOf(Playlist pl) {
    if (pl.items.isEmpty || pl.index < 0 || pl.index >= pl.items.length) {
      return ('', '');
    }
    final ex = pl.items[pl.index].extras;
    return (
      (ex?['serverId'] as String?) ?? '',
      (ex?['server'] as String?) ?? '',
    );
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
    setState(() => _error = null);
  }

  /// The session expired mid-use (a 401 on a fetch): drop it and return to the
  /// connect form with an explanatory note so the user can sign in again. The
  /// fetch error is otherwise swallowed by the now-hidden paged list.
  Future<void> _expireSession() async {
    await _server.logout();
    if (!mounted) return;
    _search.clear();
    _query = '';
    setState(() => _error = 'Session expired. Please sign in again.');
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

  Media _serverTrackToMedia(ServerTrack t, FavoritesController favorites) {
    final segment = _server.segmentContainer(
      _mode,
      codec: _codec.value,
      transport: _transport,
      protocol: _protocol,
    );
    final lavfOptions = _server.demuxerLavfOptions(
      _mode,
      codec: _codec.value,
      transport: _transport,
      protocol: _protocol,
    );
    return Media(
      _server.streamUrl(
        t,
        _mode,
        codec: _codec.value,
        bitrateKbps: _bitrateKbps,
        transport: _transport,
        protocol: _protocol,
      ),
      demuxerLavfOptions: lavfOptions,
      extras: {
        'title': t.title,
        'artist': t.artist,
        'album': t.album,
        if (t.artUrl != null) 'art': t.artUrl,
        if (segment != null) 'segment': segment,
        'serverId': t.id,
        'server': _server.kind.name,
        'serverInstanceId': _server.instance.id,
        'playbackMode': _mode.name,
        'codec': _codec.value,
        'bitrateKbps': _bitrateKbps,
        'transport': _transport.name,
        'protocol': _protocol.name,
        'durationMs': t.duration.inMilliseconds,
        'isFavorite': favorites.resolvedByInstance(_server.instance.id, t.id, t.isFavorite),
      },
    );
  }

  void _play(int index) {
    final items = _paging.value.items ?? const <ServerTrack>[];
    if (index < 0 || index >= items.length) return;
    final favorites = PlayerScope.favoritesOf(context);
    final window =
        items.sublist(index, math.min(index + _queueMax, items.length));
    final medias = window.map((t) => _serverTrackToMedia(t, favorites)).toList();
    _queueManager?.openAll(medias, play: true, index: 0);
  }

  Future<void> _addMediasToQueue(
    QueueManager qm,
    String queueId,
    List<Media> medias, {
    required bool skipDuplicates,
  }) async {
    final origId = qm.viewedQueueId;
    qm.selectViewedQueue(queueId);
    final queue = qm.queues.firstWhere((q) => q.id == queueId);
    final existingUris = queue.items.map((item) => item.uri).toSet();
    for (final media in medias) {
      if (skipDuplicates && existingUris.contains(media.uri)) {
        continue;
      }
      await qm.add(media);
    }
    qm.selectViewedQueue(origId);
  }

  void _showQueueSelectionDialog(
    BuildContext context,
    QueueManager qm,
    List<Media> medias,
    String title, {
    required bool skipDuplicates,
  }) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Tokens.surface,
          title: const Text('Select a Queue', style: Tokens.heading),
          content: SizedBox(
            width: 300,
            height: 250,
            child: ListView.builder(
              itemCount: qm.queues.length,
              itemBuilder: (context, i) {
                final q = qm.queues[i];
                return ListTile(
                  title: Text(q.name, style: Tokens.body),
                  subtitle: Text('${q.items.length} tracks', style: Tokens.caption),
                  onTap: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    final nav = Navigator.of(context);
                    await _addMediasToQueue(qm, q.id, medias, skipDuplicates: skipDuplicates);
                    nav.pop();
                    messenger.showSnackBar(
                      SnackBar(content: Text('Added ${medias.length} track(s) to ${q.name}')),
                    );
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel', style: TextStyle(color: Tokens.accent)),
            ),
          ],
        );
      },
    );
  }

  void _showServerTrackMenu(BuildContext context, ServerTrack track) {
    final qm = _queueManager;
    if (qm == null) return;

    bool addAll = false;
    bool skipDuplicates = false;

    showModalBottomSheet(
      context: context,
      backgroundColor: Tokens.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(Tokens.rMd)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final favorites = PlayerScope.favoritesOf(context);
            final items = _paging.value.items ?? const <ServerTrack>[];
            final targetTracks = addAll ? items : [track];
            final medias = targetTracks.map((t) => _serverTrackToMedia(t, favorites)).toList();

            return SafeArea(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: Tokens.s12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SwitchListTile(
                        title: const Text('Agregar todas', style: Tokens.body),
                        subtitle: const Text('Añade todas las canciones de la vista actual', style: Tokens.caption),
                        value: addAll,
                        activeThumbColor: Tokens.accent,
                        onChanged: (val) => setSheetState(() => addAll = val),
                      ),
                      SwitchListTile(
                        title: const Text('Omitir si ya se encuentra en la lista', style: Tokens.body),
                        subtitle: const Text('Evita duplicados en la lista de reproducción', style: Tokens.caption),
                        value: skipDuplicates,
                        activeThumbColor: Tokens.accent,
                        onChanged: (val) => setSheetState(() => skipDuplicates = val),
                      ),
                      const Divider(color: Tokens.line),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: Tokens.s16, vertical: Tokens.s8),
                        child: Text(
                          track.title,
                          style: Tokens.heading.copyWith(fontSize: 15),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const Divider(color: Tokens.line),
                      ListTile(
                        leading: const Icon(Icons.playlist_play_rounded, color: Tokens.accent),
                        title: const Text('Play now as new list', style: Tokens.body),
                        onTap: () async {
                          final nav = Navigator.of(context);
                          qm.createQueue(track.title);
                          await qm.openAll(medias, play: true);
                          nav.pop();
                        },
                      ),
                      ListTile(
                        leading: const Icon(Icons.bookmark_added_rounded, color: Tokens.accent),
                        title: const Text('Add to Listen Later', style: Tokens.body),
                        onTap: () async {
                          final messenger = ScaffoldMessenger.of(context);
                          final nav = Navigator.of(context);
                          QueueModel? target;
                          for (final q in qm.queues) {
                            if (q.name == 'Listen Later') {
                              target = q;
                              break;
                            }
                          }
                          target ??= qm.createQueue('Listen Later');
                          await _addMediasToQueue(qm, target.id, medias, skipDuplicates: skipDuplicates);
                          nav.pop();
                          messenger.showSnackBar(
                            SnackBar(content: Text('Added ${medias.length} track(s) to Listen Later')),
                          );
                        },
                      ),
                      ListTile(
                        leading: const Icon(Icons.playlist_add_rounded, color: Tokens.accent),
                        title: Text('Add to current list (${qm.viewedQueue.name})', style: Tokens.body),
                        onTap: () async {
                          final messenger = ScaffoldMessenger.of(context);
                          final nav = Navigator.of(context);
                          await _addMediasToQueue(qm, qm.viewedQueueId, medias, skipDuplicates: skipDuplicates);
                          nav.pop();
                          messenger.showSnackBar(
                            SnackBar(content: Text('Added ${medias.length} track(s) to current list')),
                          );
                        },
                      ),
                      ListTile(
                        leading: const Icon(Icons.queue_music_rounded, color: Tokens.accent),
                        title: const Text('Add to a list...', style: Tokens.body),
                        onTap: () {
                          Navigator.of(context).pop();
                          _showQueueSelectionDialog(context, qm, medias, track.title, skipDuplicates: skipDuplicates);
                        },
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ── Transcode option dropdowns (shown only in transcode mode) ────────

  Widget _codecDropdown() => AppDropdown<TranscodeCodec>(
        value: _codec,
        items: [
          for (final c in TranscodeCodec.values)
            DropdownMenuItem(value: c, child: Text(c.label)),
        ],
        onChanged: (c) {
          if (c == null) return;
          setState(() {
            _codec = c;
            // MPEG-TS survives only with MP3 — revert if the new codec
            // forbids it, so the picker and the stream never disagree.
            if (!mpegtsAllowed(c.value)) _transport = StreamTransport.fmp4;
          });
        },
      );

  Widget _bitrateDropdown() => AppDropdown<int>(
        value: _bitrateKbps,
        items: [
          for (final b in _bitrates)
            DropdownMenuItem(value: b, child: Text('$b kbps')),
        ],
        onChanged: (b) {
          if (b != null) setState(() => _bitrateKbps = b);
        },
      );

  Widget _protocolDropdown() {
    // DASH is Plex-only; Jellyfin transcodes over HLS only, so it's greyed.
    final dashOk = _server.kind == ServerKind.plex;
    return AppDropdown<StreamProtocol>(
      value: _protocol,
      items: [
        const DropdownMenuItem(
          value: StreamProtocol.hls,
          child: Text('HLS'),
        ),
        DropdownMenuItem(
          value: StreamProtocol.dash,
          enabled: dashOk,
          child: dashOk
              ? const Text('DASH')
              : Tooltip(
                  message: 'DASH is available only on Plex',
                  child: const Text('DASH'),
                ),
        ),
      ],
      onChanged: (p) {
        if (p == null) return;
        setState(() {
          _protocol = p;
          // DASH carries only fMP4 — drop MPEG-TS so the picker and the
          // stream never disagree.
          if (p == StreamProtocol.dash) _transport = StreamTransport.fmp4;
        });
      },
    );
  }

  Widget _transportDropdown() {
    final dash = _protocol == StreamProtocol.dash;
    final tsOk = !dash && mpegtsAllowed(_codec.value);
    // Explain why MPEG-TS is unavailable: blocked by DASH first, else by codec.
    final tsHint = dash
        ? 'MPEG-TS is not available over DASH'
        : 'MPEG-TS is available only with the MP3 codec';
    return AppDropdown<StreamTransport>(
      value: _transport,
      items: [
        const DropdownMenuItem(
          value: StreamTransport.fmp4,
          child: Text('fMP4'),
        ),
        DropdownMenuItem(
          value: StreamTransport.mpegts,
          enabled: tsOk,
          child: tsOk
              ? const Text('MPEG-TS')
              : Tooltip(
                  message: tsHint,
                  child: const Text('MPEG-TS'),
                ),
        ),
      ],
      onChanged: (t) {
        if (t != null) setState(() => _transport = t);
      },
    );
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
              Tokens.s16, Tokens.s8, Tokens.s16, Tokens.s8),
          child: Column(
            children: [
              Row(
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
              // Codec / bitrate / protocol / container apply only to a
              // transcode, so they sit on their own rows that appear only in
              // that mode. Two rows keep each picker tappable on a phone.
              if (_mode == PlaybackMode.transcode) ...[
                const SizedBox(height: Tokens.s8),
                Row(
                  children: [
                    Expanded(child: _codecDropdown()),
                    const SizedBox(width: Tokens.s8),
                    Expanded(child: _bitrateDropdown()),
                  ],
                ),
                const SizedBox(height: Tokens.s8),
                Row(
                  children: [
                    Expanded(child: _protocolDropdown()),
                    const SizedBox(width: Tokens.s8),
                    Expanded(child: _transportDropdown()),
                  ],
                ),
              ],
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
                  Tokens.s16, Tokens.s8, Tokens.s16, Tokens.s12),
              builderDelegate: PagedChildBuilderDelegate<ServerTrack>(
                itemBuilder: (context, track, index) => _TrackTile(
                  track: track,
                  current: _currentId.isNotEmpty &&
                      track.id == _currentId &&
                      _currentServer == _server.kind.name,
                  serverInstanceId: _server.instance.id,
                  favorites: PlayerScope.favoritesOf(context),
                  onTap: () => _play(index),
                  onMore: () => _showServerTrackMenu(context, track),
                ),
                firstPageProgressIndicatorBuilder: (_) => const _Spinner(),
                newPageProgressIndicatorBuilder: (_) => const _Spinner(),
                firstPageErrorIndicatorBuilder: (_) => _ErrorState(
                  message: _paging.value.error?.toString() ?? 'Failed to load.',
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
  final String serverInstanceId;
  final FavoritesController favorites;
  final VoidCallback onTap;
  final VoidCallback onMore;
  const _TrackTile({
    required this.track,
    required this.current,
    required this.serverInstanceId,
    required this.favorites,
    required this.onTap,
    required this.onMore,
  });

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
                const SizedBox(width: Tokens.s4),
                _FavoriteStar(favorites: favorites, serverInstanceId: serverInstanceId, track: track),
                const SizedBox(width: Tokens.s4),
                Text(_fmt(track.duration), style: Tokens.numeric),
                const SizedBox(width: Tokens.s8),
                IconButton(
                  icon: const Icon(Icons.more_vert_rounded, size: 18, color: Tokens.fgDim),
                  onPressed: onMore,
                  constraints: const BoxConstraints(),
                  padding: EdgeInsets.zero,
                  splashRadius: 18,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The per-row favourite toggle. Rebuilds off the shared [FavoritesController]
/// so a toggle from the OS lock screen (or another row) reflects immediately.
class _FavoriteStar extends StatelessWidget {
  final FavoritesController favorites;
  final String serverInstanceId;
  final ServerTrack track;
  const _FavoriteStar({
    required this.favorites,
    required this.serverInstanceId,
    required this.track,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: favorites,
      builder: (context, _) {
        final fav = favorites.resolvedByInstance(serverInstanceId, track.id, track.isFavorite);
        return IconButton(
          onPressed: () => favorites.setFavoriteByInstance(serverInstanceId, track.id, !fav),
          icon: Icon(fav ? Icons.star_rounded : Icons.star_border_rounded,
              size: 18),
          color: fav ? Tokens.accent : Tokens.fgDim,
          splashRadius: 18,
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          tooltip: fav ? 'Unfavorite' : 'Favorite',
        );
      },
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
            // Content-sized so the Row's centre cross-axis alignment centres
            // it vertically in the fixed-height pill — forcing a full height
            // would top-anchor the text instead.
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
