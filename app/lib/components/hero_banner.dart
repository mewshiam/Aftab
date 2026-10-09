/// [HeroBanner]: the compact featured strip on Home. Only shown when the
/// top item has real artwork; deliberately restrained height so content
/// stays above the fold.

library aftab_hero_banner;

import 'package:flutter/material.dart';

import '../core/models.dart';
import '../design/tokens.dart';
import '../l10n/app_localizations.dart';
import 'aftab_image.dart';

class HeroBanner extends StatelessWidget {
  const HeroBanner({
    super.key,
    required this.item,
    required this.onOpen,
    this.height = 210,
    this.tv = false,
  });

  final CatalogItem item;
  final VoidCallback onOpen;

  /// Total banner height; grows for the 10-foot UI.
  final double height;

  final bool tv;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final scheme = Theme.of(context).colorScheme;
    final backdrop = item.cover.isNotEmpty ? item.cover : item.image;
    final effectiveHeight = tv ? height * 1.6 : height;

    return Semantics(
      label: s.posterSemantic(item.title, s.featured),
      button: true,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: AftabSpacing.screenPadding(MediaQuery.sizeOf(context).width),
        ),
        child: Material(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(AftabRadius.lg),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onOpen,
            child: SizedBox(
              height: effectiveHeight,
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  AftabImage(
                    url: backdrop,
                    fallbackIcon: Icons.movie_filter_outlined,
                  ),
                  const _Scrim(),
                  PositionedDirectional(
                    start: AftabSpacing.lg,
                    bottom: AftabSpacing.lg,
                    end: AftabSpacing.xl,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          s.featured,
                          style: Theme.of(context)
                              .textTheme
                              .labelMedium
                              ?.copyWith(color: scheme.primary),
                        ),
                        const SizedBox(height: AftabSpacing.xs),
                        Text(
                          item.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Scrim extends StatelessWidget {
  const _Scrim();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: AlignmentDirectional.bottomCenter,
          end: AlignmentDirectional.topCenter,
          stops: <double>[0, 0.85],
          colors: <Color>[Colors.black87, Colors.transparent],
        ),
      ),
    );
  }
}
