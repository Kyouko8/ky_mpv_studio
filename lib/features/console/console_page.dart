import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';

import '../../state/player_scope.dart';
import '../../ui/tokens.dart';

/// The engine console — a power tool, not just a log. Two tabs:
///
/// * **Console**: the live mpv + library log interleaved with a REPL.
///   Type a raw command (`seek 30`), or `get <property>` /
///   `set <property> <value>`; results land inline in the scrollback.
///   Filter by level, clear, toggle autoscroll, copy.
/// * **Inspector**: watch arbitrary mpv properties live — each is polled
///   and shown with its current value.
class ConsolePage extends StatefulWidget {
  const ConsolePage({super.key});

  @override
  State<ConsolePage> createState() => _ConsolePageState();
}

enum _Tab { console, inspector }

enum _Kind { log, input, output, error }

class _Line {
  final _Kind kind;
  final LogLevel level;
  final String prefix;
  final String text;
  const _Line(this.kind, this.text, {this.level = LogLevel.info, this.prefix = ''});
}

class _ConsolePageState extends State<ConsolePage> {
  static const _max = 1000;
  static const _mono = TextStyle(
    fontFamily: Tokens.mono,
    fontSize: 12,
    height: 1.5,
    color: Tokens.fg,
  );

  late final Player _player;
  final _lines = Queue<_Line>();
  final _subs = <StreamSubscription<MpvLogEntry>>[];
  final _scroll = ScrollController();
  final _input = TextEditingController();
  final _inputFocus = FocusNode();
  final _watchInput = TextEditingController();

  _Tab _tab = _Tab.console;
  int _levelThreshold = 4; // see _severity; default shows down to info
  bool _autoscroll = true;

