import 'package:flutter/material.dart';

/// AusHD Player brand mark.
///
/// The vector source is `assets/brand/aushd-logo.svg`; this widget renders the
/// exported high-resolution PNG so the mark stays crisp at any size. The
/// constructor signature is kept for compatibility with existing call sites.
class ZerkLogo extends StatelessWidget {
  const ZerkLogo({
    super.key,
    this.size = 48,
    this.tile = true,
    this.color = Colors.white,
  });

  final double size;
  final bool tile;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/brand/aushd-mark.png',
      width: size,
      height: size,
      filterQuality: FilterQuality.high,
      semanticLabel: 'AusHD Player',
    );
  }
}
