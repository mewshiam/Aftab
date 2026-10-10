/// Subtitle appearance model + libmpv property mapping.
///
/// The single source of truth for how rendered subtitles look. The model is
/// pure (no player imports) so it can be unit-tested and reused by both the
/// in-player subtitle sheet and the Settings → Subtitles screen.
///
/// Properties map onto libmpv's `sub-*` family (rendered by libass):
///
/// | Model field        | mpv property      | Notes                          |
/// |--------------------|-------------------|--------------------------------|
/// | [SubtitleStyle.fontFamily] | `sub-font` | libass resolves the family  |
/// | [SubtitleStyle.fontSize]   | `sub-font-size` | scaled px @ 720p window  |
/// | [SubtitleStyle.color]      | `sub-color` | `#AARRGGBB`, alpha first       |
/// | [SubtitleStyle.outlineSize] | `sub-outline-size` | 0 disables outline  |
/// | [SubtitleStyle.outlineColor] | `sub-outline-color` | text outline      |
/// | [SubtitleStyle.background] | `sub-back-color` | box behind each line       |
/// | [SubtitleStyle.bold] / [SubtitleStyle.italic] | `sub-bold` / `sub-italic` | yes/no |
/// | [SubtitleStyle.position]   | `sub-pos` | 100 = default bottom margin   |
/// | [SubtitleStyle.overrideEmbedded] | `sub-ass-override` | `force`/`no` |
///
/// Styling applies to plain-text subtitles (SRT/VTT/…) directly; for
/// ASS/SSA subtitles it applies only when [SubtitleStyle.overrideEmbedded]
/// is on (`sub-ass-override=force`).

library aftab_subtitle_style;

import 'package:flutter/material.dart';

/// A complete subtitle appearance, independent of any player instance.
@immutable
class SubtitleStyle {
  const SubtitleStyle({
    this.fontFamily = defaultFontFamily,
    this.fontSize = defaultFontSize,
    this.color = defaultColor,
    this.outlineSize = defaultOutlineSize,
    this.outlineColor = defaultOutlineColor,
    this.background = defaultBackground,
    this.bold = false,
    this.italic = false,
    this.position = defaultPosition,
    this.overrideEmbedded = false,
  });

  /// libass font family. See [kSubtitleFontChoices].
  final String fontFamily;

  /// Scaled pixels at a 720p window height (mpv's `sub-font-size` unit).
  static const double defaultFontSize = 38;
  final double fontSize;

  /// Minimum/maximum offered in the UI.
  static const double minFontSize = 16;
  static const double maxFontSize = 96;

  /// Text color.
  static const Color defaultColor = Color(0xFFFFFFFF);
  final Color color;

  /// Outline width; 0 disables the outline entirely.
  static const double defaultOutlineSize = 3;
  final double outlineSize;
  static const double maxOutlineSize = 8;

  /// Outline color.
  static const Color defaultOutlineColor = Color(0xFF000000);
  final Color outlineColor;

  /// Box color behind each line — fully transparent by default.
  static const Color defaultBackground = Color(0x00000000);
  final Color background;

  /// Fake-bold / fake-italic rendering (mpv `sub-bold` / `sub-italic`).
  final bool bold;
  final bool italic;

  /// Vertical position in % of screen height (mpv `sub-pos`).
  /// 100 is the default bottom placement; up to 150 pushes below it.
  static const double defaultPosition = 100;
  static const double minPosition = 50;
  static const double maxPosition = 130;
  final double position;

  /// Whether the style is forced onto ASS subtitles as well
  /// (`sub-ass-override=force`). Can break deliberately-styled karaoke
  /// tracks, so it is opt-in.
  final bool overrideEmbedded;

  /// The bundled Persian-first family — guaranteed on Android (copied by
  /// media_kit into libass's font dir) and resolvable elsewhere via
  /// fontconfig's generic fallbacks.
  static const String defaultFontFamily = 'Vazirmatn';

  SubtitleStyle copyWith({
    String? fontFamily,
    double? fontSize,
    Color? color,
    double? outlineSize,
    Color? outlineColor,
    Color? background,
    bool? bold,
    bool? italic,
    double? position,
    bool? overrideEmbedded,
  }) {
    return SubtitleStyle(
      fontFamily: fontFamily ?? this.fontFamily,
      fontSize: fontSize ?? this.fontSize,
      color: color ?? this.color,
      outlineSize: outlineSize ?? this.outlineSize,
      outlineColor: outlineColor ?? this.outlineColor,
      background: background ?? this.background,
      bold: bold ?? this.bold,
      italic: italic ?? this.italic,
      position: position ?? this.position,
      overrideEmbedded: overrideEmbedded ?? this.overrideEmbedded,
    );
  }

