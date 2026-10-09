/// Android TV home: big focusable cards, D-pad-first navigation.
///
/// Every card is a `FocusableActionDetector`; the default focus traversal
/// order follows the grid layout, which is what remotes expect (left/right
/// move inside a row, up/down move between rows). The first card gets
/// autofocus so the TV lands somewhere sensible right after launch.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/aftab_ffi.dart';
import '../core/catalog.dart';
import '../core/models.dart';
import '../ui/detail_screen.dart';
import '../ui/theme.dart';

class TvHomeScreen extends StatefulWidget {
  const TvHomeScreen({super.key});

  @override
  State<TvHomeScreen> createState() => _TvHomeScreenState();
}

class _TvHomeScreenState extends State<TvHomeScreen> {
  final _client = CatalogClient.instance;

  List<CatalogItem> _movies = const <CatalogItem>[];
  List<CatalogItem> _series = const <CatalogItem>[];
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final movies = await _client.movies(sort: CatalogSort.byImdb, page: 0);
      final series = await _client.series(sort: CatalogSort.byImdb, page: 0);
      if (!mounted) return;
      setState(() {
        _movies = movies.take(12).toList(growable: false);
        _series = series.take(12).toList(growable: false);
        _error = null;
      });
    } on AftabException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AftabTheme.background,
      body: Focus(
        autofocus: true,
        onKeyEvent: (node, event) {
          // Color buttons on many Iranian/LG/Samsung remotes refresh.
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.keyR) {
            _load();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: _buildBody(context),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading && _movies.isEmpty && _series.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: AftabTheme.accent));
    }
    if (_error != null && _movies.isEmpty && _series.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.cloud_off, size: 64, color: AftabTheme.muted),
            const SizedBox(height: 16),
            Text(
              'اتصال برقرار نشد',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 48),
              child: Text(
                _error!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('تلاش دوباره'),
            ),
          ],
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 32),
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 48),
          child: Text(
            'آفتاب مدیا',
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(color: AftabTheme.accent),
          ),
        ),
        if (_movies.isNotEmpty)
          _TvRow(label: 'برترین فیلم‌ها', items: _movies),
        if (_series.isNotEmpty)
          _TvRow(label: 'برترین سریال‌ها', items: _series),
      ],
    );
  }
}

class _TvRow extends StatelessWidget {
  const _TvRow({required this.label, required this.items});

  final String label;
  final List<CatalogItem> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
          child: Text(
            label,
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        SizedBox(
          height: 300,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 48),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 20),
            itemBuilder: (context, i) => _TvCard(
              item: items[i],
              autofocus: i == 0 && label.startsWith('برترین فیلم'),
            ),
          ),
        ),
      ],
    );
  }
}

class _TvCard extends StatelessWidget {
  const _TvCard({required this.item, required this.autofocus});

  final CatalogItem item;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      autofocus: autofocus,
      mouseCursor: SystemMouseCursors.click,
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => DetailScreen(item: item),
              ),
            );
            return null;
          },
        ),
      },
      child: Builder(
        builder: (context) {
          final focused = Focus.of(context).hasFocus;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            transform: Matrix4.diagonal3Values(
              focused ? 1.06 : 1.0,
              focused ? 1.06 : 1.0,
              1.0,
            ),
            child: Card(
              color: focused ? AftabTheme.surfaceVariant : AftabTheme.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: focused
                    ? const BorderSide(color: AftabTheme.accent, width: 3)
                    : BorderSide.none,
              ),
              child: InkWell(
                onTap: () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => DetailScreen(item: item),
                  ),
                ),
                child: SizedBox(
                  width: 180,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Expanded(
                        child: item.image.isEmpty
                            ? const ColoredBox(
                                color: AftabTheme.surfaceVariant,
                                child: Center(
                                  child: Icon(Icons.movie_outlined, size: 48),
                                ),
                              )
                            : Image.network(
                                item.image,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const ColoredBox(
                                  color: AftabTheme.surfaceVariant,
                                  child: Center(
                                    child: Icon(Icons.broken_image_outlined),
                                  ),
                                ),
                              ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              item.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            if (item.imdb > 0)
                              Text(
                                'IMDb ${item.imdb.toStringAsFixed(1)}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
