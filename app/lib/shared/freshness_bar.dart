/// The three-stop freshness gradient as a small bar: fresh → aging → gone.
///
/// It is the legend for the week's shelf-life painter, drawn beside a "keeps
/// 4 d" badge so the colours on the week row mean something the first time
/// they are seen. The painter itself draws the scale along a real timeline;
/// this is the same scale with no time in it.
library;

import 'package:flutter/widgets.dart';

import '../core/theme/ansi_tokens.dart';

class FreshnessBar extends StatelessWidget {
  const FreshnessBar({this.width = 22, this.height = 6, super.key});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(3),
      gradient: const LinearGradient(
        colors: [AnsiColors.fresh, AnsiColors.aging, AnsiColors.gone],
      ),
    ),
  );
}
