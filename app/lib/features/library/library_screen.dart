/// Library: favorites, continue watching and downloads — the user's
/// shelf. Every entry maps to real data; empty states suggest the next
/// action instead of dead space.

library aftab_library_screen;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/aftab_ffi.dart';
import '../../core/models.dart';
import '../../core/store.dart';
import '../../data/downloads.dart';
import '../../data/sources.dart';
import '../../data/watch_index.dart';
import '../../design/tokens.dart';
import '../../l10n/app_localizations.dart';
import '../../navigation/app_scope.dart';
import '../../navigation/app_shell.dart';
import '../../utils/format.dart';
import '../../player/player_screen.dart';
import '../../components/aftab_image.dart';
import '../../components/states.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs =
      TabController(length: 3, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(s.navLibrary),
        bottom: TabBar(
          controller: _tabs,
          tabs: <Widget>[
            Tab(text: s.libraryFavorites),
            Tab(text: s.libraryContinue),
            Tab(text: s.libraryDownloads),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: const <Widget>[
          _FavoritesPane(),
          _ContinuePane(),
          _DownloadsPane(),
        ],
      ),
    );
  }
}

// ── Favorites ───────────────────────────────────────────────────────────────

class _FavoritesPane extends StatefulWidget {
  const _FavoritesPane();

  @override
  State<_FavoritesPane> createState() => _FavoritesPaneState();
}

class _FavoritesPaneState extends State<_FavoritesPane>
    with AutomaticKeepAliveClientMixin {
  StoreSource? _store;
  List<Favorite>? _favorites;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _store ??= AppScope.storeOf(context);
    if (_favorites == null && _error == null) {
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    try {
      final favorites = await _store!.favorites();
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
    await _store!.removeFavorite(favorite.asCatalogItem);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final s = S.of(context);
    if (_error != null) {
      return AftabErrorPane(message: _error!, onRetry: _load);
    }
    if (_favorites == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_favorites!.isEmpty) {
      return AftabEmptyPane(
        title: s.favoritesEmpty,
        hint: s.favoritesEmptyHint,
        icon: Icons.favorite_border,
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(AftabSpacing.md),
        itemCount: _favorites!.length,
        itemBuilder: (context, i) => _favoriteTile(context, _favorites![i]),
      ),
    );
  }

  Widget _favoriteTile(BuildContext context, Favorite favorite) {
    final s = S.of(context);
    final isFa = Localizations.localeOf(context).languageCode == 'fa';
    return Card(
      margin: const EdgeInsets.symmetric(vertical: AftabSpacing.xs),
      child: ListTile(
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(AftabRadius.sm),
          child: SizedBox(
            width: 56,
            height: 84,
            child: AftabImage(url: favorite.image),
          ),
        ),
        title: Text(
          favorite.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          <String>[
            if (favorite.year > 0) formatInt(favorite.year, persian: isFa),
            favorite.kind == 'serie' ? s.seriesLabel : s.movieLabel,
          ].join(' · '),
        ),
        trailing: IconButton(
          tooltip: s.favoriteRemove,
          icon: const Icon(Icons.delete_outline),
          onPressed: () => unawaited(_remove(favorite)),
        ),
        onTap: () => openDetail(context, favorite.asCatalogItem),
      ),
    );
  }
}

// ── Continue watching ──────────────────────────────────────────────────────

class _ContinuePane extends StatefulWidget {
  const _ContinuePane();

  @override
  State<_ContinuePane> createState() => _ContinuePaneState();
}

class _ContinuePaneState extends State<_ContinuePane>
    with AutomaticKeepAliveClientMixin {
  AppScope? _scope;
  List<WatchEntry>? _entries;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scope ??= AppScope.of(context);
    if (_entries == null && _error == null) {
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    try {
      final entries = await _scope!.store.progressAll();
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _error = null;
      });
    } on AftabException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final s = S.of(context);
    if (_error != null) {
      return AftabErrorPane(message: _error!, onRetry: _load);
    }
    if (_entries == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final visible =
        _entries!.where((e) => e.progress.fraction < 0.95).toList();
    if (visible.isEmpty) {
      return AftabEmptyPane(
        title: s.continueEmpty,
        hint: s.continueEmptyHint,
        icon: Icons.play_circle_outline,
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(AftabSpacing.md),
        itemCount: visible.length,
        itemBuilder: (context, i) =>
            _continueTile(context, visible[i], _load),
      ),
    );
  }

  Widget _continueTile(
      BuildContext context, WatchEntry entry, Future<void> Function() refresh) {
    return _WatchTile(
      entry: entry,
      watchIndex: AppScope.watchIndexOf(context),
      store: AppScope.storeOf(context),
      onRefresh: refresh,
    );
  }
}

