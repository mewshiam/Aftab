/// Media cards: the atomic unit of every grid and rail.
///
/// One component, three flavors:
///
/// * [PosterCard]   — 2:3 artwork, title, year/rating line, progress.
/// * [WideCard]     — 16:9 artwork for landscape thumbnails.
/// * [EpisodeTile]  — episode row with thumbnail, duration, progress.
///
/// Cards are artwork-first, adapt to touch / hover / focus, and expose
/// full semantics for screen readers.

library aftab_media_card;

import 'package:flutter/material.dart';

import '../core/models.dart';
import '../design/tokens.dart';
import '../l10n/app_localizations.dart';
import '../utils/format.dart';
import 'aftab_image.dart';
import 'tv_focus.dart';

/// How the card should present focus.
enum CardFocusMode { none, tv }

class PosterCard extends StatelessWidget {
  const PosterCard({
    super.key,
    required this.item,
    this.onTap,
    this.progressFraction,
    this.downloaded = false,
    this.focusMode = CardFocusMode.none,
    this.autofocus = false,
    this.compact = false,
  });

  final CatalogItem item;
  final VoidCallback? onTap;
  final double? progressFraction;
  final bool downloaded;
  final CardFocusMode focusMode;
  final bool autofocus;

  /// Slim layout for dense rails: single-line meta.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    final typeLabel = item.isSeries ? s.seriesLabel : s.movieLabel;
    final meta = <String>[
      if (item.year > 0) formatInt(item.year, persian: _isFa(context)),
      if (item.imdb > 0)
        s.imdbRating(formatDouble(item.imdb, persian: _isFa(context))),
    ].join(' · ');

    // Card provides the Material surface; InkWell prints its ink on it.
    Widget card = Card(
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(child: _artwork(context, s, typeLabel)),
            if (!compact) const SizedBox(height: AftabSpacing.sm),
            Padding(
              padding: const EdgeInsetsDirectional.only(
                top: AftabSpacing.sm,
                end: AftabSpacing.xs,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge,
                  ),
                  if (meta.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    if (focusMode == CardFocusMode.tv) {
      card = TvFocusable(
        autofocus: autofocus,
        onActivate: onTap,
        child: card,
      );
    }

    return RepaintBoundary(
      child: Semantics(
        label: s.posterSemantic(item.title, typeLabel),
        button: true,
        child: card,
      ),
    );
  }

  Widget _artwork(BuildContext context, S s, String typeLabel) {
    final scheme = Theme.of(context).colorScheme;
    return Stack(
      fit: StackFit.passthrough,
      children: <Widget>[
        Positioned.fill(
          child: AftabImage(
            url: item.image,
            semanticLabel: s.posterSemantic(item.title, typeLabel),
            borderRadius: AftabRadius.md,
            fallbackIcon: item.isSeries
                ? Icons.tv_outlined
                : Icons.movie_outlined,
          ),
        ),
        if (downloaded)
          PositionedDirectional(
            top: AftabSpacing.sm,
            end: AftabSpacing.sm,
            child: _Badge(
              icon: Icons.offline_pin,
              label: s.downloadedBadge,
              scheme: scheme,
            ),
          ),
        if (progressFraction != null && progressFraction! > 0)
          PositionedDirectional(
            start: 0,
            end: 0,
            bottom: 0,
            child: _ProgressStrip(
              fraction: progressFraction!,
              scheme: scheme,
            ),
          ),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.icon, required this.label, required this.scheme});

  final IconData icon;
  final String label;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      child: Container(
        padding: const EdgeInsets.all(AftabSpacing.xs),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(AftabRadius.sm),
        ),
        child: Icon(icon, size: 14, color: scheme.primary),
      ),
    );
  }
}

class _ProgressStrip extends StatelessWidget {
  const _ProgressStrip({required this.fraction, required this.scheme});

  final double fraction;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 3.5,
      color: Colors.black38,
      child: FractionallySizedBox(
        alignment: AlignmentDirectional.centerStart,
        widthFactor: fraction.clamp(0.0, 1.0),
        child: ColoredBox(color: scheme.primary),
      ),
    );
  }
}

/// Landscape card for wide thumbnails (continue watching, episodes).
class WideCard extends StatelessWidget {
  const WideCard({
    super.key,
    required this.image,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.progressFraction,
    this.focusMode = CardFocusMode.none,
    this.autofocus = false,
  });

  final String image;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final double? progressFraction;
  final CardFocusMode focusMode;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // Material (not Card) so the 16:9 artwork can bleed to the edges.
    Widget card = Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(AftabRadius.md),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.passthrough,
                children: <Widget>[
                  Positioned.fill(
                    child: AftabImage(
                      url: image,
                      fallbackIcon: Icons.smart_display_outlined,
                    ),
                  ),
                  if (progressFraction != null && progressFraction! > 0)
                    PositionedDirectional(
                      start: 0,
                      end: 0,
                      bottom: 0,
                      child: _ProgressStrip(
                        fraction: progressFraction!,
                        scheme: scheme,
                      ),
                    ),
                  PositionedDirectional(
                    start: AftabSpacing.sm,
                    bottom: AftabSpacing.sm,
                    child: _PlayChip(scheme: scheme),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AftabSpacing.sm),
            Padding(
              padding: const EdgeInsetsDirectional.only(end: AftabSpacing.xs),
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelLarge,
              ),
            ),
            if (subtitle.isNotEmpty)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: AftabSpacing.xs),
                child: Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
    );
    if (focusMode == CardFocusMode.tv) {
      card = TvFocusable(autofocus: autofocus, onActivate: onTap, child: card);
    }
    return RepaintBoundary(child: card);
  }
}

class _PlayChip extends StatelessWidget {
  const _PlayChip({required this.scheme});

  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AftabSpacing.xs + 2),
      decoration: BoxDecoration(
        color: Colors.black45,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white24),
      ),
      child: const Icon(Icons.play_arrow, size: 18, color: Colors.white),
    );
  }
}

/// Episode row inside a season list.
class EpisodeTile extends StatelessWidget {
  const EpisodeTile({
    super.key,
    required this.episode,
    this.onTap,
    this.focusMode = CardFocusMode.none,
  });

  final Episode episode;
  final VoidCallback? onTap;
  final CardFocusMode focusMode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = S.of(context);
    Widget tile = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AftabSpacing.md,
            vertical: AftabSpacing.sm,
          ),
          child: Row(
            children: <Widget>[
              ClipRRect(
                borderRadius: BorderRadius.circular(AftabRadius.sm),
                child: SizedBox(
                  width: 112,
                  height: 63,
                  child: AftabImage(
                    url: episode.image,
                    fallbackIcon: Icons.smart_display_outlined,
                  ),
                ),
              ),
              const SizedBox(width: AftabSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      episode.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall,
                    ),
                    if (episode.duration != null &&
                        episode.duration!.isNotEmpty)
                      Text(
                        episode.duration!,
                        style: theme.textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: AftabSpacing.sm),
              Icon(
                Icons.play_circle_outline,
                color: theme.colorScheme.primary,
                semanticLabel: s.play,
              ),
            ],
          ),
        ),
      ),
    );
    if (focusMode == CardFocusMode.tv) {
      tile = TvFocusable(onActivate: onTap, child: tile);
    }
    return tile;
  }
}

bool _isFa(BuildContext context) =>
    Localizations.localeOf(context).languageCode == 'fa';
