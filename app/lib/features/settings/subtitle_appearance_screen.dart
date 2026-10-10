/// Subtitle appearance editor: font, size, colors, outline, background,
/// position, weight/slant — with a live libass-like preview.
///
/// Opens from Settings (edits persisted defaults) and from the player
/// (additionally applies the style to the running playback through
/// [onApply]).

library aftab_subtitle_appearance_screen;

import 'dart:async' show unawaited;

import 'package:flutter/material.dart';

import '../../data/player_settings.dart';
import '../../design/tokens.dart';
import '../../l10n/app_localizations.dart';
import '../../navigation/app_scope.dart';
import '../../player/subtitle_style.dart';
import '../../utils/format.dart';
import '../../widgets/color_picker.dart';

class SubtitleAppearanceScreen extends StatefulWidget {
  const SubtitleAppearanceScreen({super.key, this.onApply});

  /// Live application hook (the running player); `null` in Settings.
  final void Function(SubtitleStyle style)? onApply;

  @override
  State<SubtitleAppearanceScreen> createState() =>
      _SubtitleAppearanceScreenState();
}

class _SubtitleAppearanceScreenState extends State<SubtitleAppearanceScreen> {
  PlayerSettingsController? _settings;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _settings ??= AppScope.playerSettingsOf(context);
  }

  void _update(SubtitleStyle style) {
    final settings = _settings;
    if (settings == null) return;
    unawaited(settings.updateSubtitleStyle(style));
    widget.onApply?.call(style);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final settings = _settings ?? AppScope.playerSettingsOf(context);
    final isFa = Localizations.localeOf(context).languageCode == 'fa';

    return Scaffold(
      appBar: AppBar(
        title: Text(s.subsAppearanceTitle),
        actions: <Widget>[
          IconButton(
            tooltip: s.resetDefaults,
            icon: const Icon(Icons.restart_alt),
            onPressed: () {
              unawaited(settings.resetSubtitleStyle());
              widget.onApply?.call(const SubtitleStyle());
            },
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: settings,
        builder: (context, _) {
          final style = settings.subtitleStyle;
          return ListView(
            padding: const EdgeInsets.symmetric(vertical: AftabSpacing.sm),
            children: <Widget>[
              _Preview(style: style, sample: s.subsPreviewSample),
              _sectionHeader(context, s.subsSectionText),
              _fontTile(context, s, settings, style),
              _sliderTile(
                context: context,
                icon: Icons.format_size,
                title: s.subsFontSize,
                value: style.fontSize,
                min: SubtitleStyle.minFontSize,
                max: SubtitleStyle.maxFontSize,
                isFa: isFa,
                onChanged: (v) => _update(style.copyWith(fontSize: v)),
              ),
              _colorTile(
                context: context,
                icon: Icons.text_fields,
                title: s.subsTextColor,
                color: style.color,
                withAlpha: false,
                onPicked: (c) => _update(style.copyWith(color: c)),
              ),
              _sectionHeader(context, s.subsSectionOutline),
              _sliderTile(
                context: context,
                icon: Icons.circle_outlined,
                title: s.subsOutlineWidth,
                value: style.outlineSize,
                min: 0,
                max: SubtitleStyle.maxOutlineSize,
                isFa: isFa,
                onChanged: (v) => _update(style.copyWith(outlineSize: v)),
              ),
              _colorTile(
                context: context,
                icon: Icons.donut_small,
                title: s.subsOutlineColor,
                color: style.outlineColor,
                withAlpha: false,
                onPicked: (c) => _update(style.copyWith(outlineColor: c)),
              ),
              _colorTile(
                context: context,
                icon: Icons.format_color_fill,
                title: s.subsBackgroundColor,
                color: style.background,
                withAlpha: true,
                onPicked: (c) => _update(style.copyWith(background: c)),
              ),
              _sectionHeader(context, s.subsSectionShape),
              SwitchListTile(
                secondary: const Icon(Icons.format_bold),
                title: Text(s.subsBold),
                value: style.bold,
                onChanged: (v) => _update(style.copyWith(bold: v)),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.format_italic),
                title: Text(s.subsItalic),
                value: style.italic,
                onChanged: (v) => _update(style.copyWith(italic: v)),
              ),
              _sliderTile(
                context: context,
                icon: Icons.vertical_align_center,
                title: s.subsPosition,
                value: style.position,
                min: SubtitleStyle.minPosition,
                max: SubtitleStyle.maxPosition,
                isFa: isFa,
                unit: '%',
                onChanged: (v) => _update(style.copyWith(position: v)),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.layers_clear),
                title: Text(s.subsOverrideEmbedded),
                subtitle: Text(s.subsOverrideEmbeddedHint),
                value: style.overrideEmbedded,
                onChanged: (v) =>
                    _update(style.copyWith(overrideEmbedded: v)),
              ),
              const SizedBox(height: AftabSpacing.lg),
            ],
          );
        },
      ),
    );
  }

  Widget _sectionHeader(BuildContext context, String title) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.only(
        start: AftabSpacing.xl,
        top: AftabSpacing.md,
        bottom: AftabSpacing.xs,
      ),
      child: Text(
        title,
        style: theme.textTheme.labelLarge
            ?.copyWith(color: theme.colorScheme.primary),
      ),
    );
  }

  Widget _fontTile(BuildContext context, S s,
      PlayerSettingsController settings, SubtitleStyle style) {
    return ListTile(
      leading: const Icon(Icons.font_download_outlined),
      title: Text(s.subsFont),
      trailing: Text(
        style.fontFamily,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
      ),
      onTap: () => _pickFont(context, settings, style),
    );
  }

  Future<void> _pickFont(BuildContext context,
      PlayerSettingsController settings, SubtitleStyle style) async {
    final s = S.of(context);
    final family = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: AftabSpacing.lg),
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(AftabSpacing.lg),
              child: Text(s.subsFont,
                  style: Theme.of(sheetContext).textTheme.titleMedium),
            ),
            for (final choice in kSubtitleFontChoices)
              ListTile(
                title: Text(choice),
                trailing: choice == style.fontFamily
                    ? const Icon(Icons.check)
                    : null,
                onTap: () => Navigator.of(sheetContext).pop(choice),
              ),
            ListTile(
              leading: const Icon(Icons.keyboard_alt_outlined),
              title: Text(s.subsFontCustom),
              subtitle: Text(s.subsFontCustomHint),
              onTap: () async {
                final custom = await showDialog<String>(
                  context: sheetContext,
                  builder: (dialogContext) => const _CustomFontDialog(),
                );
                if (custom != null && sheetContext.mounted) {
                  Navigator.of(sheetContext).pop(custom);
                }
              },
            ),
          ],
        ),
      ),
    );
    if (family == null || !mounted) return;
    _update(style.copyWith(fontFamily: family));
  }

  Widget _sliderTile({
    required BuildContext context,
    required IconData icon,
    required String title,
    required double value,
    required double min,
    required double max,
    required bool isFa,
    String unit = '',
    required ValueChanged<double> onChanged,
  }) {
    final label = '${formatDouble(value, persian: isFa)}$unit';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsetsDirectional.only(
              start: AftabSpacing.xl, end: AftabSpacing.lg),
          child: Row(
            children: <Widget>[
              Icon(icon,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(width: AftabSpacing.md),
              Expanded(child: Text(title)),
              Text(label, style: Theme.of(context).textTheme.labelMedium),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsetsDirectional.only(
              start: AftabSpacing.xl, end: AftabSpacing.lg),
          child: Slider(
            value: value.clamp(min, max).toDouble(),
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  Widget _colorTile({
    required BuildContext context,
    required IconData icon,
    required String title,
    required Color color,
    required bool withAlpha,
    required ValueChanged<Color> onPicked,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(icon, color: scheme.onSurfaceVariant),
      title: Text(title),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: scheme.outline),
            ),
          ),
          const Icon(Icons.chevron_right),
        ],
      ),
      onTap: () async {
        final picked = await showAftabColorPicker(
          context,
          initial: color,
          title: title,
          withAlpha: withAlpha,
        );
        if (picked != null) onPicked(picked);
      },
    );
  }
}

