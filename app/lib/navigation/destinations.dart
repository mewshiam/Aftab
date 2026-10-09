/// Navigation destinations — one information architecture, one icon set.

library aftab_destinations;

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

enum AftabDestination { home, discover, search, library, settings }

extension AftabDestinationX on AftabDestination {
  String label(S s) {
    switch (this) {
      case AftabDestination.home:
        return s.navHome;
      case AftabDestination.discover:
        return s.navDiscover;
      case AftabDestination.search:
        return s.navSearch;
      case AftabDestination.library:
        return s.navLibrary;
      case AftabDestination.settings:
        return s.navSettings;
    }
  }

  IconData get outlined {
    switch (this) {
      case AftabDestination.home:
        return Icons.home_outlined;
      case AftabDestination.discover:
        return Icons.explore_outlined;
      case AftabDestination.search:
        return Icons.search;
      case AftabDestination.library:
        return Icons.video_library_outlined;
      case AftabDestination.settings:
        return Icons.settings_outlined;
    }
  }

  IconData get filled {
    switch (this) {
      case AftabDestination.home:
        return Icons.home;
      case AftabDestination.discover:
        return Icons.explore;
      case AftabDestination.search:
        return Icons.search;
      case AftabDestination.library:
        return Icons.video_library;
      case AftabDestination.settings:
        return Icons.settings;
    }
  }

  /// Ctrl+N shortcut index (desktop).
  int get shortcutIndex => switch (this) {
        AftabDestination.home => 1,
        AftabDestination.discover => 2,
        AftabDestination.search => 3,
        AftabDestination.library => 4,
        AftabDestination.settings => 5,
      };
}
