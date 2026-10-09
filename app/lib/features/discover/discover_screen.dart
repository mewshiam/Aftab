/// Discover: browse movies and series with genre/type filters, sort and
/// infinite pagination. On wide layouts the filters become a persistent
/// side panel (two-pane) instead of stacked chips.

library aftab_discover_screen;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/aftab_ffi.dart';
import '../../core/models.dart';
import '../../data/sources.dart';
import '../../design/tokens.dart';
import '../../l10n/app_localizations.dart';
import '../../navigation/app_scope.dart';
import '../../navigation/app_shell.dart';
import '../../components/media_card.dart';
import '../../components/skeletons.dart';
import '../../components/states.dart';
import '../../features/details/detail_screen.dart' show discoverGenreHop;

enum _TypeFilter { movies, series }

class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key, this.initialGenre});

  /// Pre-selected genre (deep link from a genre chip elsewhere).
  final int? initialGenre;

  @override
  State<DiscoverScreen> createState() => DiscoverScreenState();
}

/// Public state so other sections can deep-link into a genre.
class DiscoverScreenState extends State<DiscoverScreen> {
  CatalogSource? _catalog;

  final List<Genre> _genres = <Genre>[];
  final List<CatalogItem> _items = <CatalogItem>[];
  final ScrollController _scroll = ScrollController();

  int _selectedGenre = 0;
  _TypeFilter _type = _TypeFilter.movies;
  CatalogSort _sort = CatalogSort.newest;
  int _page = 0;
  bool _loading = false;
  bool _exhausted = false;
  bool _genresLoading = true;
  String? _error;
  String? _moreError;

  @override
  void initState() {
    super.initState();
    _selectedGenre = widget.initialGenre ?? 0;
    _scroll.addListener(_onScroll);
    discoverGenreHop.addListener(_onGenreHop);
  }

  void _onGenreHop() {
    final genre = discoverGenreHop.value;
    if (genre == null) return;
    discoverGenreHop.value = null;
    openGenre(genre);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _catalog ??= AppScope.catalogOf(context);
    if (_genresLoading && _genres.isEmpty && _items.isEmpty) {
      unawaited(_reload());
      unawaited(_loadGenres());
    }
  }

  /// Deep-links the Discover tab to [genreId].
  void openGenre(int genreId) {
    if (genreId == _selectedGenre) return;
    _selectedGenre = genreId;
    unawaited(_reload());
  }

  @override
  void dispose() {
    discoverGenreHop.removeListener(_onGenreHop);
    _scroll
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    if (_scroll.position.extentAfter < 600) unawaited(_loadMore());
  }

  Future<void> _loadGenres() async {
    try {
      final genres = await _catalog!.genres();
      if (!mounted) return;
      setState(() {
        _genres
          ..clear()
          ..addAll(genres);
        _genresLoading = false;
      });
    } on AftabException catch (e) {
      if (mounted) {
        setState(() {
          _genresLoading = false;
          if (_items.isEmpty) _error = e.message;
        });
      }
    }
  }

  Future<List<CatalogItem>> _fetch(int page) {
    if (_type == _TypeFilter.series) {
      return _catalog!.series(genre: _selectedGenre, sort: _sort, page: page);
    }
    return _catalog!.movies(genre: _selectedGenre, sort: _sort, page: page);
  }

  Future<void> _reload() async {
    setState(() {
      _items.clear();
      _page = 0;
      _exhausted = false;
      _error = null;
      _moreError = null;
      _loading = true;
    });
    try {
      final page = await _fetch(0);
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(page);
        _exhausted = page.isEmpty;
        _page = 1;
      });
    } on AftabException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _exhausted) return;
    setState(() => _loading = true);
    try {
      final page = await _fetch(_page);
      if (!mounted) return;
      setState(() {
        _items.addAll(page);
        _page += 1;
        if (page.isEmpty) _exhausted = true;
        _moreError = null;
      });
    } on AftabException catch (e) {
      if (mounted) setState(() => _moreError = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final twoPane = width >= 900;

    final content = twoPane
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SizedBox(
                width: 260,
                child: _FiltersPanel(
                  genres: _genres,
                  genresLoading: _genresLoading,
                  selectedGenre: _selectedGenre,
                  type: _type,
                  sort: _sort,
                  onGenre: (g) {
                    setState(() => _selectedGenre = g);
                    unawaited(_reload());
                  },
                  onType: (t) {
                    setState(() => _type = t);
                    unawaited(_reload());
                  },
                  onSort: (v) {
                    setState(() => _sort = v);
                    unawaited(_reload());
                  },
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(child: _gridBody(context, s)),
            ],
          )
        : Column(
            children: <Widget>[
              _filterChips(context, s),
              Expanded(child: _gridBody(context, s)),
            ],
          );

    return Scaffold(
      appBar: AppBar(
        title: Text(s.discoverTitle),
      ),
      body: content,
    );
  }

  Widget _filterChips(BuildContext context, S s) {
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AftabSpacing.lg,
            vertical: AftabSpacing.sm,
          ),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: SegmentedButton<_TypeFilter>(
              segments: <ButtonSegment<_TypeFilter>>[
                ButtonSegment<_TypeFilter>(
                  value: _TypeFilter.movies,
                  label: Text(s.filterMovies),
                  icon: const Icon(Icons.movie_outlined),
                ),
                ButtonSegment<_TypeFilter>(
                  value: _TypeFilter.series,
                  label: Text(s.filterSeries),
                  icon: const Icon(Icons.tv_outlined),
                ),
              ],
              selected: <_TypeFilter>{_type},
              onSelectionChanged: (selection) {
                setState(() => _type = selection.first);
                unawaited(_reload());
              },
            ),
          ),
        ),
        if (_genresLoading)
          const Padding(
            padding: EdgeInsets.all(AftabSpacing.md),
            child: SizedBox(
              height: 30,
              child: SkeletonBox(height: 30),
            ),
          )
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
              horizontal: AftabSpacing.lg,
              vertical: AftabSpacing.sm,
            ),
            child: Row(
              children: <Widget>[
                _genreChip(context, s.filterGenre, 0),
                for (final g in _genres)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(
                        start: AftabSpacing.sm),
                    child: _genreChip(context, g.title, g.id),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _genreChip(BuildContext context, String label, int id) {
    return ChoiceChip(
      label: Text(label),
      selected: _selectedGenre == id,
      onSelected: (_) {
        setState(() => _selectedGenre = id);
        unawaited(_reload());
      },
    );
  }

  Widget _gridBody(BuildContext context, S s) {
    if (_error != null && _items.isEmpty) {
      return AftabErrorPane(
        message: _error!,
        onRetry: () async {
          unawaited(_reload());
          unawaited(_loadGenres());
        },
      );
    }
    if (_items.isEmpty && _loading) {
      return const AftabLoadingGrid();
    }
    if (_items.isEmpty) {
      return AftabEmptyPane(
        title: s.noContent,
        icon: Icons.movie_filter_outlined,
      );
    }
    final width = MediaQuery.sizeOf(context).width;
    return Column(
      children: <Widget>[
        Expanded(
          child: RefreshIndicator(
            onRefresh: _reload,
            child: GridView.builder(
              controller: _scroll,
              padding: EdgeInsets.symmetric(
                horizontal: AftabSpacing.screenPadding(width),
                vertical: AftabSpacing.md,
              ),
              gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: width >= AftabBreakpoints.medium ? 190 : 160,
                childAspectRatio: 0.62,
                mainAxisSpacing: AftabSpacing.md,
                crossAxisSpacing: AftabSpacing.md,
              ),
              itemCount: _items.length + (_loading ? 1 : 0),
              itemBuilder: (context, i) {
                if (i >= _items.length) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(AftabSpacing.lg),
                      child: CircularProgressIndicator(),
                    ),
                  );
                }
                return PosterCard(
                  item: _items[i],
                  onTap: () => openDetail(context, _items[i]),
                );
              },
            ),
          ),
        ),
        if (_moreError != null)
          AftabInlineError(
            message: _moreError!,
            onRetry: _loadMore,
          ),
      ],
    );
  }
}

