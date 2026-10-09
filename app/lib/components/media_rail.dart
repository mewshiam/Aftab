/// [MediaRail]: titled horizontal rows of cards — the backbone of the
/// home screen and TV.

library aftab_media_rail;

import 'package:flutter/material.dart';

import '../core/models.dart';
import '../design/tokens.dart';
import '../l10n/app_localizations.dart';
import 'media_card.dart';
import 'skeletons.dart';

class MediaRail extends StatelessWidget {
  const MediaRail({
    super.key,
    required this.title,
    required this.items,
    required this.onOpenItem,
    this.onSeeAll,
    this.loading = false,
    this.tvFocus = false,
    this.progressOf,
    this.cardHeight = 232,
    this.autofocusFirst = false,
  });

  final String title;
  final List<CatalogItem> items;
  final ValueChanged<CatalogItem> onOpenItem;
  final VoidCallback? onSeeAll;

  /// Show skeleton cards instead of content.
  final bool loading;
  final bool tvFocus;
  final double Function(CatalogItem)? progressOf;
  final double cardHeight;
  final bool autofocusFirst;

  @override
  Widget build(BuildContext context) {
    if (!loading && items.isEmpty) return const SizedBox.shrink();
    final s = S.of(context);
    final theme = Theme.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final cardWidth = railCardWidth(width).clamp(96.0, 168.0).toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: AftabSpacing.railPadding(width),
            vertical: AftabSpacing.sm,
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(title, style: theme.textTheme.titleLarge),
              ),
              if (onSeeAll != null)
                TextButton(
                  onPressed: onSeeAll,
                  child: Text(s.seeAll),
                ),
            ],
          ),
        ),
        SizedBox(
          height: cardHeight,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(
              horizontal: AftabSpacing.railPadding(width),
            ),
            itemCount: loading ? 6 : items.length,
            separatorBuilder: (_, __) => const SizedBox(width: AftabSpacing.sm),
            itemBuilder: (context, i) {
              if (loading) {
                return SizedBox(
                  width: cardWidth,
                  child: const SkeletonBox(borderRadius: AftabRadius.md),
                );
              }
              final item = items[i];
              return SizedBox(
                width: cardWidth,
                child: PosterCard(
                  item: item,
                  onTap: () => onOpenItem(item),
                  compact: true,
                  progressFraction: progressOf?.call(item),
                  focusMode: tvFocus ? CardFocusMode.tv : CardFocusMode.none,
                  autofocus: autofocusFirst && i == 0,
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
