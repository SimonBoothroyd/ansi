/// The two-way switch on a fractional cook session: the exact scale or the
/// whole batch. Display only: the shopping list buys the exact scale either
/// way.
library;

import 'package:flutter/widgets.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';

class WholeBatchSwitch extends StatelessWidget {
  const WholeBatchSwitch({
    required this.exact,
    required this.whole,
    required this.wholeShown,
    required this.onChanged,
    this.dense = false,
    super.key,
  });

  /// `×0.44 exact`.
  final String exact;

  /// `×1 whole batch`.
  final String whole;

  /// Which side is on.
  final bool wholeShown;

  /// Called with true for the whole batch, false for the exact scale.
  final ValueChanged<bool> onChanged;

  /// The wide sheet's smaller type.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    Widget side(String label, {required bool on, required bool isWhole}) =>
        Expanded(
          child: Semantics(
            button: true,
            selected: on,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onChanged(isWhole),
              child: Container(
                padding: EdgeInsets.symmetric(
                  vertical: dense ? 5 : 7,
                  horizontal: 4,
                ),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: on ? AnsiColors.surface : null,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: on
                      ? const [
                          BoxShadow(
                            color: Color(0x1418211C),
                            offset: Offset(0, 1),
                            blurRadius: 2,
                          ),
                        ]
                      : null,
                ),
                child: Text(
                  label,
                  maxLines: 1,
                  textAlign: TextAlign.center,
                  style: ansiMono(
                    size: dense ? 9.5 : 10.5,
                    color: on ? AnsiColors.ink : AnsiColors.muted,
                    weight: on ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            ),
          ),
        );

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AnsiColors.paper,
        border: Border.all(color: AnsiColors.line),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Row(
        children: [
          side(exact, on: !wholeShown, isWhole: false),
          side(whole, on: wholeShown, isWhole: true),
        ],
      ),
    );
  }
}
