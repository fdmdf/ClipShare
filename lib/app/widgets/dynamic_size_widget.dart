import 'dart:math';

import 'package:flutter/material.dart';

class DynamicSizeWidget extends StatelessWidget {
  final double? widthScale;
  final double? heightScale;
  final double? maxWidth;
  final double? maxHeight;
  final Widget child;
  final double? ratio;

  const DynamicSizeWidget({
    super.key,
    this.widthScale,
    this.heightScale,
    this.maxHeight,
    this.maxWidth,
    this.ratio,
    required this.child,
  })  : assert((widthScale ?? 0) <= 1),
        assert((heightScale ?? 0) <= 1);

  double calcWidth(double screenWidth) {
    const double defaultMaxWidth = 350;
    if (maxWidth == null && maxHeight == null) {
      return defaultMaxWidth;
    }
    if (maxWidth == null) {
      return min(defaultMaxWidth, widthScale! * screenWidth);
    }
    if (widthScale == null) {
      return defaultMaxWidth;
    }
    return min(maxWidth!, widthScale! * screenWidth);
  }

  double calcHeight(double screenHeight) {
    const defaultMaxHeight = 350 * 1.618;
    final scale = heightScale ?? 0.8;
    if (maxHeight == null && heightScale == null) {
      if (screenHeight <= defaultMaxHeight) {
        return screenHeight * scale;
      }
      return defaultMaxHeight;
    }
    if (maxHeight == null) {
      return min(defaultMaxHeight, scale * screenHeight);
    }
    return min(maxHeight! * (ratio ?? 1), scale * screenHeight);
  }

  @override
  Widget build(BuildContext context) {
    var h = MediaQuery.of(context).size.height;
    var w = MediaQuery.of(context).size.width;
    return Center(
      child: Container(
        constraints: BoxConstraints(
          maxWidth: calcWidth(w),
          maxHeight: calcHeight(h),
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: Colors.white,
        ),
        child: child,
      ),
    );
  }
}
