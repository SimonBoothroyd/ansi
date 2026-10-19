/// The proposal card: every row a change Ansi proposes would write, and the
/// one Confirm that writes it.
///
/// Nothing is written before Confirm, and Confirm is one write through the
/// repositories (ADR-0011). A meal edited after the card was drawn refuses the
/// whole change ([PlanChangedError]); Ansi is told, and reads the week again.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../shared/write.dart';
import '../../planning/data/planning_providers.dart';
import '../../planning/domain/plan_change.dart';
import '../../planning/presentation/week_view_models.dart';
import '../../shopping/data/shopping_providers.dart';
import '../domain/ask_proposal.dart';
import 'ask_controller.dart';

class AskCard extends HookConsumerWidget {
  const AskCard({required this.proposal, super.key});

  final AskProposal proposal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final writing = useState(false);

    Future<void> confirm() async {
      writing.value = true;
      // Captured before the await: the card is gone once the decision lands.
      final container = ProviderScope.containerOf(context, listen: false);
      final controller = container.read(askControllerProvider.notifier);
      final decision = await ref.write(
        context,
        'make that change',
        () async {
          switch (proposal) {
            case AskPlanProposal(:final changes):
              try {
                await container
                    .read(planningRepositoryProvider)
                    .applyPlanChanges(changes);
              } on PlanChangedError {
                // Moved underneath the card: Ansi is told, not the toast.
                return AskDecision.changed;
              }
            case AskCopyWeekProposal(:final weekStart):
              final result = await container
                  .read(planningRepositoryProvider)
                  .copyLastWeek(weekStart);
              // The Week names the variants a copy left behind, as its own
              // copy does.
              container
                  .read(lastCopyReportProvider.notifier)
                  .record(weekStart, result);
            case AskTopUpProposal(
              :final weekStart,
              :final ingredientId?,
              :final quantity?,
              :final unit?,
            ):
              await container
                  .read(shoppingRepositoryProvider)
                  .addTopUp(
                    ingredientId: ingredientId,
                    quantity: quantity,
                    unit: unit,
                    weekStart: weekStart,
                  );
            case AskTopUpProposal(:final weekStart, :final item):
              await container
                  .read(shoppingRepositoryProvider)
                  .addFreeTextItem(text: item!, weekStart: weekStart);
          }
          return AskDecision.confirmed;
        },
        // Ansi is told the outcome at once; it proposes again if asked.
        retryable: false,
      );
      controller.decide(decision ?? AskDecision.failed);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(13, 11, 13, 12),
      decoration: BoxDecoration(
        color: AnsiColors.paper,
        border: Border.all(color: AnsiColors.line),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            proposal.title,
            style: ansiSans(size: 14, weight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          for (final row in proposal.rows) _Row(row: row),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              FButton(
                variant: FButtonVariant.outline,
                size: FButtonSizeVariant.sm,
                onPress: writing.value
                    ? null
                    : () => ref
                          .read(askControllerProvider.notifier)
                          .decide(AskDecision.cancelled),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              FButton(
                size: FButtonSizeVariant.sm,
                onPress: writing.value ? null : confirm,
                child: const Text('Confirm'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.row});

  final AskProposalRow row;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (row.when.isNotEmpty)
          Text(row.when, style: ansiMono(size: 10.5, color: AnsiColors.muted)),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(text: row.what),
              if (row.note != null)
                TextSpan(
                  text: ' · ${row.note}',
                  style: ansiMono(size: 11, color: AnsiColors.herb),
                ),
            ],
          ),
          style: ansiSans(size: 14),
        ),
      ],
    ),
  );
}
