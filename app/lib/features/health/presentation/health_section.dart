/// Account's Health Connect section, on Android only: one switch, the meals
/// that cannot be sent, and — while off — the door to Health Connect's own
/// page for Ansi, where what was sent can be deleted.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../data/health_providers.dart';
import '../domain/health_gateway.dart';
import 'health_sync.dart';

/// A row's words: the page's own sans, not the list's default.
final _row = ansiSans(size: 14);

class HealthSection extends ConsumerWidget {
  const HealthSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(healthIsSupportedProvider)) return const SizedBox.shrink();
    final availability = ref.watch(healthAvailabilityProvider).asData?.value;
    if (availability == null) return const SizedBox.shrink();
    final on = ref.watch(healthEnabledProvider).asData?.value ?? false;
    // Why the last pass did not reach Health Connect, if it did not.
    final problem = on ? ref.watch(healthSyncRunnerProvider) : null;
    final notSent = on
        ? ref.watch(healthMealsProvider)?.notSent ?? const <String>[]
        : const <String>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FItemGroup(
          children: [
            if (availability != HealthAvailability.available)
              FItem(
                title: Text(
                  availability == HealthAvailability.needsUpdate
                      ? 'Health Connect needs an update'
                      : 'Health Connect isn’t on this phone',
                  style: ansiSans(size: 14, color: AnsiColors.muted),
                ),
              )
            else ...[
              FItem(
                title: Text('Send my meals', style: _row),
                suffix: FSwitch(
                  semanticsLabel: 'Send my meals to Health Connect',
                  value: on,
                  onChange: (v) => unawaited(
                    ref.read(healthEnabledProvider.notifier).set(on: v),
                  ),
                ),
              ),
              if (problem != null)
                FItem(
                  title: Text(
                    problem,
                    style: ansiSans(size: 14, color: AnsiColors.cautionInk),
                  ),
                  suffix: Text(
                    'Try again ›',
                    style: ansiSans(size: 13, color: AnsiColors.herbDeep),
                  ),
                  onPress: () => ref.invalidate(healthSyncRunnerProvider),
                ),
              for (final title in notSent)
                FItem(
                  title: Text(
                    '$title has no macros',
                    style: ansiSans(size: 14, color: AnsiColors.cautionInk),
                  ),
                ),
              if (!on)
                FItem(
                  title: Text('Manage in Health Connect', style: _row),
                  suffix: const Icon(FLucideIcons.chevronRight),
                  onPress: () =>
                      unawaited(ref.read(healthGatewayProvider).openSettings()),
                ),
            ],
          ],
        ),
      ],
    );
  }
}
