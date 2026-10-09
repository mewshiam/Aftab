/// Full- and partial-screen UI states: loading, empty, error, offline.
///
/// Every significant surface renders one of these instead of a bare
/// spinner or blank canvas. Errors explain themselves in plain language
/// and always offer a way forward.

library aftab_states;

import 'package:flutter/material.dart';

import '../design/tokens.dart';
import '../l10n/app_localizations.dart';
import 'skeletons.dart';

/// Something failed; explains and offers retry.
class AftabErrorPane extends StatelessWidget {
  const AftabErrorPane({
    super.key,
    required this.message,
    this.onRetry,
    this.title,
    this.icon = Icons.cloud_off_outlined,
  });

  final String message;
  final VoidCallback? onRetry;
  final String? title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AftabSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              icon,
              size: 56,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: AftabSpacing.lg),
            Text(
              title ?? s.errorTitle,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AftabSpacing.sm),
            Text(
              message,
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...<Widget>[
              const SizedBox(height: AftabSpacing.xl),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: Text(s.retry),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Nothing here (yet) — with a hint about what to do next.
class AftabEmptyPane extends StatelessWidget {
  const AftabEmptyPane({
    super.key,
    required this.title,
    this.hint,
    this.icon = Icons.movie_outlined,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? hint;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AftabSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              icon,
              size: 56,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: AftabSpacing.lg),
            Text(
              title,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            if (hint != null) ...<Widget>[
              const SizedBox(height: AftabSpacing.sm),
              Text(
                hint!,
                style: theme.textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
            if (actionLabel != null && onAction != null) ...<Widget>[
              const SizedBox(height: AftabSpacing.xl),
              FilledButton.tonalIcon(
                onPressed: onAction,
                icon: const Icon(Icons.explore_outlined),
                label: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Inline error line for non-fatal failures (e.g. a failed "load more").
class AftabInlineError extends StatelessWidget {
  const AftabInlineError({
    super.key,
    required this.message,
    this.onRetry,
  });

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(AftabSpacing.lg),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.error),
            ),
          ),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: Text(s.retry)),
        ],
      ),
    );
  }
}

/// Content area still loading — poster-shaped skeletons.
class AftabLoadingGrid extends StatelessWidget {
  const AftabLoadingGrid({super.key, this.itemCount = 12});

  final int itemCount;

  @override
  Widget build(BuildContext context) {
    return SkeletonPosterGrid(itemCount: itemCount);
  }
}
