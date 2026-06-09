import 'package:flutter/material.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';

import '../../../generated/filter_catalog.dart';
import '../../../studio/player_scope.dart';
import '../../../ui/tokens.dart';
import '../../../ui/widgets/controls.dart';
import '../../../ui/widgets/module_card.dart';

/// Renders one [ParamSpec] as the app control that fits its type — the single
/// place that maps a logical param to a widget (slider / dropdown / switch /
/// text). Every value flows through the spec's typed get/set closures over the
/// [AudioEffects] bundle, so this is filter-agnostic.
Widget buildParamControl(ParamSpec p, AudioEffects fx, Player player) {
  switch (p) {
    case DoubleParam d:
      return SliderRow(
        label: d.name,
        value: d.get(fx).clamp(d.min, d.max),
        min: d.min,
        max: d.max,
        resetTo: d.def,
        format: (v) => v.toStringAsFixed(2),
        onChanged: (v) => player.updateAudioEffects((e) => d.set(e, v)),
      );
    case IntParam d:
      return SliderRow(
        label: d.name,
        value: d.get(fx).toDouble().clamp(d.min.toDouble(), d.max.toDouble()),
        min: d.min.toDouble(),
        max: d.max.toDouble(),
        resetTo: d.def.toDouble(),
        format: (v) => v.toStringAsFixed(0),
        onChanged: (v) => player.updateAudioEffects((e) => d.set(e, v.round())),
      );
    case BoolParam b:
      return SwitchRow(
        label: b.name,
        value: b.get(fx),
        onChanged: (v) => player.updateAudioEffects((e) => b.set(e, v)),
      );
    case EnumParam en:
      return DropdownRow<Object>(
        label: en.name,
        value: en.get(fx),
        items: [
          for (final o in en.options)
            DropdownMenuItem<Object>(value: o.value, child: Text(o.label)),
        ],
        onChanged: (v) {
          if (v != null) player.updateAudioEffects((e) => en.set(e, v));
        },
      );
    case StringParam s:
      return TextRow(
        label: s.name,
        value: s.get(fx),
        onChanged: (v) => player.updateAudioEffects((e) => s.set(e, v)),
      );
  }
}

/// A generic, data-driven filter card: the typed [FilterDescriptor]'s enable
/// toggle over its parameter controls. Replaces the per-filter generated
/// widgets — the look lives here, the logic in the catalog.
class FilterCard extends StatelessWidget {
  final FilterDescriptor d;
  const FilterCard(this.d, {super.key});

  @override
  Widget build(BuildContext context) {
    final player = PlayerScope.of(context);
    return StreamBuilder<AudioEffects>(
      stream: player.stream.audioEffects.distinct(),
      initialData: player.state.audioEffects,
      builder: (context, snap) {
        final fx = snap.data!;
        return ModuleCard(
          title: d.name,
          subtitle: d.wire,
          icon: d.icon,
          enabled: d.isEnabled(fx),
          onEnabledChanged: (v) =>
              player.updateAudioEffects((e) => d.setEnabled(e, v)),
          onReset: d.params.isEmpty
              ? null
              : () => player.updateAudioEffects((e) {
                    var next = e;
                    for (final p in d.params) {
                      if (p is DoubleParam) next = p.set(next, p.def);
                      if (p is IntParam) next = p.set(next, p.def);
                    }
                    return next;
                  }),
          child: d.params.isEmpty
              ? const Text('No adjustable parameters.', style: Tokens.caption)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final p in d.params) buildParamControl(p, fx, player),
                  ],
                ),
        );
      },
    );
  }
}

/// The per-category master toggle, in its own card (same flat language and tap
/// surface as the filter cards), that turns every filter in [filters] on/off
/// at once. Safe — advanced (required-param) filters are never in a category.
class EnableAllCard extends StatelessWidget {
  final List<FilterDescriptor> filters;
  const EnableAllCard(this.filters, {super.key});

  @override
  Widget build(BuildContext context) {
    final player = PlayerScope.of(context);
    return StreamBuilder<bool>(
      stream: player.stream.audioEffects
          .map((e) => filters.every((d) => d.isEnabled(e)))
          .distinct(),
      initialData: filters.every((d) => d.isEnabled(player.state.audioEffects)),
      builder: (context, snap) {
        final allOn = snap.data ?? false;
        return Container(
          margin: const EdgeInsets.only(bottom: Tokens.s16),
          decoration: ShapeDecoration(
            color: allOn ? Tokens.accentWash : Tokens.surface,
            shape: Tokens.squircle(Tokens.rMd),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              customBorder: Tokens.squircle(Tokens.rMd),
              onTap: () {
                final on = !allOn;
                player.updateAudioEffects((e) {
                  var next = e;
                  for (final d in filters) {
                    next = d.setEnabled(next, on);
                  }
                  return next;
                });
              },
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                    Tokens.s16, Tokens.s12, Tokens.s12, Tokens.s12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('All filters', style: Tokens.heading),
                          const SizedBox(height: 2),
                          Text(
                            allOn
                                ? 'Every filter in this category is on'
                                : 'Turn every filter in this category on',
                            style: Tokens.caption,
                          ),
                        ],
                      ),
                    ),
                    AppSwitch(value: allOn),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The body of one category page: the Enable-all card above the list of
/// generic [FilterCard]s. Built entirely from the logical catalog.
class CategoryFiltersView extends StatelessWidget {
  final String slug;
  const CategoryFiltersView({super.key, required this.slug});

  @override
  Widget build(BuildContext context) {
    final filters = [
      for (final d in kFilterCatalog)
        if (d.category == slug && !d.advanced) d,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        EnableAllCard(filters),
        for (final d in filters) FilterCard(d),
      ],
    );
  }
}
