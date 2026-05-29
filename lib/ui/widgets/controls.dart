import 'package:flutter/material.dart';

import '../tokens.dart';

/// Label + value readout above a full-width flat slider. The single
/// numeric control used across Effects and Settings. Double-tap the row
/// to reset to [resetTo] when provided.
class SliderRow extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;

  /// Formats the trailing value readout. Defaults to one decimal place.
  final String Function(double value)? format;

  /// When non-null, double-tapping the row snaps back to this value.
  final double? resetTo;

  final bool enabled;

  const SliderRow({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.onChangeEnd,
    this.divisions,
    this.format,
    this.resetTo,
    this.enabled = true,
  });

  String _fmt(double v) => format?.call(v) ?? v.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final clamped = value.clamp(min, max);
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: Tokens.body.copyWith(
                  color: enabled ? Tokens.fg : Tokens.fgFaint,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: Tokens.s12),
            Text(
              _fmt(clamped),
              style: Tokens.numeric.copyWith(
                color: enabled ? Tokens.accent : Tokens.fgFaint,
              ),
            ),
          ],
        ),
        SizedBox(
          height: 28,
          child: Slider(
            value: clamped,
            min: min,
            max: max,
            divisions: divisions,
            onChanged: enabled ? onChanged : null,
            onChangeEnd: enabled ? onChangeEnd : null,
          ),
        ),
      ],
    );
    if (resetTo == null) return body;
    return GestureDetector(
      onDoubleTap: enabled ? () => onChanged(resetTo!) : null,
      behavior: HitTestBehavior.opaque,
      child: body,
    );
  }
}

/// Label (+ optional subtitle) on the left, a flat [Switch] on the right.
class SwitchRow extends StatelessWidget {
  final String label;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool enabled;

  const SwitchRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? () => onChanged(!value) : null,
      borderRadius: BorderRadius.circular(Tokens.rSm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Tokens.s6),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: Tokens.body.copyWith(
                      color: enabled ? Tokens.fg : Tokens.fgFaint,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle!, style: Tokens.caption),
                  ],
                ],
              ),
            ),
            const SizedBox(width: Tokens.s12),
            Switch(
              value: value,
              onChanged: enabled ? onChanged : null,
            ),
          ],
        ),
      ),
    );
  }
}

/// One selectable option in a [SegmentedControl].
class SegmentOption<T> {
  final T value;
  final String label;
  const SegmentOption(this.value, this.label);
}

/// A flat pill of mutually-exclusive options. Used for short enum picks
/// (loop, gapless, cache mode, normalization, FFT window).
class SegmentedControl<T> extends StatelessWidget {
  final List<SegmentOption<T>> options;
  final T selected;
  final ValueChanged<T> onSelect;

  const SegmentedControl({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Tokens.surface2,
        borderRadius: BorderRadius.circular(Tokens.rSm),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        children: [
          for (final o in options)
            Expanded(
              child: _Segment(
                label: o.label,
                active: o.value == selected,
                onTap: () => onSelect(o.value),
              ),
            ),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _Segment({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Tokens.rSm - 2),
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(vertical: Tokens.s8),
          decoration: BoxDecoration(
            color: active ? Tokens.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(Tokens.rSm - 2),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
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

/// Label on the left, a flat dropdown on the right. Used when the option
/// set is too long for a [SegmentedControl] (devices, channel layouts).
class DropdownRow<T> extends StatelessWidget {
  final String label;

  /// Current selection. Pass `null` (with a [hint]) when the live value
  /// isn't among [items], so the dropdown shows the hint rather than
  /// asserting.
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  final String? hint;

  const DropdownRow({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Tokens.s4),
      child: Row(
        children: [
          Flexible(child: Text(label, style: Tokens.body)),
          const SizedBox(width: Tokens.s12),
          SizedBox(
            width: 200,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: Tokens.s12),
              decoration: BoxDecoration(
                color: Tokens.surface2,
                borderRadius: BorderRadius.circular(Tokens.rSm),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<T>(
                  value: value,
                  items: items,
                  onChanged: onChanged,
                  isDense: true,
                  // Fill the fixed width and ellipsize the selected
                  // label rather than overflow on long device names.
                  isExpanded: true,
                  hint: hint == null
                      ? null
                      : Text(
                          hint!,
                          style: Tokens.caption,
                          overflow: TextOverflow.ellipsis,
                        ),
                  borderRadius: BorderRadius.circular(Tokens.rSm),
                  dropdownColor: Tokens.surface3,
                  style: Tokens.body,
                  icon: const Icon(
                    Icons.expand_more_rounded,
                    size: 18,
                    color: Tokens.fgDim,
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
