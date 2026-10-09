/// Locale-aware formatting: Persian digits for `fa`, Latin for `en`,
/// shared duration and byte-size helpers.
///
/// Persian-first means numbers inside a Persian UI should read as Persian
/// digits (۰۱۲۳۴۵۶۷۸۹) — but an English UI must never show them. All
/// numeric display goes through these functions instead of raw
/// interpolation.

library aftab_format;

/// Digits for the current locale: `true` → Persian digits.
String formatInt(int value, {bool persian = true}) {
  final s = value.toString();
  return persian ? _toPersianDigits(s) : s;
}

/// One decimal, locale digits (ratings).
String formatDouble(double value, {bool persian = true}) {
  final s = value.toStringAsFixed(1);
  return persian ? _toPersianDigits(s) : s;
}

/// `mm:ss` / `h:mm:ss` playback time.
String formatDuration(Duration d, {bool persian = true}) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  final raw = h > 0 ? '$h:$m:$s' : '$m:$s';
  return persian ? _toPersianDigits(raw) : raw;
}

/// Seconds → short clock (e.g. 1:23:45).
String formatSeconds(double seconds, {bool persian = true}) =>
    formatDuration(Duration(milliseconds: (seconds * 1000).round()),
        persian: persian);

/// Minutes remaining, rounded up.
int minutesRemaining(double positionSeconds, double durationSeconds) {
  if (durationSeconds <= 0) return 0;
  final left = (durationSeconds - positionSeconds) / 60;
  if (left <= 0) return 0;
  return left.ceil();
}

/// Human byte size: KB / MB / GB with locale digits.
String formatBytes(int bytes, {bool persian = true}) {
  const unit = 1024;
  if (bytes < unit) return formatInt(bytes, persian: persian);
  final mb = bytes / (unit * unit);
  if (mb < 1) return '${formatDouble(bytes / unit, persian: persian)} KB';
  final gb = mb / unit;
  if (gb >= 1) return '${formatDouble(gb, persian: persian)} GB';
  return '${formatDouble(mb, persian: persian)} MB';
}

const _latin = '0123456789.';
const _persian = '۰۱۲۳۴۵۶۷۸۹٫';

String _toPersianDigits(String input) {
  final out = StringBuffer();
  for (final ch in input.runes) {
    final i = _latin.indexOf(String.fromCharCode(ch));
    out.write(i >= 0 ? _persian[i] : String.fromCharCode(ch));
  }
  return out.toString();
}
