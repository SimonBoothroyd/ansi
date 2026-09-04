/// One selection anatomy for the ingredient and recipe pickers: an
/// [AnsiSheetShell] with a TOP-anchored search field, a slot for source tabs /
/// context strips above the list, and a footer slot (add-new, the eating
/// footer).
library;

import 'package:flutter/widgets.dart';

import '../core/theme/ansi_theme.dart';
import '../core/theme/ansi_tokens.dart';
import 'ansi_chip.dart';
import 'ansi_search_field.dart';
import 'ansi_sheet_shell.dart';

class PickerShell extends StatelessWidget {
  const PickerShell({
    required this.title,
    required this.searchHint,
    required this.onQueryChanged,
    required this.body,
    this.subtitle,
    this.aboveList,
    this.footer,
    this.heightFactor = 0.86,
    this.searchAutofocus = false,
    super.key,
  });

  /// The sheet's centered serif title.
  final String title;

  /// Mono context line under the title ("to · Wednesday, Dinner").
  final String? subtitle;

  final String searchHint;
  final ValueChanged<String> onQueryChanged;
  final bool searchAutofocus;

  /// Rendered between the search field and the list (source tabs, the
  /// already-this-week strip).
  final Widget? aboveList;

  /// The scrolling result area (gets the remaining height).
  final Widget body;

  /// Pinned under the list (add-new affordance, eating footer).
  final Widget? footer;

  final double heightFactor;

  @override
  Widget build(BuildContext context) {
    return AnsiSheetShell(
      title: title,
      subtitle: subtitle,
      heightFactor: heightFactor,
      children: [
        const SizedBox(height: 12),
        AnsiSearchField(
          autofocus: searchAutofocus,
          hint: searchHint,
          onChanged: onQueryChanged,
        ),
        if (aboveList != null) ...[const SizedBox(height: 12), aboveList!],
        const SizedBox(height: 12),
        Expanded(child: body),
        if (footer != null) ...[const SizedBox(height: 8), footer!],
      ],
    );
  }
}

/// The `DID YOU MEAN` band header — the pickers' own section-header idiom, in
/// the caution colour, so a guessed row can never be read as a found one.
///
/// One header for all three pickers: whatever the corpus, a guess is labelled
/// the same way. It appears only when NOTHING was spelled right, so the band
/// it opens is the whole list rather than a tail under real hits.
class DidYouMeanHeader extends StatelessWidget {
  const DidYouMeanHeader({super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Text('DID YOU MEAN', style: ansiLabel(color: AnsiColors.aging)),
  );
}

/// The pill tab row both pickers share (Recent / Books / Favorites…).
class PickerTabs extends StatelessWidget {
  const PickerTabs({
    required this.labels,
    required this.index,
    required this.onChanged,
    super.key,
  });

  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final (i, label) in labels.indexed) ...[
          if (i > 0) const SizedBox(width: 8),
          AnsiChip(
            label: label,
            selected: index == i,
            onTap: () => onChanged(i),
            tone: AnsiChipTone.ink,
            mono: true,
          ),
        ],
      ],
    );
  }
}
