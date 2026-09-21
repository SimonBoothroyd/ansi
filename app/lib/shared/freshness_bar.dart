/// The three-stop freshness gradient as a small bar: fresh → aging → gone.
/// The legend for the week's shelf-life painter.
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