  final _watches = <String>[];
  final _watchValues = <String, String>{};
  Timer? _poll;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_subs.isNotEmpty) return;
    _player = PlayerScope.of(context);
    for (final s in [_player.stream.log, _player.stream.internalLog]) {
      _subs.add(s.listen((e) => _add(_Line(
            _Kind.log,
            e.text,
            level: e.level,
            prefix: e.prefix,
          ))));
    }
    _poll = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (_tab == _Tab.inspector && _watches.isNotEmpty) _pollWatches();
    });
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _poll?.cancel();
    _scroll.dispose();
    _input.dispose();
    _inputFocus.dispose();
    _watchInput.dispose();
    super.dispose();
  }

  // ---- log buffer --------------------------------------------------

  void _add(_Line line) {
    if (!mounted) return;
    setState(() {
      _lines.addLast(line);
      while (_lines.length > _max) {
        _lines.removeFirst();
      }
    });
    if (_autoscroll) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        }
      });
    }
  }

  // Severity rank: lower = more severe. Used by the level filter.
  static int _severity(LogLevel l) {
    switch (l) {
      case LogLevel.fatal:
        return 0;
      case LogLevel.error:
        return 1;
      case LogLevel.warn:
        return 2;
      case LogLevel.info:
        return 4;
      case LogLevel.v:
        return 5;
      case LogLevel.debug:
        return 6;
      case LogLevel.trace:
        return 7;
      case LogLevel.off:
        return 8;
    }
  }

  bool _visible(_Line l) =>
      l.kind != _Kind.log || _severity(l.level) <= _levelThreshold;

  Color _color(_Line l) {
    switch (l.kind) {
      case _Kind.input:
        return Tokens.accent;
      case _Kind.error:
        return Tokens.red;
      case _Kind.output:
        return Tokens.fg;
      case _Kind.log:
        switch (l.level) {
          case LogLevel.fatal:
          case LogLevel.error:
            return Tokens.red;
          case LogLevel.warn:
            return Tokens.amber;
          case LogLevel.info:
            return Tokens.fgDim;
          default:
            return Tokens.fgFaint;
        }
    }
  }

  // ---- REPL --------------------------------------------------------

  Future<void> _run(String raw) async {
    final text = raw.trim();
    if (text.isEmpty) return;
    _add(_Line(_Kind.input, '› $text'));
    _input.clear();
    _inputFocus.requestFocus();

    final tokens = text.split(RegExp(r'\s+'));
    try {
      if (tokens.first == 'get' && tokens.length >= 2) {
        final prop = tokens[1];
        final value = await _player.getRawProperty(prop);
        _add(_Line(_Kind.output, '$prop = ${value ?? '<null>'}'));
      } else if (tokens.first == 'set' && tokens.length >= 3) {
        final prop = tokens[1];
        final value = tokens.sublist(2).join(' ');
        await _player.setRawProperty(prop, value);
        _add(_Line(_Kind.output, '$prop = $value'));
      } else {
        await _player.sendRawCommand(tokens);
        _add(const _Line(_Kind.output, 'ok'));
      }
    } catch (e) {
      _add(_Line(_Kind.error, e.toString()));
    }
  }

  void _copyAll() {
    final text = _lines
        .where(_visible)
        .map((l) => l.kind == _Kind.log && l.prefix.isNotEmpty
            ? '[${l.prefix}] ${l.text}'
            : l.text)
        .join('\n');
    Clipboard.setData(ClipboardData(text: text));
  }

  // ---- inspector ---------------------------------------------------

  Future<void> _pollWatches() async {
    final updates = <String, String>{};
    for (final name in _watches) {
      try {
        updates[name] = (await _player.getRawProperty(name)) ?? '<null>';
      } catch (e) {
        updates[name] = '<error>';
      }
    }
    if (!mounted) return;
    setState(() => _watchValues.addAll(updates));
  }

  void _addWatch(String raw) {
    final name = raw.trim();
    if (name.isEmpty || _watches.contains(name)) return;
    setState(() {
      _watches.add(name);
      _watchValues[name] = '…';
    });
    _watchInput.clear();
    _pollWatches();
  }

  void _removeWatch(String name) {
    setState(() {
      _watches.remove(name);
      _watchValues.remove(name);
    });
  }

  // ---- build -------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _Toolbar(
          tab: _tab,
          onTab: (t) => setState(() => _tab = t),
          levelThreshold: _levelThreshold,
          onLevel: (v) => setState(() => _levelThreshold = v),
          autoscroll: _autoscroll,
          onAutoscroll: () => setState(() => _autoscroll = !_autoscroll),
          onClear: () => setState(_lines.clear),
          onCopy: _copyAll,
        ),
        const Divider(height: 1, thickness: 1, color: Tokens.line),
        Expanded(
          child: _tab == _Tab.console ? _buildConsole() : _buildInspector(),
        ),
      ],
    );
  }

  Widget _buildConsole() {
    final visible = _lines.where(_visible).toList(growable: false);
    return Column(
      children: [
        Expanded(
          child: visible.isEmpty
              ? const Center(
                  child: Text('No log output yet.', style: Tokens.caption))
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.symmetric(
                    horizontal: Tokens.s16,
                    vertical: Tokens.s8,
                  ),
                  itemCount: visible.length,
                  itemBuilder: (context, i) {
                    final l = visible[i];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 1),
                      child: SelectableText.rich(
                        TextSpan(
                          style: _mono,
                          children: [
                            if (l.kind == _Kind.log) ...[
                              TextSpan(
                                text: '${l.level.mpvValue.padRight(5)} ',
                                style: _mono.copyWith(color: _color(l)),
                              ),
                              if (l.prefix.isNotEmpty)
                                TextSpan(
                                  text: '${l.prefix}: ',
                                  style: _mono.copyWith(color: Tokens.fgFaint),
                                ),
                              TextSpan(text: l.text),
                            ] else
                              TextSpan(
                                text: l.text,
                                style: _mono.copyWith(color: _color(l)),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
        const Divider(height: 1, thickness: 1, color: Tokens.line),
        _InputBar(
          controller: _input,
          focusNode: _inputFocus,
          onSubmit: _run,
        ),
      ],
    );
  }

  Widget _buildInspector() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Tokens.s16,
            Tokens.s8,
            Tokens.s16,
            Tokens.s8,
          ),
          child: _WatchInput(
            controller: _watchInput,
            onAdd: _addWatch,
          ),
        ),
        Expanded(
          child: _watches.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(Tokens.s24),
                    child: Text(
                      'Watch any mpv property live.\n'
                      'Try: time-pos · ao · cache-buffering-state · metadata',
                      style: Tokens.caption,
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: Tokens.s4),
                  itemCount: _watches.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, thickness: 1, color: Tokens.line),
                  itemBuilder: (context, i) {
                    final name = _watches[i];
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: Tokens.s16,
                        vertical: Tokens.s8,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 2,
                            child: Text(name, style: _mono),
                          ),
                          const SizedBox(width: Tokens.s12),
                          Expanded(
                            flex: 3,
                            child: Text(
                              _watchValues[name] ?? '…',
                              style: _mono.copyWith(color: Tokens.accent),
                            ),
                          ),
                          InkWell(
                            onTap: () => _removeWatch(name),
                            child: const Padding(
                              padding: EdgeInsets.all(2),
                              child: Icon(Icons.close_rounded,
                                  size: 15, color: Tokens.fgFaint),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _Toolbar extends StatelessWidget {
  final _Tab tab;
  final ValueChanged<_Tab> onTab;
  final int levelThreshold;
  final ValueChanged<int> onLevel;
  final bool autoscroll;
  final VoidCallback onAutoscroll;
  final VoidCallback onClear;
  final VoidCallback onCopy;

  const _Toolbar({
    required this.tab,
    required this.onTab,
    required this.levelThreshold,
    required this.onLevel,
    required this.autoscroll,
    required this.onAutoscroll,
    required this.onClear,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Tokens.s16,
        Tokens.s8,
        Tokens.s8,
        Tokens.s8,
      ),
      child: Row(
        children: [
          _Pill(label: 'Console', active: tab == _Tab.console, onTap: () => onTab(_Tab.console)),
          const SizedBox(width: Tokens.s4),
          _Pill(label: 'Inspector', active: tab == _Tab.inspector, onTap: () => onTab(_Tab.inspector)),
          const Spacer(),
          if (tab == _Tab.console) ...[
            _LevelFilter(threshold: levelThreshold, onSelect: onLevel),
            const SizedBox(width: Tokens.s8),
            IconButton(
              onPressed: onAutoscroll,
              icon: Icon(
                autoscroll
                    ? Icons.vertical_align_bottom_rounded
                    : Icons.vertical_align_center_rounded,
                size: 18,
              ),
              color: autoscroll ? Tokens.accent : Tokens.fgDim,
              tooltip: 'Autoscroll',
              splashRadius: 18,
            ),
            IconButton(
              onPressed: onCopy,
              icon: const Icon(Icons.copy_rounded, size: 16),
              color: Tokens.fgDim,
              tooltip: 'Copy',
              splashRadius: 18,
            ),
            IconButton(
              onPressed: onClear,
              icon: const Icon(Icons.delete_outline_rounded, size: 18),
              color: Tokens.fgDim,
              tooltip: 'Clear',
              splashRadius: 18,
            ),
          ],
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _Pill({required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Tokens.rSm),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(
            horizontal: Tokens.s12,
            vertical: Tokens.s6,
          ),
          decoration: BoxDecoration(
            color: active ? Tokens.accent : Tokens.surface2,
            borderRadius: BorderRadius.circular(Tokens.rSm),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: active ? Tokens.onAccent : Tokens.fgDim,
            ),
          ),
        ),
      ),
    );
  }
}

class _LevelFilter extends StatelessWidget {
  final int threshold;
  final ValueChanged<int> onSelect;
  const _LevelFilter({required this.threshold, required this.onSelect});

  static const _opts = <(String, int)>[
    ('Err', 1),
    ('Warn', 2),
    ('Info', 4),
    ('All', 8),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Tokens.surface2,
        borderRadius: BorderRadius.circular(Tokens.rSm),
      ),
      padding: const EdgeInsets.all(2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final o in _opts)
            Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: () => onSelect(o.$2),
                borderRadius: BorderRadius.circular(Tokens.rSm - 2),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: Tokens.s4,
                  ),
                  decoration: BoxDecoration(
                    color: threshold == o.$2
                        ? Tokens.accentWash
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(Tokens.rSm - 2),
                  ),
                  child: Text(
                    o.$1,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: threshold == o.$2 ? Tokens.accent : Tokens.fgDim,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onSubmit;

  const _InputBar({
    required this.controller,
    required this.focusNode,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Tokens.s16, Tokens.s8, Tokens.s16, Tokens.s12),
      child: Row(
        children: [
          const Text('›', style: TextStyle(color: Tokens.accent, fontSize: 16)),
          const SizedBox(width: Tokens.s8),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              style: const TextStyle(
                fontFamily: Tokens.mono,
                fontSize: 12.5,
                color: Tokens.fg,
              ),
              cursorColor: Tokens.accent,
              textInputAction: TextInputAction.send,
              onSubmitted: onSubmit,
              decoration: InputDecoration(
                isDense: true,
                hintText: 'command  ·  get <prop>  ·  set <prop> <value>',
                hintStyle: Tokens.caption,
                filled: true,
                fillColor: Tokens.surface2,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: Tokens.s12,
                  vertical: Tokens.s8,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(Tokens.rSm),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WatchInput extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onAdd;
  const _WatchInput({required this.controller, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            style: const TextStyle(
              fontFamily: Tokens.mono,
              fontSize: 12.5,
              color: Tokens.fg,
            ),
            cursorColor: Tokens.accent,
            textInputAction: TextInputAction.done,
            onSubmitted: onAdd,
            decoration: InputDecoration(
              isDense: true,
              hintText: 'mpv property to watch',
              hintStyle: Tokens.caption,
              prefixIcon:
                  const Icon(Icons.visibility_rounded, size: 16, color: Tokens.fgDim),
              prefixIconConstraints: const BoxConstraints(minWidth: 36),
              filled: true,
              fillColor: Tokens.surface2,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: Tokens.s12,
                vertical: Tokens.s8,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(Tokens.rSm),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        const SizedBox(width: Tokens.s8),
        IconButton(
          onPressed: () => onAdd(controller.text),
          icon: const Icon(Icons.add_rounded, size: 20),
          color: Tokens.accent,
          tooltip: 'Watch',
        ),
      ],
    );
  }
}
