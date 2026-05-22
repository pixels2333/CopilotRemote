import 'package:flutter/material.dart';

/// A widget that clips its child with an inverted (concave) bottom edge,
/// designed to visually complement a rounded rectangle below it.
class ConcaveBottomContainer extends StatelessWidget {
  final Widget child;
  final double radius;
  final double? width;
  final double? height;

  const ConcaveBottomContainer({
    super.key,
    required this.child,
    this.radius = 14.0,
    this.width,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: ClipPath(
        clipper: _ConcaveBottomClipper(radius: radius),
        child: child,
      ),
    );
  }
}

class _ConcaveBottomClipper extends CustomClipper<Path> {
  final double radius;

  const _ConcaveBottomClipper({this.radius = 14.0});

  @override
  Path getClip(Size size) {
    final r = radius;
    return Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..arcToPoint(
        Offset(size.width - r, size.height - r),
        radius: Radius.circular(r),
        clockwise: false,
      )
      ..lineTo(r, size.height - r)
      ..arcToPoint(
        Offset(0, size.height),
        radius: Radius.circular(r),
        clockwise: false,
      )
      ..close();
  }

  @override
  bool shouldReclip(covariant _ConcaveBottomClipper oldClipper) =>
      oldClipper.radius != radius;
}