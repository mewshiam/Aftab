/// The tabbed home: فیلم‌ها / سریال‌ها / جست‌وجو / علاقه‌مندی‌ها.

import 'package:flutter/material.dart';

import 'catalog_screen.dart';
import 'favorites_screen.dart';
import 'search_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;

  static const _screens = <Widget>[
    CatalogScreen(kind: CatalogKind.movies),
    CatalogScreen(kind: CatalogKind.series),
    SearchScreen(),
    FavoritesScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const <Widget>[
          NavigationDestination(
            icon: Icon(Icons.movie_outlined),
            selectedIcon: Icon(Icons.movie, color: Colors.black),
            label: 'فیلم‌ها',
          ),
          NavigationDestination(
            icon: Icon(Icons.tv_outlined),
            selectedIcon: Icon(Icons.tv, color: Colors.black),
            label: 'سریال‌ها',
          ),
          NavigationDestination(
            icon: Icon(Icons.search),
            selectedIcon: Icon(Icons.search, color: Colors.black),
            label: 'جست‌وجو',
          ),
          NavigationDestination(
            icon: Icon(Icons.favorite_border),
            selectedIcon: Icon(Icons.favorite, color: Colors.black),
            label: 'علاقه‌مندی‌ها',
          ),
        ],
      ),
    );
  }
}

/// Shared app bar for the tab screens.
class AftabAppBar extends StatelessWidget implements PreferredSizeWidget {
  const AftabAppBar({super.key, required this.title, this.actions});

  final String title;
  final List<Widget>? actions;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: Text(title),
      actions: <Widget>[
        ...?actions,
        IconButton(
          tooltip: 'تنظیمات',
          icon: const Icon(Icons.settings_outlined),
          onPressed: () => Navigator.of(context).push<void>(
            MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
          ),
        ),
      ],
    );
  }
}
