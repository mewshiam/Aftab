/// Model parsing + progress math (pure Dart).

library aftab_widget_test;

import 'package:flutter_test/flutter_test.dart';

import 'package:aftab_media/core/models.dart';
import 'package:aftab_media/core/store.dart';
import 'package:aftab_media/data/sources.dart';

void main() {
  group('CatalogItem parsing', () {
    test('parses a full movie payload', () {
      final item = CatalogItem.fromJson(<String, dynamic>{
        'id': 12,
        'type': 'movie',
        'title': 'گوشه',
        'description': 'یک فیلم',
        'year': 2023,
        'imdb': 7.4,
        'rating': 8.1,
        'duration': '1h 52m',
        'image': 'https://img.example/p.jpg',
        'cover': 'https://img.example/c.jpg',
        'genres': <dynamic>[
          <String, dynamic>{'id': 1, 'title': 'اکشن'},
        ],
        'sources': <dynamic>[
          <String, dynamic>{
            'id': 9,
            'quality': '1080p',
            'type': 'mp4',
            'url': 'https://cdn.example/v.mp4',
          },
        ],
        'country': <dynamic>[],
      });
      expect(item.id, 12);
      expect(item.title, 'گوشه');
      expect(item.isSeries, isFalse);
      expect(item.genres, hasLength(1));
      expect(item.sortedSources.first.qualityRank, 1080);
    });

    test('series kind is recognized and sources sort by quality', () {
      final item = CatalogItem.fromJson(<String, dynamic>{
        'id': 3,
        'type': 'serie',
        'title': 'سرزمین',
        'sources': <dynamic>[
          <String, dynamic>{
            'id': 2,
            'quality': '720',
            'type': 'mkv',
            'url': 'u2',
          },
          <String, dynamic>{
            'id': 1,
            'quality': '1080',
            'type': 'mp4',
            'url': 'u1',
          },
        ],
      });
      expect(item.isSeries, isTrue);
      expect(item.sortedSources.first.url, 'u1');
    });

    test('missing fields degrade to defaults, not crashes', () {
      final item = CatalogItem.fromJson(<String, dynamic>{'id': 1});
      expect(item.title, '');
      expect(item.year, 0);
      expect(item.duration, isNull);
      expect(item.genreTitles, '');
    });

    test('WatchEntry parses the progress_all JSON shape', () {
      const entry = WatchEntry(
        kind: 'movie',
        id: 5,
        progress: WatchProgress(
          positionSeconds: 300,
          durationSeconds: 600,
          updatedAt: 1,
        ),
      );
      expect(entry.progress.fraction, closeTo(0.5, 1e-9));
    });
  });

  group('WatchProgress fraction (pure Dart mirror of the core test)', () {
    test('half-watched', () {
      final p = WatchProgress.fromJson(<String, dynamic>{
        'position': 540.0,
        'duration': 1080.0,
        'updated_at': 1,
      });
      expect(p.fraction, closeTo(0.5, 1e-9));
    });

    test('unknown duration is zero, overflow is clamped', () {
      expect(
        WatchProgress.fromJson(<String, dynamic>{
          'position': 10,
          'duration': 0,
          'updated_at': 1,
        }).fraction,
        0,
      );
      expect(
        WatchProgress.fromJson(<String, dynamic>{
          'position': 200,
          'duration': 100,
          'updated_at': 1,
        }).fraction,
        1,
      );
    });
  });
}
