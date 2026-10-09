/// Detail: cinematic backdrop, clear metadata hierarchy, honest actions
/// (play / resume / favorite / download), seasons with a chip selector
/// and an episode list. Partial items (favorites, continue watching) are
/// resolved back to full items via provider search.

library aftab_detail_screen;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/aftab_ffi.dart';
import '../../core/models.dart';
import '../../core/store.dart';
import '../../data/sources.dart';
import '../../design/tokens.dart';
import '../../l10n/app_localizations.dart';
import '../../navigation/app_scope.dart';
import '../../navigation/app_shell.dart';
import '../../navigation/destinations.dart';
import '../../player/player_screen.dart';
import '../../utils/format.dart';
import '../../components/aftab_image.dart';
import '../../components/media_card.dart';
import '../../components/skeletons.dart';
import '../../components/states.dart';

/// Genre deep-link signal: detail-page chips hop to Discover's genre.
final ValueNotifier<int?> discoverGenreHop = ValueNotifier<int?>(null);

class DetailScreen extends StatefulWidget {
  const DetailScreen({super.key, required this.item});

  final CatalogItem item;

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  CatalogSource? _catalog;
  CatalogItem _item = const CatalogItem(
    id: 0,
    kind: '',
    title: '',
    description: '',
    year: 0,
    imdb: 0,
    rating: 0,
    duration: null,
    image: '',
    cover: '',
    genres: <Genre>[],
    sources: <Source>[],
    countries: <Country>[],
  );

  List<Season>? _seasons;
  int _selectedSeason = 0;
  bool? _isFavorite;
  bool _downloading = false;
  bool _downloadedHere = false;
  String? _seasonError;
  WatchProgress? _progress;

  @override
  void initState() {
    super.initState();
    _item = widget.item;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = AppScope.of(context);
    _catalog ??= scope.catalog;
    if (_isFavorite == null && _seasons == null && _seasonError == null) {
      unawaited(_loadState());
    }
  }

  Future<void> _loadState() async {
    final scope = AppScope.of(context);
    // 1. Favorite flag.
    try {
      final fav = await scope.store.isFavorite(_item);
      if (mounted) setState(() => _isFavorite = fav);
    } on AftabException {
      if (mounted) setState(() => _isFavorite = false);
    }
    // 2. Watch progress (for the Resume label).
    try {
      final progress = await scope.store.progress(_item);
      if (mounted) setState(() => _progress = progress);
    } on AftabException {
      // Progress is optional display info.
    }
    // 3. Downloads: is this title already on disk?
    try {
      final record = await scope.downloads.recordFor(_item);
      if (mounted) setState(() => _downloadedHere = record != null);
    } catch (_) {
      // Best-effort.
    }
    // 4. Resolve partial items (no sources) to full items via search.
    if (_item.sources.isEmpty) {
      try {
        final full = await _catalog!.resolveItem(_item);
        if (full != null && mounted) {
          setState(() => _item = full);
        }
      } on AftabException {
        // Offline / not found: the partial item still displays.
      }
    }
    // 5. Seasons for series.
    if (_item.isSeries) {
      try {
        final seasons = await _catalog!.seasons(_item.id);
        if (!mounted) return;
        setState(() => _seasons = seasons);
      } on AftabException catch (e) {
        if (mounted) setState(() => _seasonError = e.message);
      }
    }
  }

  Future<void> _toggleFavorite() async {
    final store = AppScope.storeOf(context);
    final was = _isFavorite ?? false;
    setState(() => _isFavorite = !was); // optimistic
    try {
      if (was) {
        await store.removeFavorite(_item);
      } else {
        await store.addFavorite(_item);
      }
    } on AftabException {
      if (mounted) setState(() => _isFavorite = was); // revert
    }
  }

