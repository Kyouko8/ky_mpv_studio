import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';

import '../../../ui/tokens.dart';
import '../../../ui/widgets/controls.dart';
import '../../../ui/widgets/section_body.dart';

/// Hooks Lab — recipe-based playground for [Player.registerHook]. Each
/// recipe is a real interception pattern; toggling one registers the
/// hooks it needs (mpv has no public unregister, so a disabled recipe
/// just becomes a no-op handler). The activity log shows every fire.
class HooksGroup extends StatefulWidget {
  final Player player;
  const HooksGroup(this.player, {super.key});

  @override
  State<HooksGroup> createState() => _HooksGroupState();
}

enum _Recipe { headers, fallback, pickAudio, trace }

class _RecipeSpec {
  final String title;
  final String description;
  final IconData icon;
  final Set<Hook> hooks;
  const _RecipeSpec({
    required this.title,
    required this.description,
    required this.icon,
    required this.hooks,
  });
}

const _recipeSpecs = <_Recipe, _RecipeSpec>{
  _Recipe.headers: _RecipeSpec(
    title: 'Inject HTTP headers',
    description:
        'Adds Authorization + User-Agent headers on every http(s) stream, '
        'scoped per file. Skipped on local files.',
    icon: Icons.vpn_key_rounded,
    hooks: {Hook.load},
  ),
  _Recipe.fallback: _RecipeSpec(
    title: 'HTTPS → HTTP fallback',
    description:
        'When a TLS handshake fails, rewrites the URL to plain http and mpv '
        'retries the open. Skipped if the URL is not https.',
    icon: Icons.swap_horiz_rounded,
    hooks: {Hook.loadFail},
  ),
  _Recipe.pickAudio: _RecipeSpec(
    title: 'Force first audio track',
    description:
        'Right before decoder init, sets aid=1 — overriding the container '
        'default. Useful when the muxer picks the wrong language.',
    icon: Icons.audiotrack_rounded,
    hooks: {Hook.preloaded},
  ),
  _Recipe.trace: _RecipeSpec(
    title: 'Lifecycle trace',
    description:
        'Passive observer — registers every phase and only logs, to show '
        'the firing order.',
    icon: Icons.timeline_rounded,
    hooks: {
      Hook.beforeStartFile,
      Hook.load,
      Hook.loadFail,
      Hook.preloaded,
      Hook.unload,
      Hook.afterEndFile,
    },
  ),
};

class _RecipeAction {
  final _Recipe recipe;
  final String label;
  final String? detail;
  const _RecipeAction(this.recipe, this.label, this.detail);
}

class _LogEntry {
  final Hook hook;
  final int id;
  final String url;
  final List<_RecipeAction> actions;
  const _LogEntry({
    required this.hook,
    required this.id,
    required this.url,
    required this.actions,
  });
}

class _HooksGroupState extends State<HooksGroup> {
  final Set<_Recipe> _enabled = {};
  final List<_LogEntry> _log = [];
  StreamSubscription<MpvHookEvent>? _hookSub;

  Player get player => widget.player;

  @override
  void dispose() {
    _hookSub?.cancel();
    super.dispose();
  }

  void _toggleRecipe(_Recipe r, bool enable) {
    setState(() => enable ? _enabled.add(r) : _enabled.remove(r));
    if (enable) {
      for (final h in _recipeSpecs[r]!.hooks) {
        player.registerHook(h, timeout: const Duration(seconds: 5));
      }
      _hookSub ??= player.stream.hook.listen(_handleHook);
    } else if (_enabled.isEmpty) {
      _hookSub?.cancel();
      _hookSub = null;
    }
  }