/// Persistent filters for the two-pane layout.
class _FiltersPanel extends StatelessWidget {
  const _FiltersPanel({
    required this.genres,
    required this.genresLoading,
    required this.selectedGenre,
    required this.type,
    required this.sort,
    required this.onGenre,
    required this.onType,
    required this.onSort,
  });

  final List<Genre> genres;
  final bool genresLoading;
  final int selectedGenre;
  final _TypeFilter type;
  final CatalogSort sort;
  final ValueChanged<int> onGenre;
  final ValueChanged<_TypeFilter> onType;
  final ValueChanged<CatalogSort> onSort;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(AftabSpacing.lg),
      children: <Widget>[
        Text(s.navDiscover, style: theme.textTheme.titleLarge),
        const SizedBox(height: AftabSpacing.lg),
        SegmentedButton<_TypeFilter>(
          segments: <ButtonSegment<_TypeFilter>>[
            ButtonSegment<_TypeFilter>(
              value: _TypeFilter.movies,
              label: Text(s.filterMovies),
              icon: const Icon(Icons.movie_outlined),
            ),
            ButtonSegment<_TypeFilter>(
              value: _TypeFilter.series,
              label: Text(s.filterSeries),
              icon: const Icon(Icons.tv_outlined),
            ),
          ],
          selected: <_TypeFilter>{type},
          onSelectionChanged: (selection) => onType(selection.first),
        ),
        const Divider(),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AftabSpacing.sm),
          child: Text(s.sortBy, style: theme.textTheme.titleSmall),
        ),
        PopupMenuButton<CatalogSort>(
          initialValue: sort,
          onSelected: onSort,
          itemBuilder: (_) => <PopupMenuEntry<CatalogSort>>[
            _sortEntry(context, CatalogSort.newest, s.sortNewest),
            _sortEntry(context, CatalogSort.byYear, s.sortYear),
            _sortEntry(context, CatalogSort.byImdb, s.sortImdb),
          ],
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AftabSpacing.sm),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(Icons.sort),
                const SizedBox(width: AftabSpacing.sm),
                Text(_sortLabel(s)),
              ],
            ),
          ),
        ),
        const Divider(),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AftabSpacing.sm),
          child: Text(s.browseByGenre, style: theme.textTheme.titleSmall),
        ),
        if (genresLoading)
          const Center(child: CircularProgressIndicator(strokeWidth: 2))
        else
          Wrap(
            spacing: AftabSpacing.sm,
            runSpacing: AftabSpacing.sm,
            children: <Widget>[
              ChoiceChip(
                label: Text(s.filterGenre),
                selected: selectedGenre == 0,
                onSelected: (_) => onGenre(0),
              ),
              for (final g in genres)
                ChoiceChip(
                  label: Text(g.title),
                  selected: selectedGenre == g.id,
                  onSelected: (_) => onGenre(g.id),
                ),
            ],
          ),
      ],
    );
  }

  String _sortLabel(S s) => switch (sort) {
        CatalogSort.newest => s.sortNewest,
        CatalogSort.byYear => s.sortYear,
        CatalogSort.byImdb => s.sortImdb,
      };

  PopupMenuItem<CatalogSort> _sortEntry(
      BuildContext context, CatalogSort value, String label) {
    return PopupMenuItem<CatalogSort>(value: value, child: Text(label));
  }
}