/// Live preview approximating libass output: background box, stroked
/// outline, filled text — scaled as mpv would at a 720p window.
class _Preview extends StatelessWidget {
  const _Preview({required this.style, required this.sample});

  final SubtitleStyle style;
  final String sample;

  /// Preview pane stands in for a 720p-tall window.
  static const double _paneHeight = 176;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const scale = _paneHeight / 720;
    final fontSize = (style.fontSize * scale).clamp(8.0, 64.0);
    final outlineWidth = style.outlineSize * scale;
    final family = _previewFamily(style.fontFamily);

    // Higher sub-pos = closer to the bottom edge (mpv semantics).
    final bottomInset =
        (style.position - SubtitleStyle.minPosition) / 80 * 96;

    final text = Text(
      sample,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontFamily: family,
        fontSize: fontSize,
        fontWeight: style.bold ? FontWeight.w700 : FontWeight.w400,
        fontStyle: style.italic ? FontStyle.italic : FontStyle.normal,
        color: style.color,
      ),
    );

    final outlined = outlineWidth >= 0.5
        ? Stack(
            children: <Widget>[
              Text(
                sample,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: family,
                  fontSize: fontSize,
                  fontWeight: style.bold ? FontWeight.w700 : FontWeight.w400,
                  fontStyle:
                      style.italic ? FontStyle.italic : FontStyle.normal,
                  foreground: Paint()
                    ..style = PaintingStyle.stroke
                    ..strokeWidth = outlineWidth * 2
                    ..strokeJoin = StrokeJoin.round
                    ..color = style.outlineColor,
                ),
              ),
              text,
            ],
          )
        : text;

    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AftabSpacing.lg, vertical: AftabSpacing.sm),
      child: Semantics(
        label: S.of(context).subsPreviewSample,
        child: Container(
          height: _paneHeight + AftabSpacing.lg,
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(AftabRadius.md),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Stack(
            children: <Widget>[
              // A hint of "video" behind the subtitle.
              const Align(
                alignment: AlignmentDirectional.topStart,
                child: Padding(
                  padding: EdgeInsets.all(AftabSpacing.sm),
                  child: Icon(Icons.movie_filter_outlined,
                      color: Colors.white24, size: 20),
                ),
              ),
              PositionedDirectional(
                start: AftabSpacing.lg,
                end: AftabSpacing.lg,
                bottom: AftabSpacing.sm + bottomInset.clamp(0.0, 120.0),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AftabSpacing.sm, vertical: 2),
                  color: style.background.a == 0
                      ? null
                      : style.background,
                  child: Center(child: outlined),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String? _previewFamily(String family) {
    // Generic families have no Flutter equivalent — the default family is
    // the closest honest approximation.
    return family == 'Vazirmatn' ? family : null;
  }
}

/// Text-field dialog for entering a custom font family name.
class _CustomFontDialog extends StatefulWidget {
  const _CustomFontDialog();

  @override
  State<_CustomFontDialog> createState() => _CustomFontDialogState();
}

class _CustomFontDialogState extends State<_CustomFontDialog> {
  final TextEditingController _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return AlertDialog(
      title: Text(s.subsFontCustom),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 48,
        onChanged: (_) {
          if (_error != null) setState(() => _error = null);
        },
        decoration: InputDecoration(
          hintText: 'Roboto',
          errorText: _error,
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child:
              Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        FilledButton(
          onPressed: () {
            final value = _controller.text.trim();
            if (isValidCustomFontFamily(value)) {
              Navigator.of(context).pop(value);
            } else {
              setState(() => _error = s.subsFontCustomInvalid);
            }
          },
          child: Text(MaterialLocalizations.of(context).okButtonLabel),
        ),
      ],
    );
  }
}
