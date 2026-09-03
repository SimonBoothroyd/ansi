/// The one thing a screen shows when the data it needs did not arrive.
///
/// It replaces six copies of the same shrug — *"Could not load the library."*,
/// *"Could not load the week."*, and four more — each of which threw the
/// exception it had been handed into a `debugPrint` and offered the user no
/// reason and no way out.
///
/// Three things, in this order, because that is the order a person asks them
/// in: **what** didn't load, **why**, and **what now**.
///
///     Couldn’t load the week.
///     couldn’t reach the server
///     [Try again]  [Copy details]
///
/// The reason is a mapped sentence (`describe_failure.dart`), never a raw
/// `toString()`; the raw text lives behind Copy details.
library;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../core/theme/ansi_theme.dart';
import '../core/theme/ansi_tokens.dart';
import 'describe_failure.dart';

class AnsiErrorState extends StatelessWidget {
  const AnsiErrorState({
    required this.what,
    required this.error,
    this.stackTrace,
    this.onRetry,
    this.compact = false,
    super.key,
  });

  /// The thing that didn't load, as the user would name it: "the week", "this
  /// recipe", "what this is used in".
  final String what;
  final Object error;
  final StackTrace? stackTrace;

  /// Usually `() => ref.invalidate(theProvider)`. Absent only where retrying
  /// genuinely cannot help.
  final VoidCallback? onRetry;

  /// A one-line form for a chip row or an inline slot, where a centred block
  /// would be heavier than the thing it is reporting on.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final reason = describeFailure(error);
    if (compact) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            FLucideIcons.circleAlert,
            size: 13,
            color: AnsiColors.gone,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              'Couldn’t load $what — $reason',
              style: ansiMono(size: 11, color: AnsiColors.gone),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(width: 8),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onRetry,
              child: Text(
                'Try again',
                style: ansiMono(size: 11, color: AnsiColors.herbDeep),
              ),
            ),
          ],
        ],
      );
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Couldn’t load $what.',
              textAlign: TextAlign.center,
              style: ansiSerif(size: 18),
            ),
            const SizedBox(height: 8),
            Text(
              reason,
              textAlign: TextAlign.center,
              style: ansiMono(size: 11.5, color: AnsiColors.muted),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (onRetry != null) ...[
                  FButton(
                    size: FButtonSizeVariant.sm,
                    variant: FButtonVariant.outline,
                    onPress: onRetry,
                    child: const Text('Try again'),
                  ),
                  const SizedBox(width: 10),
                ],
                FButton(
                  size: FButtonSizeVariant.sm,
                  variant: FButtonVariant.ghost,
                  onPress: () => Clipboard.setData(
                    ClipboardData(text: failureDetails(error, stackTrace)),
                  ),
                  child: const Text('Copy details'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