  Future<void> _handleHook(MpvHookEvent event) async {
    final url = await player.getRawProperty('stream-open-filename') ?? '';
    final actions = <_RecipeAction>[];
    for (final r in _Recipe.values) {
      if (!_enabled.contains(r)) continue;
      if (!_recipeSpecs[r]!.hooks.contains(event.hook)) continue;
      final a = await _runRecipe(r, url);
      if (a != null) actions.add(a);
    }
    if (mounted) {
      setState(() {
        _log.insert(
          0,
          _LogEntry(
            hook: event.hook,
            id: event.id,
            url: url,
            actions: actions,
          ),
        );
        if (_log.length > 30) _log.removeRange(30, _log.length);
      });
    }
    // Always continue — registrations persist after a recipe is disabled.
    player.continueHook(event.id);
  }

  Future<_RecipeAction?> _runRecipe(_Recipe r, String url) async {
    switch (r) {
      case _Recipe.headers:
        if (!url.startsWith('http')) {
          return const _RecipeAction(_Recipe.headers, 'skipped', 'local URL');
        }
        const headers = 'Authorization: Bearer demo-token,'
            'User-Agent: mpv_studio/1.0';
        await player.setRawProperty(
          'file-local-options/http-header-fields',
          headers,
        );
        return const _RecipeAction(_Recipe.headers, 'injected headers', null);
      case _Recipe.fallback:
        if (!url.startsWith('https://')) {
          return const _RecipeAction(_Recipe.fallback, 'skipped', 'not https');
        }
        final downgraded = url.replaceFirst('https://', 'http://');
        await player.setRawProperty('stream-open-filename', downgraded);
        return _RecipeAction(_Recipe.fallback, 'rewrote to http', downgraded);
      case _Recipe.pickAudio:
        await player.setRawProperty('aid', '1');
        return const _RecipeAction(_Recipe.pickAudio, 'forced aid=1', null);
      case _Recipe.trace:
        return const _RecipeAction(_Recipe.trace, 'observed', null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsGroup(
          label: 'Recipes',
          children: [
            for (final r in _Recipe.values)
              SwitchRow(
                label: _recipeSpecs[r]!.title,
                subtitle: _recipeSpecs[r]!.description,
                value: _enabled.contains(r),
                onChanged: (v) => _toggleRecipe(r, v),
              ),
          ],
        ),
        Padding(
          padding:
              const EdgeInsets.fromLTRB(Tokens.s4, 0, Tokens.s4, Tokens.s8),
          child: Row(
            children: [
              Expanded(child: Text('ACTIVITY', style: Tokens.caption)),
              if (_log.isNotEmpty)
                GestureDetector(
                  onTap: () => setState(_log.clear),
                  child: Text('Clear',
                      style: Tokens.caption.copyWith(color: Tokens.accent)),
                ),
            ],
          ),
        ),
        if (_log.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Tokens.s24),
            child: Text(
              _enabled.isEmpty
                  ? 'Enable a recipe above, then play a track to see hooks fire.'
                  : 'Waiting for the next file load…',
              style: Tokens.caption,
              textAlign: TextAlign.center,
            ),
          )
        else
          for (final e in _log) _LogTile(entry: e),
      ],
    );
  }
}

class _LogTile extends StatelessWidget {
  final _LogEntry entry;
  const _LogTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: Tokens.s6),
      padding: const EdgeInsets.symmetric(
        horizontal: Tokens.s12,
        vertical: Tokens.s8,
      ),
      decoration: ShapeDecoration(
        color: Tokens.surface,
        shape: Tokens.squircle(
          Tokens.rSm,
          side: const BorderSide(color: Tokens.line, width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(entry.hook.mpvValue,
                  style: Tokens.numeric.copyWith(color: Tokens.accent)),
              const SizedBox(width: Tokens.s8),
              Text('id=${entry.id}', style: Tokens.numeric),
            ],
          ),
          if (entry.url.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(entry.url,
                style: Tokens.numeric,
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
          ],
          if (entry.actions.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('(no recipe acted — auto-continued)',
                  style: Tokens.caption),
            )
          else
            for (final a in entry.actions)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  '• ${_recipeSpecs[a.recipe]!.title}: ${a.label}'
                  '${a.detail != null ? ' (${a.detail})' : ''}',
                  style: Tokens.caption.copyWith(color: Tokens.fgDim),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
        ],
      ),
    );
  }
}
