/// Data-layer logic: watch index codec, download record codec, and the
/// settings controller round-trip.

library aftab_data_test;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aftab_media/data/app_settings.dart';
import 'package:aftab_media/data/downloads.dart';
import 'package:aftab_media/data/watch_index.dart';

import 'fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WatchIndex codec', () {
    test('round-trips entries', () async {
      final store = FakeStoreSource();
      final index = WatchIndex(store: store);
      final item = fakeItem(id: 7, kind: 'serie', title: 'سرزمین');
      await index.record(item);
      final entries = await index.entries();
      expect(entries, hasLength(1));
      expect(entries.first.title, 'سرزمین');
      expect(entries.first.kind, 'serie');
      expect(entries.first.id, 7);
      final again = await index.entry('serie', 7);
      expect(again?.title, 'سرزمین');
    });

    test('corrupt JSON degrades to empty', () {
      expect(decodeWatchIndex('not json'), isEmpty);
      expect(decodeWatchIndex(null), isEmpty);
      expect(decodeWatchIndex('[]'), isEmpty);
    });

    test('record refreshes, not duplicates', () async {
      final store = FakeStoreSource();
      final index = WatchIndex(store: store);
      await index.record(fakeItem(id: 1, title: 'a'));
      await index.record(fakeItem(id: 1, title: 'b'));
      final entries = await index.entries();
      expect(entries, hasLength(1));
      expect(entries.first.title, 'b');
    });
  });

  group('DownloadRecord codec', () {
    test('decode tolerates garbage', () {
      expect(decodeDownloads(null), isEmpty);
      expect(decodeDownloads('nope'), isEmpty);
      expect(decodeDownloads('[]'), isEmpty);
    });

    test('encode shape matches the record fields', () {
      const record = DownloadRecord(
        kind: 'movie',
        id: 5,
        title: 'گوشه',
        image: '',
        path: '/tmp/x.mp4',
        bytes: 42,
        addedAt: 9,
      );
      final encoded = encodeDownloads(<DownloadRecord>[record]);
      expect(encoded, contains('"title":"گوشه"'));
      expect(encoded, contains('"bytes":42'));
    });
  });

  group('SettingsController', () {
    test('defaults are Persian-first and dark', () async {
      final controller = SettingsController(store: FakeStoreSource());
      await controller.load();
      expect(controller.locale, AppLocale.fa);
      expect(controller.themeMode, ThemeMode.dark);
      expect(controller.autoResume, isTrue);
      expect(controller.tvMode, isFalse);
      expect(controller.materialLocale, const Locale('fa'));
    });

    test('changes persist through the store', () async {
      final store = FakeStoreSource();
      final controller = SettingsController(store: store);
      await controller.load();
      await controller.setLocale(AppLocale.en);
      await controller.setThemeMode(ThemeMode.light);
      await controller.setAutoResume(false);
      await controller.setTvMode(true);

      final reloaded = SettingsController(store: store);
      await reloaded.load();
      expect(reloaded.locale, AppLocale.en);
      expect(reloaded.themeMode, ThemeMode.light);
      expect(reloaded.autoResume, isFalse);
      expect(reloaded.tvMode, isTrue);
    });

    test('system theme mode round-trips', () async {
      final store = FakeStoreSource();
      final controller = SettingsController(store: store);
      await controller.load();
      await controller.setThemeMode(ThemeMode.system);
      final reloaded = SettingsController(store: store);
      await reloaded.load();
      expect(reloaded.themeMode, ThemeMode.system);
    });
  });
}
