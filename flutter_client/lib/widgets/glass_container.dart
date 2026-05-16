import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/vscode_colors.dart';

class GlassContainer extends StatelessWidget {
  final Widget child;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final BorderRadius? borderRadius;
  final double blur;
  final double opacity;
  final Color? color;
  final BoxBorder? border;

  const GlassContainer({
    super.key,
    required this.child,
    this.width,
    this.height,
    this.padding,
    this.margin,
    this.borderRadius,
    this.blur = VSCodeColors.glassBlur,
    this.opacity = VSCodeColors.glassOpacity,
    this.color,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effectiveBorderRadius = borderRadius ?? BorderRadius.circular(12);
    final bgColor = (color ?? theme.colorScheme.surfaceContainerHighest)
        .withOpacity(opacity);
    final effectiveBorder = border ?? Border.all(
      color: theme.dividerColor.withOpacity(0.3),
      width: 0.5,
    );

    return ClipRRect(
      borderRadius: effectiveBorderRadius,
      child: Container(
        width: width,
        height: height,
        margin: margin,
        child: Stack(
          children: [
            // blur effect
            BackdropFilter(
              filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
              child: Container(
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: effectiveBorderRadius,
                  border: effectiveBorder,
                ),
              ),
            ),
            // content
            Padding(
              padding: padding ?? EdgeInsets.zero,
              child: child,
            ),
          ],
        ),
      ),
    );
  }
}
