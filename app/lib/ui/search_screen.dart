/// Search: provider full-text search plus local Persian-aware re-ranking
/// of the current results while the query is refined.

library aftab_search_screen;

import 'dart:async';

import 'package:flutter/material.dart';

import '../core/aftab_ffi.dart';
import '../core/catalog.dart';
import '../core/models.dart';
import 'home_screen.dart' show AftabAppBar;
import 'detail_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _client = CatalogClient.instance;
  final _controller = TextEditingController();
  final List<CatalogItem> _providerResults = <CatalogItem>[];
  List<CatalogItem> _displayed = const <CatalogItem>[];
  Timer? _debounce;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _run(query));
    _refilterLocal(query);
  }

  /// Instant client-side filter with the core's Persian scoring while the
  /// network round-trip is in flight.
  Future<void> _refilterLocal(String query) async {
    if (query.trim().isEmpty) {
      if (mounted) setState(() => _displayed = _providerResults);
      return;
    }
    final ranked = await _client.rank(query, _providerResults);
    if (mounted) setState(() => _displayed = ranked);
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
      final results = await _client.search(q);
      final ranked = await _client.rank(q, results);
      if (!mounted) return;
      setState(() {
        _providerResults
          ..clear()
          ..addAll(results);
        _displayed = ranked;
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
    final theme = Theme.of(context);
    return Scaffold(
      appBar: const AftabAppBar(title: 'جست‌وجو'),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              controller: _controller,
              textInputAction: TextInputAction.search,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'نام فیلم یا سریال…',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _controller.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _controller.clear();
                          _onChanged('');
                        },
                      ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onChanged: _onChanged,
              onSubmitted: _run,
            ),
          ),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'جست‌وجو ناموفق بود: $_error',
                style: theme.textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ),
          Expanded(child: _buildResults(theme)),
        ],
      ),
    );
  }

  Widget _buildResults(ThemeData theme) {
    if (_displayed.isEmpty) {
      final String label;
      if (_loading) {
        label = 'در حال جست‌وجو…';
      } else if (_controller.text.trim().isEmpty) {
        label = 'نام مورد نظر را بنویسید';
      } else {
        label = 'نتیجه‌ای یافت نشد';
      }
      return Center(child: Text(label, style: theme.textTheme.bodyMedium));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _displayed.length,
      itemBuilder: (context, i) {
        final item = _displayed[i];
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 6),
          child: ListTile(
            leading: item.image.isEmpty
                ? const SizedBox(
                    width: 56,
                    height: 84,
                    child: ColoredBox(color: Color(0xFF1F2940)),
                  )
                : ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.network(
                      item.image,
                      width: 56,
                      height: 84,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox(
                        width: 56,
                        height: 84,
                        child: ColoredBox(color: Color(0xFF1F2940)),
                      ),
                    ),
                  ),
            title: Text(item.title),
            subtitle: Text(<String>[
              if (item.year > 0) '${item.year}',
              if (item.imdb > 0) 'IMDb ${item.imdb.toStringAsFixed(1)}',
            ].join(' · ')),
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => DetailScreen(item: item),
              ),
            ),
          ),
        );
      },
    );
  }
}
