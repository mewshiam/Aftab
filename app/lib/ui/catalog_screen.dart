/// The catalog grid: movies or series, with sort control and infinite
/// scroll pagination.

import 'package:flutter/material.dart';

import '../core/aftab_ffi.dart';
import '../core/catalog.dart';
import '../core/models.dart';
import 'detail_screen.dart';
import 'home_screen.dart';

enum CatalogKind { movies, series }

class CatalogScreen extends StatefulWidget {
  const CatalogScreen({super.key, required this.kind});

  final CatalogKind kind;

  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen>
    with AutomaticKeepAliveClientMixin {
  final _client = CatalogClient.instance;
  final _scroll = ScrollController();
  final List<CatalogItem> _items = <CatalogItem>[];
  int _page = 0;
  CatalogSort _sort = CatalogSort.newest;
  bool _loading = false;
  bool _exhausted = false;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _reload();
  }

  @override
  void dispose() {
    _scroll
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    if (_scroll.position.extentAfter < 600) {
      _loadMore();
    }
  }

  Future<List<CatalogItem>> _fetch(int page) => widget.kind == CatalogKind.movies
      ? _client.movies(sort: _sort, page: page)
      : _client.series(sort: _sort, page: page);

  Future<void> _reload() async {
    setState(() {
      _items.clear();
      _page = 0;
      _exhausted = false;
      _error = null;
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
      });
    } on AftabException catch (e) {
      // Pagination failures are soft: keep what we have, show a hint.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('بارگذاری صفحهٔ بعد ناموفق بود: ${e.message}')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final title =
        widget.kind == CatalogKind.movies ? 'فیلم‌ها' : 'سریال‌ها';
    return Scaffold(
      appBar: AftabAppBar(
        title: title,
        actions: <Widget>[
          PopupMenuButton<CatalogSort>(
            tooltip: 'ترتیب',
            icon: const Icon(Icons.sort),
            initialValue: _sort,
            onSelected: (sort) {
              setState(() => _sort = sort);
              _reload();
            },
            itemBuilder: (_) => <PopupMenuEntry<CatalogSort>>[
              for (final s in CatalogSort.values)
                PopupMenuItem<CatalogSort>(
                  value: s,
                  child: Text(s.persianLabel),
                ),
            ],
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_error != null && _items.isEmpty) {
      return _ErrorPane(message: _error!, onRetry: _reload);
    }
    if (_items.isEmpty && _loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_items.isEmpty) {
      return const _EmptyPane(label: 'چیزی برای نمایش نیست');
    }
    final grid = GridView.builder(
      controller: _scroll,
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 160,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.62,
      ),
      itemCount: _items.length + (_loading ? 1 : 0),
      itemBuilder: (context, i) {
        if (i >= _items.length) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(),
            ),
          );
        }
        return _PosterCard(item: _items[i]);
      },
    );
    return RefreshIndicator(onRefresh: _reload, child: grid);
  }
}

class _PosterCard extends StatelessWidget {
  const _PosterCard({required this.item});

  final CatalogItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: InkWell(
        onTap: () => Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (_) => DetailScreen(item: item),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Expanded(
              child: item.image.isEmpty
                  ? ColoredBox(
                      color: theme.colorScheme.surface,
                      child: const Center(
                        child: Icon(Icons.movie_outlined, size: 40),
                      ),
                    )
                  : Image.network(
                      item.image,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => ColoredBox(
                        color: theme.colorScheme.surface,
                        child: const Center(
                          child: Icon(Icons.broken_image_outlined, size: 32),
                        ),
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                  if (item.year > 0)
                    Text(
                      '${item.year}',
                      style: theme.textTheme.bodySmall,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorPane extends StatelessWidget {
  const _ErrorPane({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.cloud_off, size: 48),
            const SizedBox(height: 12),
            Text(
              'اتصال به سرور برقرار نشد',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('تلاش دوباره'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyPane extends StatelessWidget {
  const _EmptyPane({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
    );
  }
}
