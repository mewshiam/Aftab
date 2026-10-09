/// The Android TV shell: a genuine 10-foot interface.
///
/// Big typography (1.12× text scale), a D-pad-navigable top navigation
/// row, horizontal content rails with unmistakable focus (scale + border
/// + glow), and a slim remote-friendly refresh shortcut.

library aftab_tv_shell;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/aftab_ffi.dart';
import '../core/models.dart';
import '../data/sources.dart';
import '../data/watch_index.dart';
import '../design/tokens.dart';
import '../l10n/app_localizations.dart';
import '../navigation/app_scope.dart';
import '../navigation/app_shell.dart' show openDetail;
import '../navigation/destinations.dart';
import '../utils/format.dart';
import '../components/hero_banner.dart';
import '../components/media_card.dart';
import '../components/media_rail.dart';
import '../components/skeletons.dart';
import '../components/states.dart';
import '../components/tv_focus.dart';
import '../features/library/library_screen.dart';
import '../features/search/search_screen.dart';
import '../features/settings/settings_screen.dart';

class TvShell extends StatefulWidget {
  const TvShell({super.key});

  @override
  State<TvShell> createState() => _TvShellState();
}

class _TvShellState extends State<TvShell> {
  int _index = 0;
  int _generation = 0;

  void _goTo(AftabDestination destination) =>
      setState(() => _index = destination.index);

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    final mq = MediaQuery.of(context);

    final screens = <Widget>[
      const _TvHome(),
      const SearchScreen(),
      const LibraryScreen(),
      const SettingsScreen(),
    ];

