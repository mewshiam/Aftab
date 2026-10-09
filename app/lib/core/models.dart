/// Typed mirrors of the core's JSON shapes (see `core/src/model.rs` and
/// `docs/PROVIDER-API.md`). Every field is nullable-safe: the core already
/// defaulted missing fields before serializing, but these parsers stay
/// defensive because catalog data is untrusted input.

class Source {
  const Source({
    required this.id,
    required this.quality,
    required this.type,
    required this.url,
  });

  final int id;
  final String quality;
  final String type;
  final String url;

  factory Source.fromJson(Map<String, dynamic> json) => Source(
        id: (json['id'] as num?)?.toInt() ?? 0,
        quality: json['quality'] as String? ?? '',
        type: json['type'] as String? ?? '',
        url: json['url'] as String? ?? '',
      );

  int get qualityRank {
    final digits = quality.replaceAll(RegExp(r'[^0-9]'), '');
    return int.tryParse(digits) ?? 0;
  }
}

class Genre {
  const Genre({required this.id, required this.title});

  final int id;
  final String title;

  factory Genre.fromJson(Map<String, dynamic> json) => Genre(
        id: (json['id'] as num?)?.toInt() ?? 0,
        title: json['title'] as String? ?? '',
      );
}

class Country {
  const Country({required this.id, required this.title, required this.image});

  final int id;
  final String title;
  final String image;

  factory Country.fromJson(Map<String, dynamic> json) => Country(
        id: (json['id'] as num?)?.toInt() ?? 0,
        title: json['title'] as String? ?? '',
        image: json['image'] as String? ?? '',
      );
}

/// A catalog card: movie, series, or search result.
class CatalogItem {
  const CatalogItem({
    required this.id,
    required this.kind,
    required this.title,
    required this.description,
    required this.year,
    required this.imdb,
    required this.rating,
    required this.duration,
    required this.image,
    required this.cover,
    required this.genres,
    required this.sources,
    required this.countries,
  });

  /// `"movie"` or `"serie"` — the store keys favorites by this.
  final String kind;
  final int id;
  final String title;
  final String description;
  final int year;
  final double imdb;
  final double rating;
  final String? duration;
  final String image;
  final String cover;
  final List<Genre> genres;
  final List<Source> sources;
  final List<Country> countries;

  bool get isSeries => kind == 'serie';

  /// Sources sorted best-quality first.
  List<Source> get sortedSources {
    final list = [...sources]..sort((a, b) => b.qualityRank.compareTo(a.qualityRank));
    return list;
  }

  String get genreTitles => genres.map((g) => g.title).join('، ');

  factory CatalogItem.fromJson(Map<String, dynamic> json) => CatalogItem(
        id: (json['id'] as num?)?.toInt() ?? 0,
        kind: json['type'] as String? ?? '',
        title: json['title'] as String? ?? '',
        description: json['description'] as String? ?? '',
        year: (json['year'] as num?)?.toInt() ?? 0,
        imdb: (json['imdb'] as num?)?.toDouble() ?? 0,
        rating: (json['rating'] as num?)?.toDouble() ?? 0,
        duration: json['duration'] as String?,
        image: json['image'] as String? ?? '',
        cover: json['cover'] as String? ?? '',
        genres: (json['genres'] as List<dynamic>? ?? [])
            .map((g) => Genre.fromJson(g as Map<String, dynamic>))
            .toList(),
        sources: (json['sources'] as List<dynamic>? ?? [])
            .map((s) => Source.fromJson(s as Map<String, dynamic>))
            .toList(),
        countries: (json['country'] as List<dynamic>? ?? [])
            .map((c) => Country.fromJson(c as Map<String, dynamic>))
            .toList(),
      );
}

class Episode {
  const Episode({
    required this.id,
    required this.title,
    required this.description,
    required this.duration,
    required this.image,
    required this.sources,
  });

  final int id;
  final String title;
  final String description;
  final String? duration;
  final String image;
  final List<Source> sources;

  List<Source> get sortedSources {
    final list = [...sources]..sort((a, b) => b.qualityRank.compareTo(a.qualityRank));
    return list;
  }

  factory Episode.fromJson(Map<String, dynamic> json) => Episode(
        id: (json['id'] as num?)?.toInt() ?? 0,
        title: json['title'] as String? ?? '',
        description: json['description'] as String? ?? '',
        duration: json['duration'] as String?,
        image: json['image'] as String? ?? '',
        sources: (json['sources'] as List<dynamic>? ?? [])
            .map((s) => Source.fromJson(s as Map<String, dynamic>))
            .toList(),
      );
}

class Season {
  const Season({
    required this.id,
    required this.title,
    required this.episodes,
  });

  final int id;
  final String title;
  final List<Episode> episodes;

  factory Season.fromJson(Map<String, dynamic> json) => Season(
        id: (json['id'] as num?)?.toInt() ?? 0,
        title: json['title'] as String? ?? '',
        episodes: (json['episodes'] as List<dynamic>? ?? [])
            .map((e) => Episode.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// Sort orders matching the core's `FilterType`.
enum CatalogSort {
  newest(0, 'جدیدترین'),
  byYear(1, 'بالاترین سال'),
  byImdb(2, 'بهترین ایمدی‌بی');

  const CatalogSort(this.wireValue, this.persianLabel);

  final int wireValue;
  final String persianLabel;
}
