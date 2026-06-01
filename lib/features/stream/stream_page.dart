import 'package:flutter/material.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';

import '../../state/player_scope.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets/section_body.dart';
import 'media_server.dart';
import 'server_library_tab.dart';

/// One streamable reference URL.
class StreamItem {
  final String label;
  final String url;
  const StreamItem({required this.label, required this.url});
}

/// A named group of [StreamItem]s.
class StreamCategory {
  final String name;
  final List<StreamItem> items;
  const StreamCategory({required this.name, required this.items});
}

/// Reference network streams (codecs, lossless, HLS) to exercise the
/// engine's network + demuxer paths. Tap to play, or queue with the
/// add button.
const _streamCategories = <StreamCategory>[
  StreamCategory(name: 'MP3 reference', items: [
    StreamItem(
      label: 'MP3 128k Stereo (standard)',
      url: 'https://streams.radiomast.io/ref-128k-mp3-stereo',
    ),
    StreamItem(
      label: 'MP3 128k Stereo (with preroll)',
      url: 'https://streams.radiomast.io/ref-128k-mp3-stereo-preroll',
    ),
    StreamItem(
      label: 'MP3 32k Mono (low-bandwidth)',
      url: 'https://streams.radiomast.io/ref-32k-mp3-mono',
    ),
  ]),
  StreamCategory(name: 'AAC reference', items: [
    StreamItem(
      label: 'AAC-LC 128k Stereo',
      url: 'https://streams.radiomast.io/ref-128k-aaclc-stereo',
    ),
    StreamItem(
      label: 'HE-AAC v1 64k Stereo (SBR)',
      url: 'https://streams.radiomast.io/ref-64k-heaacv1-stereo',
    ),
    StreamItem(
      label: 'HE-AAC v2 64k Stereo (SBR+PS)',
      url: 'https://streams.radiomast.io/ref-64k-heaacv2-stereo',
    ),
    StreamItem(
      label: 'HE-AAC v1 24k Mono',
      url: 'https://streams.radiomast.io/ref-24k-heaacv1-mono',
    ),
  ]),
  StreamCategory(name: 'Ogg / open formats', items: [
    StreamItem(
      label: 'Ogg Vorbis 64k Stereo',
      url: 'https://streams.radiomast.io/ref-64k-ogg-vorbis-stereo',
    ),
    StreamItem(
      label: 'Ogg Opus 64k Stereo',
      url: 'https://streams.radiomast.io/ref-64k-ogg-opus-stereo',
    ),
  ]),
  StreamCategory(name: 'Lossless & hi-fi', items: [
    StreamItem(
      label: 'Ogg FLAC (16-bit lossless)',
      url: 'https://streams.radiomast.io/ref-lossless-ogg-flac-stereo',
    ),
    StreamItem(
      label: 'Radio Paradise (main mix FLAC)',
      url: 'http://stream.radioparadise.com/flacm',
    ),
  ]),
  StreamCategory(name: 'HLS (HTTP Live Streaming)', items: [
    StreamItem(
      label: 'MP3 128k HLS adaptive',
      url: 'https://streams.radiomast.io/ref-128k-mp3-stereo/hls.m3u8',
    ),
    StreamItem(
      label: 'AAC-LC 128k HLS adaptive',
      url: 'https://streams.radiomast.io/ref-128k-aaclc-stereo/hls.m3u8',
    ),
    StreamItem(
      label: 'Apple BipBop (HLS audio)',
      url:
          'https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_4x3/gear0/prog_index.m3u8',
    ),
  ]),
];

/// The Stream surface: three windowed tabs — **Lab** (reference network
/// streams), **Jellyfin**, and **Plex** (connect to a server and browse the
/// paginated music library). The two media-server clients are created once
/// and kept alive for the lifetime of the page.
class StreamPage extends StatefulWidget {
  const StreamPage({super.key});

  @override
  State<StreamPage> createState() => _StreamPageState();
}

