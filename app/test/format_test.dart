/// Locale-aware formatting: Persian digits for fa, Latin for en, shared
/// duration / bytes helpers.

library aftab_format_test;

import 'package:flutter_test/flutter_test.dart';

import 'package:aftab_media/utils/format.dart';

void main() {
  group('formatInt', () {
    test('Persian digits under fa', () {
      expect(formatInt(2023, persian: true), '۲۰۲۳');
    });

    test('Latin digits under en', () {
      expect(formatInt(2023, persian: false), '2023');
    });
  });

  group('formatDouble', () {
    test('one decimal, locale digits, Persian decimal mark', () {
      // 7.36 avoids the 7.35 → 7.3 IEEE-754 rounding trap.
      expect(formatDouble(7.36, persian: true), '۷٫۴');
      expect(formatDouble(7.36, persian: false), '7.4');
    });
  });

  group('formatDuration', () {
    test('minutes and seconds under a minute', () {
      expect(formatDuration(const Duration(seconds: 5), persian: false), '00:05');
    });

    test('hours format', () {
      expect(
        formatDuration(const Duration(hours: 1, minutes: 2, seconds: 3),
            persian: false),
        '1:02:03',
      );
    });

    test('Persian digits', () {
      expect(
        formatDuration(const Duration(minutes: 12, seconds: 34),
            persian: true),
        '۱۲:۳۴',
      );
    });
  });

  group('minutesRemaining', () {
    test('rounds up and clamps', () {
      expect(minutesRemaining(0, 60), 1);
      expect(minutesRemaining(30, 60), 1);
      expect(minutesRemaining(59.9, 60), 1);
      expect(minutesRemaining(60, 60), 0);
      expect(minutesRemaining(10, 0), 0); // unknown duration
    });
  });

  group('formatBytes', () {
    test('bounds and units', () {
      expect(formatBytes(512, persian: false), '512');
      expect(formatBytes(2 * 1024, persian: false), '2.0 KB');
      expect(formatBytes(3 * 1024 * 1024, persian: false), '3.0 MB');
      expect(formatBytes(1024 * 1024 * 1024, persian: false), '1.0 GB');
    });

    test('Persian digits', () {
      expect(formatBytes(1024, persian: true), '۱٫۰ KB');
    });
  });
}
