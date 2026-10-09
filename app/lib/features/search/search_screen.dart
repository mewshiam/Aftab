/// Search: a first-class experience — prominent field, recent searches,
/// content-type filter, debounced provider search with the core's
/// Persian-aware re-ranking, and honest empty / loading / error states.

library aftab_search_screen;

import 'dart:async';
import 'dart:convert' show LineSplitter;

import 'package:flutter/material.dart';

import '../../core/aftab_ffi.dart';
import '../../core/models.dart';
import '../../data/sources.dart';
import '../../design/tokens.dart';
import '../../l10n/app_localizations.dart';
import '../../navigation/app_scope.dart';
import '../../navigation/app_shell.dart';
import '../../utils/format.dart';
import '../../components/media_card.dart';
import '../../components/skeletons.dart';
import '../../components/states.dart';

enum _SearchType { all, movies, series }

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  static const _kRecentKey = 'ui.recent_searches';
  static const _maxRecent = 8;

  CatalogSource? _catalog;
  StoreSource? _store;

  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final List<CatalogItem> _providerResults = <CatalogItem>[];
  List<CatalogItem> _displayed = const <CatalogItem>[];
  List<String> _recent = <String>[];
  _SearchType _type = _SearchType.all;
  Timer? _debounce;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = AppScope.of(context);
    _catalog ??= scope.catalog;
    _store ??= scope.store;
    if (_recent.isEmpty) {
      unawaited(_loadRecent());
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller
      ..removeListener(_onChanged)
      ..dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onChanged() {
    final query = _controller.text;
    _debounce?.cancel();
    _refilterLocal(query);
    _debounce = Timer(const Duration(milliseconds: 350), () {
      unawaited(_run(query));
    });
    setState(() {});
  }

  Future<void> _loadRecent() async {
    try {
      final raw = await _store!.getSetting(_kRecentKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = const LineSplitter().convert(raw);
      if (mounted) setState(() => _recent = decoded.take(_maxRecent).toList());
    } catch (_) {
      // Recents are best-effort.
    }
  }

  Future<void> _saveRecent(String query) async {
    final q = query.trim();
    if (q.isEmpty) return;
    final list = <String>[q, ..._recent.where((r) => r != q)]
        .take(_maxRecent)
        .toList();
    setState(() => _recent = list);
    try {
      await _store!.setSetting(_kRecentKey, list.join('\n'));
    } catch (_) {
      // Best-effort persistence.
    }
  }

  Future<void> _clearRecent() async {
    setState(() => _recent = <String>[]);
    try {
      await _store!.setSetting(_kRecentKey, '');
    } catch (_) {
      // Best-effort.
    }
  }

  /// Instant client-side filter with the core's Persian scoring while
  /// the network round-trip is in flight.
  Future<void> _refilterLocal(String query) async {
    if (query.trim().isEmpty) {
      if (mounted) setState(() => _displayed = _providerResults);
      return;
    }
    try {
      final ranked = await _catalog!.rank(query, _providerResults);
      if (mounted) setState(() => _displayed = ranked);
    } catch (_) {
      // Local ranking is an optimization, never a failure.
    }
  }

  Future<void> _run(String query) async {
    final q = query.trim();
    if (q.isEmpty) {
      if (mounted) {
        setState(() {
          _providerResults.clear();
          _displayed = const <CatalogItem>[];
          _error = null;
        });
      }
      return;
    }
    setState(() => _loading = true);
    try {
      final results = await _catalog!.search(q);
      final ranked = await _catalog!.rank(q, results);
      if (!mounted) return;
      setState(() {
        _providerResults
          ..clear()
          ..addAll(results);
        _displayed = ranked;
        _error = null;
      });
      await _saveRecent(q);
    } on AftabException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<CatalogItem> get _typed => _displayed
      .where((item) => _type == _SearchType.all
          ? true
          : _type == _SearchType.movies
              ? !item.isSeries
              : item.isSeries)
      .toList(growable: false);

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final width = MediaQuery.sizeOf(context).width;
    return Scaffold(
      appBar: AppBar(
        title: Text(s.navSearch),
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: AftabSpacing.screenPadding(width),
              vertical: AftabSpacing.sm,
            ),
            child: SearchBar(
              controller: _controller,
              focusNode: _focusNode,
              hintText: s.searchHint,
              leading: const Icon(Icons.search),
              trailing: <Widget>[
                if (_controller.text.isNotEmpty)
                  IconButton(
                    tooltip: MaterialLocalizations.of(context)
                        .deleteButtonTooltip,
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      _controller.clear();
                      unawaited(_run(''));
                    },
                  ),
              ],
              onChanged: (value) => _onChanged(),
              onSubmitted: (value) {
                _focusNode.unfocus();
                unawaited(_run(value));
              },
            ),
          ),
          if (_loading)
            const LinearProgressIndicator(minHeight: 2)
          else
            const SizedBox(height: 2),
          if (_displayed.isNotEmpty) _typeChips(context, s),
          Expanded(child: _buildBody(context, s)),
        ],
      ),
    );
  }

  Widget _typeChips(BuildContext context, S s) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AftabSpacing.lg,
        vertical: AftabSpacing.xs,
      ),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: SegmentedButton<_SearchType>(
          showSelectedIcon: false,
          segments: <ButtonSegment<_SearchType>>[
            ButtonSegment<_SearchType>(
              value: _SearchType.all,
              label: Text(s.filterAll),
            ),
            ButtonSegment<_SearchType>(
              value: _SearchType.movies,
              label: Text(s.filterMovies),
            ),
            ButtonSegment<_SearchType>(
              value: _SearchType.series,
              label: Text(s.filterSeries),
            ),
          ],
          selected: <_SearchType>{_type},
          onSelectionChanged: (selection) =>
              setState(() => _type = selection.first),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, S s) {
    final typed = _typed;
    if (_controller.text.trim().isEmpty) return _recentBody(context, s);
    if (_error != null && typed.isEmpty) {
      return AftabErrorPane(
        message: _error!,
        onRetry: () => unawaited(_run(_controller.text)),
      );
    }
    if (typed.isEmpty && _loading) {
      return const SkeletonPosterGrid(itemCount: 9);
    }
    if (typed.isEmpty) {
      return AftabEmptyPane(
        title: s.searchNoResults(_controller.text.trim()),
        hint: s.searchNoResultsHint,
        icon: Icons.search_off,
      );
    }
    final width = MediaQuery.sizeOf(context).width;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: AftabSpacing.screenPadding(width),
            vertical: AftabSpacing.xs,
          ),
          child: Text(
            s.searchResultsCount(
              typed.length,
              formatInt(typed.length, persian: _isFa(context)),
            ),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        Expanded(
          child: GridView.builder(
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
            itemCount: typed.length,
            itemBuilder: (context, i) => PosterCard(
              item: typed[i],
              onTap: () => openDetail(context, typed[i]),
            ),
          ),
        ),
      ],
    );
  }

  Widget _recentBody(BuildContext context, S s) {
    if (_recent.isEmpty) {
      return AftabEmptyPane(
        title: s.searchStartPrompt,
        icon: Icons.search,
      );
    }
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(AftabSpacing.lg),
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(s.searchRecent, style: theme.textTheme.titleMedium),
            ),
            if (_recent.isNotEmpty)
              IconButton(
                tooltip: s.searchClearRecent,
                icon: const Icon(Icons.clear_all),
                onPressed: _clearRecent,
              ),
          ],
        ),
        for (final q in _recent)
          ListTile(
            leading: const Icon(Icons.history),
            title: Text(q),
            dense: true,
            onTap: () {
              _controller.text = q;
              unawaited(_run(q));
            },
          ),
      ],
    );
  }
}

bool _isFa(BuildContext context) =>
    Localizations.localeOf(context).languageCode == 'fa';