  Future<void> _download() async {
    if (_downloading) return;
    final s = S.of(context);
    final sorted = _item.sortedSources;
    if (sorted.isEmpty) {
      _toast(s.noPlayableSource);
      return;
    }
    setState(() => _downloading = true);
    try {
      await AppScope.downloadsOf(context).download(_item, sorted.first);
      if (!mounted) return;
      setState(() => _downloadedHere = true);
      _toast(s.downloadDone);
    } on AftabException catch (e) {
      if (mounted) _toast(s.downloadFailedWithReason(e.message));
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _playMovie() {
    final s = S.of(context);
    final sorted = _item.sortedSources;
    if (sorted.isEmpty) {
      _toast(s.noPlayableSource);
      return;
    }
    _openPlayer(
      title: _item.title,
      url: sorted.first.url,
      currentQuality: sorted.first.quality,
      onPickQuality: sorted.length > 1 ? _pickMovieQuality : null,
    );
  }

  void _playEpisode(Episode episode) {
    final s = S.of(context);
    final sorted = episode.sortedSources;
    if (sorted.isEmpty) {
      _toast(s.noEpisodeSource);
      return;
    }
    _openPlayer(
      title: '${_item.title} — ${episode.title}',
      url: sorted.first.url,
      currentQuality: sorted.first.quality,
      onPickQuality: null,
    );
  }

  void _openPlayer({
    required String title,
    required String url,
    required String currentQuality,
    Future<void> Function(BuildContext context)? onPickQuality,
  }) {
    // SSRF / scheme guard on the wire value before handing it to libmpv.
    final problem = AftabFfiSafe.urlSafetyProblem(url);
    if (problem != null) {
      final s = S.of(context);
      _toast('${s.errorDetails}: $problem');
      return;
    }
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => PlayerScreen(
          title: title,
          url: url,
          item: _item,
          currentQuality: currentQuality,
          onPickQuality: onPickQuality,
        ),
      ),
    );
  }

