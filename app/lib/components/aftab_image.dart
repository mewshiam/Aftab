/// [AftabImage]: artwork with placeholder, disk-cached loading and a
/// graceful fallback — the only way screens display remote images.

library aftab_aftab_image;

import 'dart:io';

import 'package:flutter/material.dart';

import '../design/tokens.dart';
import 'image_cache.dart';
import 'skeletons.dart';

class AftabImage extends StatefulWidget {
  const AftabImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.fallbackIcon = Icons.image_outlined,
    this.semanticLabel,
    this.borderRadius = 0,
  });

  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final IconData fallbackIcon;
  final String? semanticLabel;
  final double borderRadius;

  @override
  State<AftabImage> createState() => _AftabImageState();
}

class _AftabImageState extends State<AftabImage> {
  Future<File?>? _future;

  @override
  void initState() {
    super.initState();
    _future = AftabImageCache.instance.load(widget.url);
  }

  @override
  void didUpdateWidget(AftabImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _future = AftabImageCache.instance.load(widget.url);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget child;
    if (widget.url.isEmpty) {
      child = _fallback(scheme);
    } else {
      child = FutureBuilder<File?>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return SkeletonBox(
              width: widget.width,
              height: widget.height,
              borderRadius: widget.borderRadius,
            );
          }
          final file = snapshot.data;
          if (file == null) return _fallback(scheme);
          final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0;
          final cacheWidth = widget.width == null
              ? null
              : (widget.width! * dpr).round();
          final image = Image.file(
            file,
            width: widget.width,
            height: widget.height,
            fit: widget.fit,
            cacheWidth: cacheWidth,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) => _fallback(scheme),
          );
          return snapshot.hasData
              ? _fadeIn(child: image)
              : _fallback(scheme);
        },
      );
    }
    if (widget.borderRadius > 0) {
      child = ClipRRect(
        borderRadius: BorderRadius.circular(widget.borderRadius),
        child: child,
      );
    }
    if (widget.semanticLabel != null) {
      child = Semantics(label: widget.semanticLabel, image: true, child: child);
    }
    return SizedBox(width: widget.width, height: widget.height, child: child);
  }

  Widget _fadeIn({required Widget child}) {
    if (AftabMotion.reducedMotion(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: AftabMotion.fast,
      curve: AftabMotion.standard,
      child: child,
      builder: (context, opacity, built) =>
          Opacity(opacity: opacity, child: built),
    );
  }

  Widget _fallback(ColorScheme scheme) {
    return ColoredBox(
      color: scheme.surfaceContainerHigh,
      child: Center(
        child: Icon(
          widget.fallbackIcon,
          size: 32,
          color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
        ),
      ),
    );
  }
}