class _StreamPageState extends State<StreamPage> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    // Servers live app-level (see PlayerScope) so their sessions and the
    // playback reporting persist across navigating away from this page.
    final jellyfin = PlayerScope.serverOf(context, ServerKind.jellyfin);
    final plex = PlayerScope.serverOf(context, ServerKind.plex);
    return Column(
      children: [
        _ChromeTabBar(
          selected: _tab,
          tabs: const ['Lab', 'Jellyfin', 'Plex'],
          onSelect: (i) => setState(() => _tab = i),
        ),
        Expanded(
          child: IndexedStack(
            index: _tab,
            sizing: StackFit.expand,
            children: [
              const _LabTab(),
              ServerLibraryTab(server: jellyfin),
              ServerLibraryTab(server: plex),
            ],
          ),
        ),
      ],
    );
  }
}

/// A Chrome/VS-Code-style tab strip: a raised [Tokens.surface] bar with
/// rounded-top tabs. The active tab is filled with the content colour
/// ([Tokens.bg]) so it visually merges into the page below, topped by an
/// accent line; inactive tabs are transparent and dim.
class _ChromeTabBar extends StatelessWidget {
  final int selected;
  final List<String> tabs;
  final ValueChanged<int> onSelect;

  const _ChromeTabBar({
    required this.selected,
    required this.tabs,
    required this.onSelect,
  });

  static const _radius = BorderRadius.vertical(top: Radius.circular(12));
  static const _shape = ContinuousRectangleBorder(borderRadius: _radius);

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Tokens.surface,
      padding: const EdgeInsets.only(
          top: Tokens.s6, left: Tokens.s8, right: Tokens.s8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < tabs.length; i++) _tab(i),
        ],
      ),
    );
  }

  Widget _tab(int i) {
    final active = i == selected;
    return Padding(
      padding: const EdgeInsets.only(right: Tokens.s4),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: () => onSelect(i),
          customBorder: _shape,
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: ShapeDecoration(
              color: active ? Tokens.bg : Colors.transparent,
              shape: _shape,
            ),
            // IntrinsicWidth bounds the column to the label width inside the
            // unconstrained Row, so the stretched accent bar isn't asked for
            // an infinite width.
            child: IntrinsicWidth(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    height: 2,
                    color: active ? Tokens.accent : Colors.transparent,
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                        Tokens.s16, Tokens.s6, Tokens.s16, Tokens.s12),
                    child: Text(
                      tabs[i],
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight:
                            active ? FontWeight.w600 : FontWeight.w500,
                        color: active ? Tokens.fg : Tokens.fgDim,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Reference-stream browser (the original Stream content).
class _LabTab extends StatelessWidget {
  const _LabTab();

  @override
  Widget build(BuildContext context) {
    final player = PlayerScope.of(context);
    return SectionBody(
      children: [
        for (final cat in _streamCategories) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Tokens.s4,
              Tokens.s8,
              Tokens.s4,
              Tokens.s8,
            ),
            child: Text(cat.name.toUpperCase(), style: Tokens.caption),
          ),
          for (final item in cat.items) _StreamTile(player: player, item: item),
          const SizedBox(height: Tokens.s12),
        ],
      ],
    );
  }
}

class _StreamTile extends StatelessWidget {
  final Player player;
  final StreamItem item;
  const _StreamTile({required this.player, required this.item});

  Media get _media =>
      Media(item.url, extras: {'title': item.label, 'artist': 'Stream'});

  void _play() => player.open(_media, play: true);

  void _enqueue() {
    if (player.state.playlist.items.isEmpty) {
      player.open(_media, play: true);
    } else {
      player.add(_media);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: Tokens.s8),
      decoration: ShapeDecoration(
        color: Tokens.surface,
        shape: Tokens.squircle(Tokens.rMd),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: _play,
          customBorder: Tokens.squircle(Tokens.rMd),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              Tokens.s16,
              Tokens.s12,
              Tokens.s8,
              Tokens.s12,
            ),
            child: Row(
              children: [
                const Icon(Icons.podcasts_rounded,
                    size: 18, color: Tokens.fgDim),
                const SizedBox(width: Tokens.s12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.label,
                        style: Tokens.body,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item.url,
                        style: Tokens.caption,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: _enqueue,
                  icon: const Icon(Icons.playlist_add_rounded, size: 18),
                  color: Tokens.fgDim,
                  splashRadius: 18,
                  tooltip: 'Add to queue',
                ),
                IconButton(
                  onPressed: _play,
                  icon: const Icon(Icons.play_arrow_rounded, size: 20),
                  color: Tokens.accent,
                  splashRadius: 18,
                  tooltip: 'Play',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
