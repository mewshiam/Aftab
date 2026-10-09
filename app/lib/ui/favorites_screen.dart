/// Favorites list, newest first, with quick removal.

import 'package:flutter/material.dart';

import '../core/aftab_ffi.dart';
import '../core/models.dart';
import '../core/store.dart';
import 'home_screen.dart' show AftabAppBar;
import 'detail_screen.dart';

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  final _store = AftabStore.instance;
  List<Favorite>? _favorites;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final favorites = await _store.favorites();
      if (!mounted) return;
      setState(() {
        _favorites = favorites;
        _error = null;
      });
    } on AftabException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _remove(Favorite favorite) async {
    await _store.removeFavorite(CatalogItem(
      id: favorite.id,
      kind: favorite.kind,
      title: favorite.title,
      description: '',
      year: favorite.year,
      imdb: 0,
      rating: 0,
      duration: null,
      image: favorite.image,
      cover: '',
      genres: const <Genre>[],
      sources: const <Source>[],
      countries: const <Country>[],
    ));
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AftabAppBar(title: 'علاقه‌مندی‌ها'),
      body: _buildBody(theme),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_error != null) {
      return Center(child: Text('خطا در خواندن علاقه‌مندی‌ها: $_error'));
    }
    if (_favorites == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_favorites!.isEmpty) {
      return Center(
        child: Text(
          'هنوز چیزی به علاقه‌مندی‌ها اضافه نکرده‌اید',
          style: theme.textTheme.bodyMedium,
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _favorites!.length,
        itemBuilder: (context, i) {
          final favorite = _favorites![i];
          return Card(
            margin: const EdgeInsets.symmetric(vertical: 6),
            child: ListTile(
              leading: favorite.image.isEmpty
                  ? const SizedBox(
                      width: 56,
                      height: 84,
                      child: ColoredBox(color: Color(0xFF1F2940)),
                    )
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.network(
                        favorite.image,
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
              title: Text(favorite.title),
              subtitle: Text(<String>[
                if (favorite.year > 0) '${favorite.year}',
                favorite.kind == 'serie' ? 'سریال' : 'فیلم',
              ].join(' · ')),
              trailing: IconButton(
                tooltip: 'حذف',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _remove(favorite),
              ),
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => DetailScreen(
                    item: CatalogItem(
                      id: favorite.id,
                      kind: favorite.kind,
                      title: favorite.title,
                      description: '',
                      year: favorite.year,
                      imdb: 0,
                      rating: 0,
                      duration: null,
                      image: favorite.image,
                      cover: '',
                      genres: const <Genre>[],
                      sources: const <Source>[],
                      countries: const <Country>[],
                    ),
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