/// Shared row: resolves display info from the watch index, offers
/// "remove from continue watching".
class _WatchTile extends StatefulWidget {
  const _WatchTile({
    required this.entry,
    required this.watchIndex,
    required this.store,
    required this.onRefresh,
  });

  final WatchEntry entry;
  final WatchIndex watchIndex;
  final StoreSource store;
  final Future<void> Function() onRefresh;

  @override
  State<_WatchTile> createState() => _WatchTileState();
}

class _WatchTileState extends State<_WatchTile> {
  String? _title;
  String? _image;

  @override
  void initState() {
    super.initState();
    unawaited(_loadMeta());
  }

  Future<void> _loadMeta() async {
    final meta =
        await widget.watchIndex.entry(widget.entry.kind, widget.entry.id);
    if (!mounted) return;
    setState(() {
      _title = meta?.title;
      _image = meta?.image;
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final isFa = Localizations.localeOf(context).languageCode == 'fa';
    final title = _title;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: AftabSpacing.xs),
      child: ListTile(
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(AftabRadius.sm),
          child: SizedBox(
            width: 56,
            height: 84,
            child: AftabImage(url: _image ?? ''),
          ),
        ),
        title: Text(
          title ?? '…',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              s.resumeFrom(formatSeconds(entry2position(widget.entry),
                  persian: isFa)),
            ),
            const SizedBox(height: AftabSpacing.xs),
            LinearProgressIndicator(
              value: widget.entry.progress.fraction,
              minHeight: 3,
            ),
          ],
        ),
        isThreeLine: true,
        trailing: IconButton(
          tooltip: s.clearProgress,
          icon: const Icon(Icons.playlist_remove),
          onPressed: () async {
            await widget.store.clearProgress(_asItem());
            await widget.onRefresh();
          },
        ),
        onTap: () => openDetail(context, _asItem()),
      ),
    );
  }

  static double entry2position(WatchEntry entry) =>
      entry.progress.positionSeconds;

  CatalogItem _asItem() => CatalogItem(
        id: widget.entry.id,
        kind: widget.entry.kind,
        title: _title ?? '',
        description: '',
        year: 0,
        imdb: 0,
        rating: 0,
        duration: null,
        image: _image ?? '',
        cover: '',
        genres: const <Genre>[],
        sources: const <Source>[],
        countries: const <Country>[],
      );
}

// ── Downloads ──────────────────────────────────────────────────────────────

class _DownloadsPane extends StatefulWidget {
  const _DownloadsPane();

  @override
  State<_DownloadsPane> createState() => _DownloadsPaneState();
}

class _DownloadsPaneState extends State<_DownloadsPane>
    with AutomaticKeepAliveClientMixin {
  DownloadManager? _downloads;
  List<DownloadRecord>? _records;

  @override
  bool get wantKeepAlive => true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _downloads ??= AppScope.downloadsOf(context);
    if (_records == null) {
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    final records = await _downloads!.records();
    if (mounted) setState(() => _records = records);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final s = S.of(context);
    if (_records == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_records!.isEmpty) {
      return AftabEmptyPane(
        title: s.downloadsEmpty,
        hint: s.downloadsEmptyHint,
        icon: Icons.download_outlined,
      );
    }
    final isFa = Localizations.localeOf(context).languageCode == 'fa';
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(AftabSpacing.md),
        itemCount: _records!.length,
        itemBuilder: (context, i) => _recordTile(context, _records![i], isFa),
      ),
    );
  }

  Widget _recordTile(BuildContext context, DownloadRecord record, bool isFa) {
    final s = S.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: AftabSpacing.xs),
      child: ListTile(
        leading: const Icon(Icons.download_done, size: 32),
        title: Text(
          record.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(formatBytes(record.bytes, persian: isFa)),
        isThreeLine: false,
        trailing: IconButton(
          tooltip: s.deleteDownload,
          icon: const Icon(Icons.delete_outline),
          onPressed: () async {
            await _downloads!.remove(record);
            await _load();
          },
        ),
        onTap: () {
          // Local file playback: a path we created ourselves, so it does
          // not go through the network-URL safety check.
          Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (_) => PlayerScreen.localFile(
                title: record.title,
                path: record.path,
              ),
            ),
          );
        },
      ),
    );
  }
}

extension on Favorite {
  CatalogItem get asCatalogItem => CatalogItem(
        id: id,
        kind: kind,
        title: title,
        description: '',
        year: year,
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
