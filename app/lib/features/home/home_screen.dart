/// Home: the discovery dashboard — greeting, continue watching,
/// featured strip and curated rails. All data comes from the existing
/// provider endpoints; every rail degrades independently.

library aftab_home_screen;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/aftab_ffi.dart';
import '../../core/models.dart';
import '../../data/sources.dart';
import '../../data/watch_index.dart';
import '../../design/tokens.dart';
import '../../l10n/app_localizations.dart';
import '../../navigation/app_shell.dart';
import '../../navigation/app_scope.dart';
import '../../utils/format.dart';
import '../../components/hero_banner.dart';
import '../../components/media_card.dart';
import '../../components/media_rail.dart';
import '../../components/skeletons.dart';
import '../../components/states.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  CatalogSource? _catalog;
  bool _kickstarted = false;

  List<CatalogItem> _topMovies = const <CatalogItem>[];
  List<CatalogItem> _topSeries = const <CatalogItem>[];
  List<CatalogItem> _newMovies = const <CatalogItem>[];
  List<_ContinueItem> _continueItems = const <_ContinueItem>[];
  bool _loading = true;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _catalog ??= AppScope.catalogOf(context);
    if (!_kickstarted) {
      _kickstarted = true;
      unawaited(_load());
    }
  }

  /// Wraps a future so a failed rail never breaks the whole screen.
  Future<Object> _guard<T>(Future<T> future) async {
    try {
      return await future as Object;
    } on AftabException catch (e) {
      return e;
    } catch (e) {
      return AftabException(aftabUnknown, e.toString());
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final catalog = _catalog!;
    final scope = AppScope.of(context);
    final results = await Future.wait(<Future<Object>>[
      _guard(catalog.movies(sort: CatalogSort.byImdb, page: 0)),
      _guard(catalog.series(sort: CatalogSort.byImdb, page: 0)),
      _guard(catalog.movies(sort: CatalogSort.newest, page: 0)),
      _guard(_loadContinue(scope)),
    ]);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _topMovies = _asItems(results[0]).take(12).toList(growable: false);
      _topSeries = _asItems(results[1]).take(12).toList(growable: false);
      _newMovies = _asItems(results[2]).take(12).toList(growable: false);
      _continueItems = results[3] is List<_ContinueItem>
          ? results[3] as List<_ContinueItem>
          : const <_ContinueItem>[];
      if (_topMovies.isEmpty && _topSeries.isEmpty && _newMovies.isEmpty) {
        AftabException? failure;
        for (final r in results) {
          if (r is AftabException) {
            failure = r;
            break;
          }
        }
        _error = failure?.message;
      }
    });
  }

  List<CatalogItem> _asItems(Object result) =>
      result is List<CatalogItem> ? result : const <CatalogItem>[];

  /// Continue watching = progress (past 30s, under 95%) joined with the
  /// display index so rows have a title and artwork.
  Future<List<_ContinueItem>> _loadContinue(AppScope scope) async {
    final entries = await scope.store.progressAll();
    final byKey = <String, WatchIndexEntry>{
      for (final e in await scope.watchIndex.entries()) e.key: e,
    };
    final out = <_ContinueItem>[];
    for (final entry in entries) {
      if (entry.progress.positionSeconds <= 30) continue;
      if (entry.progress.fraction >= 0.95) continue;
      final meta = byKey['${entry.kind}:${entry.id}'];
      if (meta == null) continue;
      out.add(_ContinueItem(entry, meta.title, meta.image));
    }
    return out.take(10).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    final width = MediaQuery.sizeOf(context).width;

    if (_error != null &&
        _topMovies.isEmpty &&
        _topSeries.isEmpty &&
        _newMovies.isEmpty) {
      return Scaffold(body: AftabErrorPane(message: _error!, onRetry: _load));
    }

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.only(bottom: AftabSpacing.huge),
          children: <Widget>[
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: AftabSpacing.screenPadding(width),
                vertical: AftabSpacing.md,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    _greeting(s),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Text(s.appName, style: theme.textTheme.headlineMedium),
                ],
              ),
            ),
            const SizedBox(height: AftabSpacing.md),
            if (_loading) ...<Widget>[
              const SkeletonRail(),
              const SizedBox(height: AftabSpacing.lg),
              const SkeletonRail(),
            ] else ...<Widget>[
              if (_continueItems.isNotEmpty)
                _ContinueRail(items: _continueItems),
              if (_topMovies.isNotEmpty &&
                  (_topMovies.first.cover.isNotEmpty ||
                      _topMovies.first.image.isNotEmpty)) ...<Widget>[
                HeroBanner(
                  item: _topMovies.first,
                  onOpen: () => openDetail(context, _topMovies.first),
                ),
                const SizedBox(height: AftabSpacing.lg),
              ],
              _rail(context, s.topMovies, _topMovies),
              _rail(context, s.topSeries, _topSeries),
              _rail(context, s.newMovies, _newMovies),
            ],
          ],
        ),
      ),
    );
  }

  Widget _rail(BuildContext context, String title, List<CatalogItem> items) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: AftabSpacing.lg),
      child: MediaRail(
        title: title,
        items: items,
        onOpenItem: (item) => openDetail(context, item),
      ),
    );
  }

  String _greeting(S s) {
    final hour = DateTime.now().hour;
    if (hour < 5) return s.greetingNight;
    if (hour < 12) return s.greetingMorning;
    if (hour < 17) return s.greetingAfternoon;
    if (hour < 21) return s.greetingEvening;
    return s.greetingNight;
  }
}

class _ContinueItem {
  const _ContinueItem(this.entry, this.title, this.image);

  final WatchEntry entry;
  final String title;
  final String image;

  CatalogItem get asCatalogItem => CatalogItem(
        id: entry.id,
        kind: entry.kind,
        title: title,
        description: '',
        year: 0,
        imdb: 0,
        rating: 0,
        duration: null,
        image: image,
        cover: '',
        genres: const <Genre>[],
        sources: const <Source>[],
        countries: const <Country>[],
      );
}

/// Continue-watching rail: wide cards with progress and "minutes left".
class _ContinueRail extends StatelessWidget {
  const _ContinueRail({required this.items});

  final List<_ContinueItem> items;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final cardWidth = railCardWidth(width).clamp(170.0, 280.0).toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: AftabSpacing.railPadding(width),
            vertical: AftabSpacing.sm,
          ),
          child: Text(s.continueWatching,
              style: Theme.of(context).textTheme.titleLarge),
        ),
        SizedBox(
          height: 170,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(
              horizontal: AftabSpacing.railPadding(width),
            ),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: AftabSpacing.sm),
            itemBuilder: (context, i) {
              final item = items[i];
              final minutes = minutesRemaining(
                item.entry.progress.positionSeconds,
                item.entry.progress.durationSeconds,
              );
              final isFa =
                  Localizations.localeOf(context).languageCode == 'fa';
              return SizedBox(
                width: cardWidth,
                child: WideCard(
                  image: item.image,
                  title: item.title,
                  subtitle: minutes > 0
                      ? s.minutesLeft(formatInt(minutes, persian: isFa))
                      : '',
                  progressFraction: item.entry.progress.fraction,
                  onTap: () => openDetail(context, item.asCatalogItem),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: AftabSpacing.lg),
      ],
    );
  }
}
