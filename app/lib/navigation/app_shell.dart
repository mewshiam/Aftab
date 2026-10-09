/// The adaptive app shell.
///
/// * Compact (phones)  → Material 3 bottom [NavigationBar].
/// * Medium (tablets)  → [NavigationRail] with labels.
/// * Expanded/desktop  → extended [NavigationRail] + Ctrl+1…5 shortcuts.
///
/// All destinations live in an [IndexedStack] so scroll positions and
/// loaded pages survive tab switches.

library aftab_app_shell;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/models.dart';
import '../design/tokens.dart';
import '../l10n/app_localizations.dart';
import '../platform/form_factor.dart';
import '../features/details/detail_screen.dart';
import '../features/discover/discover_screen.dart';
import '../features/home/home_screen.dart';
import '../features/library/library_screen.dart';
import '../features/search/search_screen.dart';
import '../features/settings/settings_screen.dart';
import 'destinations.dart';

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.formFactor,
    this.initialDestination = AftabDestination.home,
  });

  final FormFactor formFactor;
  final AftabDestination initialDestination;

  @override
  State<AppShell> createState() => AppShellState();

  /// Lets other widgets (e.g. TV search entry) switch the visible tab.
  static AppShellState of(BuildContext context) =>
      context.findAncestorStateOfType<AppShellState>()!;
}

class AppShellState extends State<AppShell> {
  static AppShellState? _instance;

  /// Global access for deep-links from pushed routes (e.g. genre chips).
  static AppShellState? get instance => _instance;

  late int _index = widget.initialDestination.index;

  @override
  void initState() {
    super.initState();
    _instance = this;
  }

  @override
  void dispose() {
    _instance = null;
    super.dispose();
  }

  void goTo(AftabDestination destination) {
    setState(() => _index = destination.index);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final expanded = width >= AftabBreakpoints.expanded ||
        widget.formFactor == FormFactor.desktop;
    final medium = width >= AftabBreakpoints.medium;

    final screens = <Widget>[
      const HomeScreen(),
      const DiscoverScreen(),
      const SearchScreen(),
      const LibraryScreen(),
      const SettingsScreen(),
    ];

    final body = IndexedStack(index: _index, children: screens);

    Widget shell;
    if (expanded || medium) {
      shell = Row(
        children: <Widget>[
          NavigationRail(
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            extended: expanded,
            minExtendedWidth: 200,
            destinations: <NavigationRailDestination>[
              for (final d in AftabDestination.values)
                NavigationRailDestination(
                  icon: Icon(d.outlined),
                  selectedIcon: Icon(d.filled),
                  label: Text(d.label(s)),
                ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: body),
        ],
      );
    } else {
      shell = Scaffold(
        body: body,
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: <Widget>[
            for (final d in AftabDestination.values)
              NavigationDestination(
                icon: Icon(d.outlined),
                selectedIcon: Icon(d.filled),
                label: d.label(s),
                tooltip: d.label(s),
              ),
          ],
        ),
      );
    }

    // Desktop keyboard shortcuts: Ctrl+1…5 jump between destinations.
    if (widget.formFactor == FormFactor.desktop) {
      shell = Shortcuts(
        shortcuts: <ShortcutActivator, Intent>{
          for (final d in AftabDestination.values)
            SingleActivator(
              _digitKeys[d.shortcutIndex - 1],
              control: true,
            ): _GoToDestinationIntent(d),
        },
        child: Actions(
          actions: <Type, Action<Intent>>{
            _GoToDestinationIntent: CallbackAction<_GoToDestinationIntent>(
              onInvoke: (intent) {
                goTo(intent.destination);
                return null;
              },
            ),
          },
          child: shell,
        ),
      );
    }
    return shell;
  }
}

/// Opens [destination] from anywhere under the shell (used by "see all").
void openDestination(BuildContext context, AftabDestination destination) {
  AppShell.of(context).goTo(destination);
}

/// Opens a detail page above the shell.
void openDetail(BuildContext context, CatalogItem item) {
  Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => DetailScreen(item: item),
    ),
  );
}

class _GoToDestinationIntent extends Intent {
  const _GoToDestinationIntent(this.destination);

  final AftabDestination destination;
}

const List<LogicalKeyboardKey> _digitKeys = <LogicalKeyboardKey>[
  LogicalKeyboardKey.digit1,
  LogicalKeyboardKey.digit2,
  LogicalKeyboardKey.digit3,
  LogicalKeyboardKey.digit4,
  LogicalKeyboardKey.digit5,
];
