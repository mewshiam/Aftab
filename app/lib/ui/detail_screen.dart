/// Detail page: poster, metadata, favorite toggle, seasons for series,
/// and the play button (best-quality source by default, quality picker).

library aftab_detail_screen;

import 'package:flutter/material.dart';

import '../core/aftab_ffi.dart';
import '../core/catalog.dart';
import '../core/models.dart';
import '../core/store.dart';
import '../player/player_screen.dart';

class DetailScreen extends StatefulWidget {
  const DetailScreen({super.key, required this.item});

  final CatalogItem item;

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  final _catalog = CatalogClient.instance;
  final _store = AftabStore.instance;

  List<Season>? _seasons;
  bool? _isFavorite;
  String? _seasonError;

  CatalogItem get item => widget.item;

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  Future<void> _loadState() async {
    final fav = await _store.isFavorite(item);
    if (!mounted) return;
    setState(() => _isFavorite = fav);
    if (item.isSeries) {
      try {
        final seasons = await _catalog.seasons(item.id);
        if (!mounted) return;
        setState(() => _seasons = seasons);
      } on AftabException catch (e) {
        if (mounted) setState(() => _seasonError = e.message);
      }
    }
  }

  Future<void> _toggleFavorite() async {
    final was = _isFavorite ?? false;
    setState(() => _isFavorite = !was); // optimistic
    try {
      if (was) {
        await _store.removeFavorite(item);
      } else {
        await _store.addFavorite(item);
      }
    } on AftabException {
      if (mounted) setState(() => _isFavorite = was); // revert
    }
  }

  void _playMovie() {
    final sorted = item.sortedSources;
    if (sorted.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('هیچ منبع پخشی برای این عنوان موجود نیست')),
      );
      return;
    }
    final source = sorted.first;
    _openPlayer(title: item.title, url: source.url, source: source);
  }

  void _openPlayer({
    required String title,
    required String url,
    required Source source,
  }) {
    // SSRF / scheme guard on the wire value before handing it to libmpv.
    final problem = AftabFfiSafe.urlSafetyProblem(url);
    if (problem != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('نشانی پخش رد شد: $problem')),
      );
      return;
    }
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => PlayerScreen(
          title: title,
          url: url,
          item: item,
          currentQuality: source.quality,
          onPickQuality: item.isSeries ? null : _pickMovieQuality,
        ),
      ),
    );
  }

  /// Quality switcher for movies (series switch inside the episode list).
  Future<void> _pickMovieQuality(BuildContext context) async {
    final sources = item.sortedSources;
    if (sources.length < 2) return;
    final chosen = await showModalBottomSheet<Source>(
      context: context,
      builder: (_) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: <Widget>[
            const ListTile(title: Text('کیفیت را انتخاب کنید')),
            for (final s in sources)
              ListTile(
                leading: const Icon(Icons.high_quality_outlined),
                title: Text(s.quality.isEmpty ? 'نامشخص' : s.quality),
                subtitle: Text(s.type),
                onTap: () => Navigator.of(context).pop(s),
              ),
          ],
        ),
      ),
    );
    if (chosen == null) return;
    if (!context.mounted) return;
    Navigator.of(context).pushReplacement<void, void>(
      MaterialPageRoute<void>(
        builder: (_) => PlayerScreen(
          title: item.title,
          url: chosen.url,
          item: item,
          currentQuality: chosen.quality,
          onPickQuality: _pickMovieQuality,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          item.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: <Widget>[
          IconButton(
            tooltip: _isFavorite == true ? 'حذف از علاقه‌مندی‌ها' : 'افزودن به علاقه‌مندی‌ها',
            icon: Icon(
              _isFavorite == true ? Icons.favorite : Icons.favorite_border,
            ),
            onPressed: _toggleFavorite,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: item.image.isEmpty
                    ? const SizedBox(
                        width: 120, height: 180, child: ColoredBox(color: Color(0xFF1F2940)))
                    : Image.network(
                        item.image,
                        width: 120,
                        height: 180,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const SizedBox(
                          width: 120,
                          height: 180,
                          child: ColoredBox(color: Color(0xFF1F2940)),
                        ),
                      ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      item.title,
                      style: theme.textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    _metaRow(theme),
                    if (item.genreTitles.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: <Widget>[
                          for (final g in item.genres.take(4))
                            Chip(
                              label: Text(g.title),
                              visualDensity: VisualDensity.compact,
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 12),
                    if (!item.isSeries)
                      FilledButton.icon(
                        onPressed: _playMovie,
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('پخش'),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(item.description, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 24),
          if (item.isSeries) _buildSeasons(theme),
        ],
      ),
    );
  }

  Widget _metaRow(ThemeData theme) {
    final parts = <String>[
      if (item.year > 0) '${item.year}',
      if (item.imdb > 0) 'IMDb ${item.imdb.toStringAsFixed(1)}',
      if (item.rating > 0) 'امتیاز ${item.rating.toStringAsFixed(1)}',
      if (item.duration != null && item.duration!.isNotEmpty) item.duration!,
    ];
    if (parts.isEmpty) return const SizedBox.shrink();
    return Text(parts.join(' · '), style: theme.textTheme.bodySmall);
  }

  Widget _buildSeasons(ThemeData theme) {
    if (_seasonError != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('فصل‌ها', style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          Text('بارگذاری فصل‌ها ناموفق بود: $_seasonError',
              style: theme.textTheme.bodySmall),
        ],
      );
    }
    if (_seasons == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_seasons!.isEmpty) {
      return Text('فصلی برای این سریال ثبت نشده است',
          style: theme.textTheme.bodySmall);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('فصل‌ها', style: theme.textTheme.titleLarge),
        for (final season in _seasons!)
          ExpansionTile(
            title: Text(season.title),
            children: <Widget>[
              for (final episode in season.episodes)
                ListTile(
                  leading: episode.image.isEmpty
                      ? const Icon(Icons.smart_display_outlined)
                      : ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Image.network(
                            episode.image,
                            width: 96,
                            height: 54,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                const Icon(Icons.smart_display_outlined),
                          ),
                        ),
                  title: Text(episode.title),
                  subtitle: episode.duration == null
                      ? null
                      : Text(episode.duration!),
                  onTap: () {
                    final epSorted = episode.sortedSources;
                    if (epSorted.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('منبعی برای این قسمت موجود نیست')),
                      );
                      return;
                    }
                    final source = epSorted.first;
                    _openPlayer(
                      title: '${item.title} — ${episode.title}',
                      url: source.url,
                      source: source,
                    );
                  },
                ),
            ],
          ),
      ],
    );
  }
}

/// Small indirection so the detail screen test can stub the FFI library.
/// In production this is `AftabFfi.instance.urlSafetyProblem`.
abstract class AftabFfiSafe {
  static String? Function(String)? _override;

  static set override(String? Function(String)? fn) => _override = fn;

  static String? urlSafetyProblem(String url) =>
      _override?.call(url) ?? AftabFfi.instance.urlSafetyProblem(url);
}
