/// A Material 3 color picker tuned for subtitle styling.
///
/// Small, keyboard- and touch-friendly: preset swatches for the classics,
/// HSV sliders for free-form mixing, an alpha slider (background boxes),
/// and a live preview chip. Returns `null` when cancelled.

library aftab_color_picker;

import 'package:flutter/material.dart';

import '../design/tokens.dart';

/// Common subtitle colors (shown first, one tap away).
const List<Color> _kPresets = <Color>[
  Color(0xFFFFFFFF),
  Color(0xFF000000),
  Color(0xFFFFFF00),
  Color(0xFF00E5FF),
  Color(0xFFFF5252),
  Color(0xFF69F0AE),
  Color(0xFF448AFF),
  Color(0xFFFFAB40),
];

/// Opens the picker; resolves to the chosen color or `null`.
Future<Color?> showAftabColorPicker(
  BuildContext context, {
  required Color initial,
  String? title,
  bool withAlpha = true,
}) {
  return showDialog<Color?>(
    context: context,
    builder: (dialogContext) => _ColorPickerDialog(
      initial: initial,
      title: title,
      withAlpha: withAlpha,
    ),
  );
}

class _ColorPickerDialog extends StatefulWidget {
  const _ColorPickerDialog({
    required this.initial,
    this.title,
    required this.withAlpha,
  });

  final Color initial;
  final String? title;
  final bool withAlpha;

  @override
  State<_ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<_ColorPickerDialog> {
  late HSVColor _hsv = HSVColor.fromColor(widget.initial);
  late double _alpha = widget.initial.a;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context);
    final color = _hsv.toColor().withValues(alpha: _alpha);

    return AlertDialog(
      title: widget.title == null ? null : Text(widget.title!),
      contentPadding: const EdgeInsets.fromLTRB(
          AftabSpacing.lg, AftabSpacing.lg, AftabSpacing.lg, 0),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // Live preview.
            Container(
              height: 64,
              decoration: BoxDecoration(
                color: s.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(AftabRadius.md),
              ),
              alignment: Alignment.center,
              child: Container(
                width: 72,
                height: 40,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(AftabRadius.sm),
                  border: Border.all(color: s.colorScheme.outline),
                ),
              ),
            ),
            const SizedBox(height: AftabSpacing.lg),
            Wrap(
              spacing: AftabSpacing.sm,
              runSpacing: AftabSpacing.sm,
              children: <Widget>[
                for (final preset in _kPresets)
                  _PresetSwatch(
                    color: preset,
                    selected: color == preset,
                    onTap: () => setState(() {
                      _hsv = HSVColor.fromColor(preset);
                      _alpha = preset.a;
                    }),
                  ),
              ],
            ),
            const SizedBox(height: AftabSpacing.lg),
            _SliderRow(
              icon: Icons.palette_outlined,
              value: _hsv.hue,
              max: 360,
              onChanged: (v) => setState(() {
                _hsv = _hsv.withHue(v);
              }),
            ),
            _SliderRow(
              icon: Icons.water_drop_outlined,
              value: _hsv.saturation * 100,
              max: 100,
              onChanged: (v) => setState(() {
                _hsv = _hsv.withSaturation(v / 100);
              }),
            ),
            _SliderRow(
              icon: Icons.contrast,
              value: _hsv.value * 100,
              max: 100,
              onChanged: (v) => setState(() {
                _hsv = _hsv.withValue(v / 100);
              }),
            ),
            if (widget.withAlpha)
              _SliderRow(
                icon: Icons.opacity,
                value: _alpha * 100,
                max: 100,
                onChanged: (v) => setState(() => _alpha = v / 100),
              ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(color),
          child: Text(MaterialLocalizations.of(context).okButtonLabel),
        ),
      ],
    );
  }
}

class _PresetSwatch extends StatelessWidget {
  const _PresetSwatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        customBorder: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AftabRadius.sm),
        ),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(AftabRadius.sm),
            border: Border.all(
              color: selected ? scheme.primary : scheme.outline,
              width: selected ? 3 : 1,
            ),
          ),
        ),
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.icon,
    required this.value,
    required this.max,
    required this.onChanged,
  });

  final IconData icon;
  final double value;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.onSurfaceVariant),
        const SizedBox(width: AftabSpacing.md),
        Expanded(
          child: Slider(
            value: value.clamp(0.0, max).toDouble(),
            max: max,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 40,
          child: Text(
            value.round().toString(),
            textAlign: TextAlign.end,
            style: Theme.of(context).textTheme.labelMedium,
          ),
        ),
      ],
    );
  }
}