  /// The style expressed as libmpv properties, ready for
  /// `NativePlayer.setProperty`.
  Map<String, String> toMpvProperties() {
    return <String, String>{
      'sub-font': fontFamily,
      'sub-font-size': fontSize.round().toString(),
      'sub-color': toMpvColorString(color),
      'sub-outline-size': outlineSize.round().toString(),
      'sub-outline-color': toMpvColorString(outlineColor),
      'sub-back-color': toMpvColorString(background),
      'sub-bold': bold ? 'yes' : 'no',
      'sub-italic': italic ? 'yes' : 'no',
      'sub-pos': position.round().toString(),
      'sub-ass-override': overrideEmbedded ? 'force' : 'no',
    };
  }

  /// Serializes to the flat `key: value` map used by the settings store.
  Map<String, String> toPersisted() {
    return <String, String>{
      'font': fontFamily,
      'size': fontSize.round().toString(),
      'color': toMpvColorString(color),
      'outline_size': outlineSize.round().toString(),
      'outline_color': toMpvColorString(outlineColor),
      'background': toMpvColorString(background),
      'bold': bold ? '1' : '0',
      'italic': italic ? '1' : '0',
      'position': position.round().toString(),
      'override': overrideEmbedded ? '1' : '0',
    };
  }

  /// Restores a style from the settings store's flat map; unknown or
  /// malformed entries fall back to defaults field by field.
  static SubtitleStyle fromPersisted(Map<String, String?> persisted) {
    return SubtitleStyle(
      fontFamily: _nonBlank(persisted['font']) ?? defaultFontFamily,
      fontSize: _clampedDouble(persisted['size'], defaultFontSize,
          minFontSize, maxFontSize),
      color: parseMpvColorString(persisted['color']) ?? defaultColor,
      outlineSize: _clampedDouble(persisted['outline_size'],
          defaultOutlineSize, 0, maxOutlineSize),
      outlineColor:
          parseMpvColorString(persisted['outline_color']) ?? defaultOutlineColor,
      background: parseMpvColorString(persisted['background']) ?? defaultBackground,
      bold: persisted['bold'] == '1',
      italic: persisted['italic'] == '1',
      position: _clampedDouble(persisted['position'], defaultPosition,
          minPosition, maxPosition),
      overrideEmbedded: persisted['override'] == '1',
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SubtitleStyle &&
          other.fontFamily == fontFamily &&
          other.fontSize == fontSize &&
          other.color == color &&
          other.outlineSize == outlineSize &&
          other.outlineColor == outlineColor &&
          other.background == background &&
          other.bold == bold &&
          other.italic == italic &&
          other.position == position &&
          other.overrideEmbedded == overrideEmbedded;

  @override
  int get hashCode => Object.hash(
        fontFamily,
        fontSize,
        color,
        outlineSize,
        outlineColor,
        background,
        bold,
        italic,
        position,
        overrideEmbedded,
      );

  @override
  String toString() => 'SubtitleStyle(${toPersisted()})';
}

/// Font families offered in the pickers.
///
/// `Vazirmatn` is bundled with the app; the generic families resolve
/// through fontconfig against the platform's system fonts. Users can also
/// type any installed family name in the custom entry.
const List<String> kSubtitleFontChoices = <String>[
  'Vazirmatn',
  'sans-serif',
  'serif',
  'monospace',
];

/// Whether [family] is one of the bundled/preset choices (vs. custom).
bool isPresetSubtitleFont(String family) =>
    kSubtitleFontChoices.contains(family);

/// A valid custom family name: 1–48 chars, not a preset, no control chars.
bool isValidCustomFontFamily(String family) {
  if (family.isEmpty || family.length > 48) return false;
  if (isPresetSubtitleFont(family)) return false;
  return family.runes.every((r) => r >= 0x20);
}

/// Flutter [Color] → mpv color string, alpha first: `#AARRGGBB`.
String toMpvColorString(Color color) {
  String hex(double channel) =>
      (channel * 255.0).round().clamp(0, 255)
          .toRadixString(16)
          .padLeft(2, '0')
          .toUpperCase();
  return '#${hex(color.a)}${hex(color.r)}${hex(color.g)}${hex(color.b)}';
}

/// mpv color string (`#AARRGGBB` or `#RRGGBB`) → [Color]; `null` if invalid.
Color? parseMpvColorString(String? value) {
  if (value == null) return null;
  var v = value.trim();
  if (v.startsWith('#')) v = v.substring(1);
  final hex = int.tryParse(v, radix: 16);
  if (hex == null) return null;
  switch (v.length) {
    case 6:
      return Color(0xFF000000 | hex);
    case 8:
      return Color(hex);
    default:
      return null;
  }
}

String? _nonBlank(String? s) =>
    (s == null || s.trim().isEmpty) ? null : s.trim();

double _clampedDouble(String? raw, double fallback, double min, double max) {
  final v = double.tryParse(raw ?? '');
  if (v == null || v.isNaN) return fallback;
  return v.clamp(min, max).toDouble();
}