    return MediaQuery(
      data: mq.copyWith(
        textScaler: const TextScaler.linear(1.12),
      ),
      child: Scaffold(
        body: Focus(
          autofocus: true,
          onKeyEvent: (node, event) {
            // Color buttons on many remotes refresh; harmless elsewhere.
            if (event is KeyDownEvent &&
                event.logicalKey == LogicalKeyboardKey.keyR) {
              // Remount the visible tab so its data loaders re-run.
              setState(() => _generation += 1);
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AftabSpacing.xxl,
                    vertical: AftabSpacing.lg,
                  ),
                  child: Row(
                    children: <Widget>[
                      Icon(
                        Icons.wb_sunny,
                        color: theme.colorScheme.primary,
                        size: 28,
                      ),
                      const SizedBox(width: AftabSpacing.md),
                      Text(
                        s.appName,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: AftabSpacing.xxl),
                      Expanded(
                        child: Row(
                          children: <Widget>[
                            for (final d in AftabDestination.values)
                              Padding(
                                padding: const EdgeInsetsDirectional.only(
                                    end: AftabSpacing.lg),
                                child: TvFocusable(
                                  onActivate: () => _goTo(d),
                                  autofocus: d == AftabDestination.home,
                                  borderRadius: AftabRadius.sm,
                                  scale: 1.04,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: AftabSpacing.lg,
                                      vertical: AftabSpacing.sm,
                                    ),
                                    child: Row(
                                      children: <Widget>[
                                        Icon(
                                          _index == d.index
                                              ? d.filled
                                              : d.outlined,
                                          size: 20,
                                        ),
                                        const SizedBox(width: AftabSpacing.sm),
                                        Text(d.label(s)),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: KeyedSubtree(
                    key: ValueKey<int>(_generation),
                    child: IndexedStack(
                        index: _index, children: screens),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// TV home: hero + continue watching + top rails, all D-pad-first.
class _TvHome extends StatefulWidget {
  const _TvHome();

  @override
  State<_TvHome> createState() => _TvHomeState();
}

class _TvHomeState extends State<_TvHome> {
  CatalogSource? _catalog;
  List<WatchEntry> _continueEntries = const <WatchEntry>[];
  Map<String, WatchIndexEntry> _watchIndex = <String, WatchIndexEntry>{};
  List<CatalogItem> _topMovies = const <CatalogItem>[];
  List<CatalogItem> _topSeries = const <CatalogItem>[];
  bool _loading = true;
  String? _error;
  bool _kickstarted = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = AppScope.of(context);
    _catalog ??= scope.catalog;
    if (!_kickstarted) {
      _kickstarted = true;
      unawaited(_load(scope));
    }
  }

  Future<Object> _guard<T>(Future<T> future) async {
    try {
      return await future as Object;
    } on AftabException catch (e) {
      return e;
    } catch (e) {
      return AftabException(aftabUnknown, e.toString());
    }
  }

  Future<void> _load(AppScope scope) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final results = await Future.wait(<Future<Object>>[
      _guard(_catalog!.movies(sort: CatalogSort.byImdb, page: 0)),
      _guard(_catalog!.series(sort: CatalogSort.byImdb, page: 0)),
      _guard(scope.store.progressAll()),
      _guard(scope.watchIndex.entries()),
    ]);
    if (!mounted) return;
    final entries = results[2] is List<WatchEntry>
        ? results[2] as List<WatchEntry>
        : const <WatchEntry>[];
    final indexList = results[3] is List<WatchIndexEntry>
        ? results[3] as List<WatchIndexEntry>
        : const <WatchIndexEntry>[];
    setState(() {
      _loading = false;
      _topMovies = results[0] is List<CatalogItem>
          ? (results[0] as List<CatalogItem>).take(12).toList(growable: false)
          : const <CatalogItem>[];
      _topSeries = results[1] is List<CatalogItem>
          ? (results[1] as List<CatalogItem>).take(12).toList(growable: false)
          : const <CatalogItem>[];
      _continueEntries = entries
          .where((e) =>
              e.progress.positionSeconds > 30 &&
              e.progress.fraction < 0.95)
          .take(10)
          .toList(growable: false);
      _watchIndex = <String, WatchIndexEntry>{
        for (final e in indexList) e.key: e,
      };
      if (_topMovies.isEmpty && _topSeries.isEmpty) {
        AftabException? failure;
        for (final r in results.take(2)) {
          if (r is AftabException) {
            failure = r;
            break;
          }
        }
        _error = failure?.message;
      }
    });
  }

  void _openWatchEntry(WatchEntry entry) {
    final meta = _watchIndex['${entry.kind}:${entry.id}'];
    if (meta == null) return;
    openDetail(
      context,
      CatalogItem(
        id: entry.id,
        kind: entry.kind,
        title: meta.title,
        description: '',
        year: 0,
        imdb: 0,
        rating: 0,
        duration: null,
        image: meta.image,
        cover: '',
        genres: const <Genre>[],
        sources: const <Source>[],
        countries: const <Country>[],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    if (_error != null && _topMovies.isEmpty && _topSeries.isEmpty) {
      return AftabErrorPane(
        message: _error!,
        onRetry: () => unawaited(_load(AppScope.of(context))),
        icon: Icons.cloud_off,
      );
    }
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: AftabSpacing.md),
      children: <Widget>[
        if (_loading) ...<Widget>[
          const Padding(
            padding: EdgeInsets.symmetric(
              horizontal: AftabSpacing.xxl,
              vertical: AftabSpacing.md,
            ),
            child: SkeletonBox(height: 240, borderRadius: AftabRadius.lg),
          ),
          const SkeletonRail(),
        ] else ...<Widget>[
          if (_continueEntries.isNotEmpty) _continueRail(context, s),
          if (_topMovies.isNotEmpty)
            HeroBanner(
              item: _topMovies.first,
              onOpen: () => openDetail(context, _topMovies.first),
              height: 280,
              tv: true,
            ),
          if (_topMovies.isNotEmpty)
            const SizedBox(height: AftabSpacing.lg),
          MediaRail(
            title: s.topMovies,
            items: _topMovies,
            onOpenItem: (item) => openDetail(context, item),
            tvFocus: true,
            cardHeight: 300,
            autofocusFirst: true,
          ),
          MediaRail(
            title: s.topSeries,
            items: _topSeries,
            onOpenItem: (item) => openDetail(context, item),
            tvFocus: true,
            cardHeight: 300,
          ),
        ],
        const SizedBox(height: AftabSpacing.huge),
      ],
    );
  }

  Widget _continueRail(BuildContext context, S s) {
    final width = MediaQuery.sizeOf(context).width;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AftabSpacing.xxl,
            vertical: AftabSpacing.sm,
          ),
          child: Text(s.continueWatching,
              style: Theme.of(context).textTheme.titleLarge),
        ),
        SizedBox(
          height: 190,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AftabSpacing.xxl),
            itemCount: _continueEntries.length,
            separatorBuilder: (_, __) =>
                const SizedBox(width: AftabSpacing.sm),
            itemBuilder: (context, i) {
              final entry = _continueEntries[i];
              final meta = _watchIndex['${entry.kind}:${entry.id}'];
              return SizedBox(
                width: (width / 5).clamp(200, 320),
                child: TvFocusable(
                  onActivate: () => _openWatchEntry(entry),
                  child: WideCard(
                    image: meta?.image ?? '',
                    title: meta?.title ?? '…',
                    subtitle: s.resumeFrom(
                      _fmtPosition(context, entry),
                    ),
                    progressFraction: entry.progress.fraction,
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: AftabSpacing.lg),
      ],
    );
  }

  static String _fmtPosition(BuildContext context, WatchEntry entry) {
    final isFa = Localizations.localeOf(context).languageCode == 'fa';
    final minutes = minutesRemaining(
        entry.progress.positionSeconds, entry.progress.durationSeconds);
    final minutesText = formatInt(minutes, persian: isFa);
    return minutes > 0
        ? S.of(context).minutesLeft(minutesText)
        : S.of(context).resumeFrom(
            formatSeconds(entry.progress.positionSeconds, persian: isFa));
  }
}
