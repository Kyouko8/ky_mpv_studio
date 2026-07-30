import 'dart:async';
import 'dart:math' as math;

import 'package:dart_smb2/dart_smb2.dart';
import 'package:flutter/material.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';

import '../../studio/player_scope.dart';
import '../../studio/queue_manager.dart';
import '../../ui/tokens.dart';
import 'media_server.dart';

/// The Samba (SMB2/3) tab: a connect form until authenticated, then a
/// **folder browser** — navigate the share's directory tree and tap a track to
/// play it.
class SambaBrowserTab extends StatefulWidget {
  final SambaServer server;
  const SambaBrowserTab({super.key, required this.server});

  @override
  State<SambaBrowserTab> createState() => _SambaBrowserTabState();
}

class _SambaBrowserTabState extends State<SambaBrowserTab> {
  static const int _queueMax = 200;

  /// Extensions mpv can decode that we surface as playable tracks.
  static const _audioExts = {
    'flac',
    'mp3',
    'm4a',
    'm4b',
    'aac',
    'ogg',
    'oga',
    'opus',
    'wav',
    'aif',
    'aiff',
    'alac',
    'wma',
    'ape',
    'wv',
    'mka',
    'mp2',
    'caf',
    'dsf',
    'dff',
    'mpc',
  };

  final _host = TextEditingController();
  final _share = TextEditingController();
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _domain = TextEditingController();

  Player? _player;
  QueueManager? _queueManager;

  StreamSubscription<Playlist>? _plSub;

  /// URI of the currently-playing track, to light up its row in the browser.
  String _currentUri = '';

  bool _loading = false;
  String? _error;

  /// Current directory, relative to the share root ('' = root).
  String _path = '';
  List<Smb2DirEntry> _entries = const [];

  bool get _connected => widget.server.isConnected;

  @override
  void initState() {
    super.initState();
    _host.text = widget.server.instance.host;
    _share.text = widget.server.instance.share;
    _user.text = widget.server.instance.username;
    _pass.text = widget.server.instance.password;
    _domain.text = widget.server.instance.domain;
    if (_connected) {
      _open('');
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_player != null) return;
    _player = PlayerScope.of(context);
    _queueManager = PlayerScope.queueManagerOf(context);
    _currentUri = _uriOf(_player!.state.playlist);
    _plSub = _player!.stream.playlist.listen((pl) {
      final u = _uriOf(pl);
      if (mounted && u != _currentUri) setState(() => _currentUri = u);
    });
  }

  static String _uriOf(Playlist pl) {
    if (pl.items.isEmpty || pl.index < 0 || pl.index >= pl.items.length) {
      return '';
    }
    return pl.items[pl.index].uri;
  }