  /// Quality switcher for movies (series switch quality per episode).
  Future<void> _pickMovieQuality(BuildContext context) async {
    final sources = _item.sortedSources;
    if (sources.length < 2) return;
    final s = S.of(context);
    final chosen = await showModalBottomSheet<Source>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(AftabSpacing.lg),
              child: Text(s.selectQuality,
                  style: Theme.of(sheetContext).textTheme.titleMedium),
            ),
            for (final source in sources)
              ListTile(
                leading: const Icon(Icons.high_quality_outlined),
                title: Text(source.quality.isEmpty
                    ? s.qualityUnknown
                    : source.quality),
                subtitle: Text(source.type),
                onTap: () => Navigator.of(sheetContext).pop(source),
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
          title: _item.title,
          url: chosen.url,
          item: _item,
          currentQuality: chosen.quality,
          onPickQuality: _pickMovieQuality,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    final isFa = Localizations.localeOf(context).languageCode == 'fa';
    final backdrop = _item.cover.isNotEmpty ? _item.cover : _item.image;

    final resumeAt = _progress?.positionSeconds ?? 0;
    final canResume = resumeAt > 30 && (_progress?.fraction ?? 0) < 0.95;
    final playLabel = canResume
        ? s.resumeFrom(formatSeconds(resumeAt, persian: isFa))
        : s.play;

    return Scaffold(
      body: CustomScrollView(
        slivers: <Widget>[
          SliverAppBar(
            expandedHeight: 260,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  AftabImage(
                    url: backdrop,
                    fallbackIcon: Icons.movie_filter_outlined,
                  ),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: AlignmentDirectional.bottomCenter,
                        end: AlignmentDirectional.topCenter,
                        stops: <double>[0, 0.7],
                        colors: <Color>[Colors.black87, Colors.transparent],
                      ),
                    ),
                  ),
                ],
              ),
              title: Text(
                _item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.symmetric(
              horizontal: AftabSpacing.screenPadding(
                  MediaQuery.sizeOf(context).width),
              vertical: AftabSpacing.lg,
            ),
            sliver: SliverList.list(
              children: <Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AftabRadius.md),
                      child: SizedBox(
                        width: 120,
                        height: 180,
                        child: AftabImage(
                          url: _item.image,
                          fallbackIcon: _item.isSeries
                              ? Icons.tv_outlined
                              : Icons.movie_outlined,
                        ),
                      ),
                    ),
                    const SizedBox(width: AftabSpacing.lg),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            _item.title,
                            style: theme.textTheme.headlineSmall,
                          ),
                          const SizedBox(height: AftabSpacing.sm),
                          _metaLine(context, s, isFa),
                          if (_item.countries.isNotEmpty) ...<Widget>[
                            const SizedBox(height: AftabSpacing.xs),
                            Text(
                              _item.countries
                                  .map((c) => c.title)
                                  .join('، '),
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                          const SizedBox(height: AftabSpacing.md),
                          Wrap(
                            spacing: AftabSpacing.sm,
                            runSpacing: AftabSpacing.sm,
                            children: <Widget>[
                              FilledButton.icon(
                                onPressed:
                                    _item.isSeries ? null : _playMovie,
                                icon: const Icon(Icons.play_arrow),
                                label: Text(playLabel),
                              ),
                              IconButton.filledTonal(
                                tooltip: _isFavorite == true
                                    ? s.favoriteRemove
                                    : s.favoriteAdd,
                                icon: Icon(
                                  _isFavorite == true
                                      ? Icons.favorite
                                      : Icons.favorite_border,
                                ),
                                onPressed: () => unawaited(_toggleFavorite()),
                              ),
                              if (!_item.isSeries)
                                IconButton.filledTonal(
                                  tooltip: _downloadedHere
                                      ? s.downloadedBadge
                                      : s.download,
                                  icon: _downloading
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2.4),
                                        )
                                      : Icon(
                                          _downloadedHere
                                              ? Icons.offline_pin
                                              : Icons.download_outlined,
                                        ),
                                  onPressed: _downloadedHere || _downloading
                                      ? null
                                      : () => unawaited(_download()),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (_item.genreTitles.isNotEmpty) ...<Widget>[
                  const SizedBox(height: AftabSpacing.md),
                  Wrap(
                    spacing: AftabSpacing.sm,
                    runSpacing: AftabSpacing.sm,
                    children: <Widget>[
                      for (final g in _item.genres.take(6))
                        ActionChip(
                          label: Text(g.title),
                          onPressed: () =>
                              _openGenre(context, g.id),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: AftabSpacing.lg),
                Text(
                  _item.description.isEmpty ? '—' : _item.description,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: AftabSpacing.xl),
                if (_item.isSeries)
                  _buildSeasons(context, s)
                else
                  const SizedBox(height: AftabSpacing.huge),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _openGenre(BuildContext context, int genreId) {
    discoverGenreHop.value = genreId;
    Navigator.of(context).popUntil((route) => route.isFirst);
    AppShellState.instance?.goTo(AftabDestination.discover);
  }

  Widget _metaLine(BuildContext context, S s, bool isFa) {
    final parts = <String>[
      _item.isSeries ? s.seriesLabel : s.movieLabel,
      if (_item.year > 0) formatInt(_item.year, persian: isFa),
      if (_item.imdb > 0)
        s.imdbRating(formatDouble(_item.imdb, persian: isFa)),
      if (_item.duration != null && _item.duration!.isNotEmpty)
        _item.duration!,
    ];
    return Text(parts.join(' · '), style: Theme.of(context).textTheme.bodySmall);
  }

  Widget _buildSeasons(BuildContext context, S s) {
    final theme = Theme.of(context);
    if (_seasonError != null) {
      return AftabErrorPane(
        title: s.seasonsLoadFailed,
        message: _seasonError!,
        onRetry: _loadState,
      );
    }
    if (_seasons == null) {
      return const Column(
        children: <Widget>[
          SkeletonBox(height: 48),
          SizedBox(height: AftabSpacing.md),
          SkeletonBox(height: 72),
          SizedBox(height: AftabSpacing.sm),
          SkeletonBox(height: 72),
        ],
      );
    }
    if (_seasons!.isEmpty) {
      return Text(s.noSeasons, style: theme.textTheme.bodySmall);
    }
    final season = _seasons![_selectedSeason.clamp(0, _seasons!.length - 1)];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(s.seasonsTitle, style: theme.textTheme.titleLarge),
        const SizedBox(height: AftabSpacing.sm),
        Wrap(
          spacing: AftabSpacing.sm,
          runSpacing: AftabSpacing.sm,
          children: <Widget>[
            for (var i = 0; i < _seasons!.length; i++)
              ChoiceChip(
                label: Text(_seasons![i].title),
                selected: i == _selectedSeason,
                onSelected: (_) => setState(() => _selectedSeason = i),
              ),
          ],
        ),
        const SizedBox(height: AftabSpacing.md),
        Text(
          s.episodesCount(
            season.episodes.length,
            formatInt(
              season.episodes.length,
              persian: Localizations.localeOf(context).languageCode == 'fa',
            ),
          ),
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: AftabSpacing.sm),
        for (final episode in season.episodes)
          EpisodeTile(
            episode: episode,
            onTap: () => _playEpisode(episode),
          ),
        const SizedBox(height: AftabSpacing.huge),
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
