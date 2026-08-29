/// The shared picker-sheet shell (step 7.7): one selection anatomy for the
/// ingredient and recipe pickers — sheet chrome, a close affordance, a
/// TOP-anchored search field (Simon's frame review kept search at the top,
/// like the shipped pickers), a slot for source tabs / context strips above
/// the list, and a footer slot (add-new, the eating footer).
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../core/theme/mise_theme.dart';
import '../core/theme/mise_tokens.dart';

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
    return Container(
      height: MediaQuery.sizeOf(context).height * heightFactor,
      decoration: const BoxDecoration(
        color: MiseColors.paper,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(top: BorderSide(color: MiseColors.line)),
      ),
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 12,
          // Clear the keyboard (viewInsets) OR the home indicator (safe-area
          // padding) — whichever is present.
          bottom:
              math.max(
                MediaQuery.viewInsetsOf(context).bottom,
                MediaQuery.paddingOf(context).bottom,
              ) +
              12,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.of(context).pop(),
                  child: const Icon(FLucideIcons.x, size: 22),
                ),
                Expanded(
                  child: Text(
                    title,
                    textAlign: TextAlign.center,
                    style: miseSerif(size: 20),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 22),
              ],
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: miseMono(size: 11, color: MiseColors.muted),
              ),
            ],
            const SizedBox(height: 12),
            FTextField(
              autofocus: searchAutofocus,
              hint: searchHint,
              control: FTextFieldControl.managed(
                onChange: (v) => onQueryChanged(v.text),
              ),
              prefixBuilder: (context, style, _) =>
                  const Icon(FLucideIcons.search),
            ),
            if (aboveList != null) ...[const SizedBox(height: 12), aboveList!],
            const SizedBox(height: 12),
            Expanded(child: body),
            if (footer != null) ...[const SizedBox(height: 8), footer!],
          ],
        ),
      ),
    );
  }
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
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onChanged(i),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
              decoration: BoxDecoration(
                color: index == i ? MiseColors.ink : MiseColors.surface,
                border: Border.all(
                  color: index == i ? MiseColors.ink : MiseColors.line,
                ),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                label,
                style: miseMono(
                  size: 12,
                  color: index == i ? MiseColors.surface : MiseColors.muted,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
