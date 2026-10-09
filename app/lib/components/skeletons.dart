/// Loading skeletons: soft pulsing placeholders that make waiting feel
/// intentional. Motion collapses to a static tint when the user asked the
/// OS for reduced motion.

library aftab_skeletons;

import 'package:flutter/material.dart';

import '../design/tokens.dart';

class SkeletonBox extends StatefulWidget {
  const SkeletonBox({
    super.key,
    this.width,
    this.height,
    this.borderRadius = AftabRadius.sm,
    this.aspectRatio,
  });

  final double? width;
  final double? height;
  final double borderRadius;
  final double? aspectRatio;

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  // MediaQuery (reduced motion) can only be read from
  // didChangeDependencies, never initState.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = AftabMotion.reducedMotion(context);
    if (reduced) {
      if (_controller.isAnimating) _controller.stop();
    } else {
      if (!_controller.isAnimating) _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base = scheme.surfaceContainerHigh;
    final highlight = scheme.surfaceContainerHighest;
    Widget box;
    if (widget.aspectRatio != null) {
      box = AspectRatio(aspectRatio: widget.aspectRatio!);
    } else {
      box = SizedBox(
        width: widget.width,
        height: widget.height,
        child: const SizedBox.expand(),
      );
    }
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => DecoratedBox(
          decoration: BoxDecoration(
            color: Color.lerp(base, highlight, _controller.value),
            borderRadius: BorderRadius.circular(widget.borderRadius),
          ),
          child: box,
        ),
      ),
    );
  }
}

/// A poster-shaped grid of skeletons matching [columns] across.
class SkeletonPosterGrid extends StatelessWidget {
  const SkeletonPosterGrid({
    super.key,
    required this.itemCount,
    this.maxCrossAxisExtent = 180,
  });

  final int itemCount;
  final double maxCrossAxisExtent;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: EdgeInsets.symmetric(
        horizontal: AftabSpacing.screenPadding(MediaQuery.sizeOf(context).width),
        vertical: AftabSpacing.md,
      ),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: maxCrossAxisExtent,
        childAspectRatio: 0.62,
        mainAxisSpacing: AftabSpacing.md,
        crossAxisSpacing: AftabSpacing.md,
      ),
      itemCount: itemCount,
      itemBuilder: (context, _) => const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(child: SkeletonBox(borderRadius: AftabRadius.md)),
          SizedBox(height: AftabSpacing.sm),
          SkeletonBox(height: 14),
          SizedBox(height: AftabSpacing.xs),
          SkeletonBox(width: 60, height: 12),
        ],
      ),
    );
  }
}

/// A horizontal rail of poster skeletons.
class SkeletonRail extends StatelessWidget {
  const SkeletonRail({super.key});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return SizedBox(
      height: 240,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(
          horizontal: AftabSpacing.railPadding(width),
        ),
        children: <Widget>[
          for (var i = 0; i < 6; i++)
            const Padding(
              padding: EdgeInsetsDirectional.only(end: AftabSpacing.sm),
              child: SizedBox(
                width: 128,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Expanded(child: SkeletonBox(borderRadius: AftabRadius.md)),
                    SizedBox(height: AftabSpacing.sm),
                    SkeletonBox(height: 14),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
