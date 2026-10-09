/// Unmistakable focus treatment for the 10-foot UI: scale + primary
/// border + glow. Applied to cards, buttons and tiles when the form
/// factor is TV.

library aftab_tv_focus;

import 'package:flutter/material.dart';

import '../design/tokens.dart';

/// Wraps [child] with remote-friendly focus visuals and an activate
/// action.
class TvFocusable extends StatefulWidget {
  const TvFocusable({
    super.key,
    required this.child,
    this.onActivate,
    this.autofocus = false,
    this.borderRadius = AftabRadius.md,
    this.scale = 1.05,
  });

  final Widget child;
  final VoidCallback? onActivate;
  final bool autofocus;
  final double borderRadius;
  final double scale;

  @override
  State<TvFocusable> createState() => _TvFocusableState();
}

class _TvFocusableState extends State<TvFocusable> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FocusableActionDetector(
      autofocus: widget.autofocus,
      mouseCursor: SystemMouseCursors.click,
      actions: <Type, Action<Intent>>{
        if (widget.onActivate != null)
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onActivate!();
              return null;
            },
          ),
      },
      onFocusChange: (focused) => setState(() => _focused = focused),
      child: AnimatedScale(
        scale: _focused ? widget.scale : 1.0,
        duration: AftabMotion.maybe(AftabMotion.fast, context),
        curve: AftabMotion.standard,
        child: AnimatedContainer(
          duration: AftabMotion.maybe(AftabMotion.fast, context),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            border: _focused
                ? Border.all(color: scheme.primary, width: 3)
                : null,
            boxShadow: _focused
                ? <BoxShadow>[
                    BoxShadow(
                      color: scheme.primary.withValues(alpha: 0.25),
                      blurRadius: 18,
                      spreadRadius: 2,
                    ),
                  ]
                : null,
          ),
          child: widget.child,
        ),
      ),
    );
  }
}