  @override
  void dispose() {
    _plSub?.cancel();
    _host.dispose();
    _share.dispose();
    _user.dispose();
    _pass.dispose();
    _domain.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final host = _host.text.trim();
    final share = _share.text.trim();
    if (host.isEmpty || share.isEmpty) {
      setState(() => _error = 'Host and share are required.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await widget.server.connect(
        host: host,
        username: _user.text,
        password: _pass.text,
      );
      if (!mounted) return;
      setState(() => _loading = false);
      await _open('');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _disconnect() async {
    await widget.server.logout();
    if (!mounted) return;
    setState(() {
      _path = '';
      _entries = const [];
      _error = null;
    });
  }

  /// List [path] and show it.
  Future<void> _open(String path) async {
    final pool = widget.server.pool;
    if (pool == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final all = await pool.listDirectory(path);
      final dirs = all
          .where((e) => e.isDirectory && e.name != '.' && e.name != '..')
          .toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      final files = all
          .where((e) => e.isFile && _audioExts.contains(_ext(e.name)))
          .toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      if (!mounted) return;
      setState(() {
        _path = path;
        _entries = [...dirs, ...files];
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  static String _ext(String name) {
    final dot = name.lastIndexOf('.');
    return dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
  }

  String _join(String base, String name) => base.isEmpty ? name : '$base/$name';

  void _up() {
    if (_path.isEmpty) return;
    final i = _path.lastIndexOf('/');
    _open(i < 0 ? '' : _path.substring(0, i));
  }

  String _smbUrl(String filePath) {
    String enc(String s) => Uri.encodeComponent(s);
    String encPath(String p) =>
        p.split('/').where((s) => s.isNotEmpty).map(enc).join('/');
    final instance = widget.server.instance;
    final dom = instance.domain.isEmpty ? '' : '${enc(instance.domain)};';
    final auth = instance.username.isEmpty
        ? ''
        : (instance.password.isEmpty
            ? '$dom${enc(instance.username)}@'
            : '$dom${enc(instance.username)}:${enc(instance.password)}@');
    return 'smb2://$auth${instance.host}/${encPath(instance.share)}/${encPath(filePath)}';
  }

  void _play(Smb2DirEntry tapped) {
    final files = _entries.where((e) => e.isFile).toList();
    final start = files.indexOf(tapped);
    if (start < 0) return;
    final window =
        files.sublist(start, math.min(start + _queueMax, files.length));
    final album = _path.isEmpty
        ? widget.server.instance.share
        : _path.substring(_path.lastIndexOf('/') + 1);
    final medias = [
      for (final f in window)
        Media(
          _smbUrl(_join(_path, f.name)),
          extras: {
            'title': _stripExt(f.name),
            'album': album,
            'server': ServerKind.samba.name,
            'serverInstanceId': widget.server.instance.id,
            'path': _join(_path, f.name),
          },
        ),
    ];
    _queueManager?.openAll(medias, play: true, index: 0);
  }

  static String _stripExt(String name) {
    final dot = name.lastIndexOf('.');
    return dot <= 0 ? name : name.substring(0, dot);
  }

  @override
  Widget build(BuildContext context) {
    return _connected ? _browser() : _connectForm();
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
              Text('Connect to Samba',
                  style: Tokens.heading, textAlign: TextAlign.center),
              const SizedBox(height: Tokens.s4),
              Text('Enter the host, share, and credentials',
                  style: Tokens.caption, textAlign: TextAlign.center),
              const SizedBox(height: Tokens.s20),
              _Field(
                  controller: _host,
                  hint: '192.168.1.10',
                  icon: Icons.dns_outlined),
              const SizedBox(height: Tokens.s8),
              _Field(
                  controller: _share,
                  hint: 'Share (e.g. Music)',
                  icon: Icons.folder_shared_outlined),
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
              const SizedBox(height: Tokens.s8),
              _Field(
                  controller: _domain,
                  hint: 'Domain (optional)',
                  icon: Icons.workspaces_outline),
              if (_error != null) ...[
                const SizedBox(height: Tokens.s12),
                Text(_error!,
                    style: Tokens.caption.copyWith(color: Tokens.red),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis),
              ],
              const SizedBox(height: Tokens.s16),
              _ConnectButton(busy: _loading, onTap: _connect),
            ],
          ),
        ),
      ),
    );
  }

  // ── Folder browser ──────────────────────────────────────────────────

  Widget _browser() {
    return Column(
      children: [
        // Path bar: up button + breadcrumb + disconnect.
        Padding(
          padding: const EdgeInsets.fromLTRB(
              Tokens.s16, Tokens.s8, Tokens.s16, Tokens.s8),
          child: Row(
            children: [
              IconButton(
                onPressed: _path.isEmpty ? null : _up,
                icon: const Icon(Icons.arrow_upward_rounded, size: 18),
                color: _path.isEmpty ? Tokens.fgFaint : Tokens.fgDim,
                splashRadius: 18,
                tooltip: 'Up',
              ),
              Expanded(
                child: Text(
                  '${widget.server.instance.share}${_path.isEmpty ? '' : '/$_path'}',
                  style: Tokens.body.copyWith(fontFamily: Tokens.mono),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                onPressed: _disconnect,
                icon: const Icon(Icons.logout_rounded, size: 18),
                color: Tokens.fgDim,
                splashRadius: 18,
                tooltip: 'Disconnect',
              ),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const _Spinner()
              : _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(Tokens.s24),
                        child: Text(_error!,
                            style: Tokens.caption.copyWith(color: Tokens.red),
                            textAlign: TextAlign.center,
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis),
                      ),
                    )
                  : _entries.isEmpty
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(Tokens.s24),
                            child: Text('Empty folder.', style: Tokens.caption),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(
                              Tokens.s16, Tokens.s8, Tokens.s16, Tokens.s12),
                          itemCount: _entries.length,
                          itemBuilder: (context, i) {
                            final e = _entries[i];
                            return _EntryTile(
                              entry: e,
                              current: !e.isDirectory &&
                                  _currentUri.isNotEmpty &&
                                  _smbUrl(_join(_path, e.name)) == _currentUri,
                              onTap: () => e.isDirectory
                                  ? _open(_join(_path, e.name))
                                  : _play(e),
                            );
                          },
                        ),
        ),
      ],
    );
  }
}

class _EntryTile extends StatelessWidget {
  final Smb2DirEntry entry;
  final bool current;
  final VoidCallback onTap;
  const _EntryTile({
    required this.entry,
    required this.onTap,
    this.current = false,
  });

  static String _size(int bytes) {
    if (bytes <= 0) return '';
    const units = ['B', 'KB', 'MB', 'GB'];
    var b = bytes.toDouble();
    var u = 0;
    while (b >= 1024 && u < units.length - 1) {
      b /= 1024;
      u++;
    }
    return '${b.toStringAsFixed(b >= 10 || u == 0 ? 0 : 1)} ${units[u]}';
  }

  @override
  Widget build(BuildContext context) {
    final dir = entry.isDirectory;
    final Widget leading = dir
        ? const Icon(Icons.folder_rounded, size: 18, color: Tokens.accent)
        : current
            ? const Icon(Icons.volume_up_rounded,
                size: 18, color: Tokens.accent)
            : const Icon(Icons.music_note_rounded,
                size: 18, color: Tokens.fgFaint);
    return Padding(
      padding: const EdgeInsets.only(bottom: Tokens.s6),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          customBorder: Tokens.squircle(Tokens.rSm),
          child: Ink(
            padding: const EdgeInsets.fromLTRB(
                Tokens.s12, Tokens.s8, Tokens.s12, Tokens.s8),
            decoration: ShapeDecoration(
              color: current ? Tokens.accentWash : Tokens.surface,
              shape: Tokens.squircle(Tokens.rSm),
            ),
            child: Row(
              children: [
                leading,
                const SizedBox(width: Tokens.s12),
                Expanded(
                  child: Text(
                    dir
                        ? entry.name
                        : _SambaBrowserTabState._stripExt(entry.name),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Tokens.body.copyWith(
                      color: current ? Tokens.accent : Tokens.fg,
                      fontWeight: current ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
                const SizedBox(width: Tokens.s8),
                Text(dir ? '' : _size(entry.size), style: Tokens.numeric),
                if (dir)
                  const Icon(Icons.chevron_right_rounded,
                      size: 18, color: Tokens.fgFaint),
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
  final ValueChanged<String>? onSubmitted;

  const _Field({
    required this.controller,
    required this.hint,
    required this.icon,
    this.obscure = false,
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
