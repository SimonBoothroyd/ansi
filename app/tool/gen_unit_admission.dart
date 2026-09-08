/// Renders `docs/generated/unit-admission.md` — the unit compatibility table —
/// by running the REAL domain rule over one synthetic ingredient per cell.
///
/// Pure Dart, no Flutter on this path (domain purity invariant 2 is what makes
/// a doc generator possible at all): it reads [allowedUnitsFor],
/// [unitSayableAsDefault], [densityUnlockedUnits] and [kImpreciseCategoryGates]
/// rather than restating them, so the table cannot drift from the code —
/// `scripts/check_docs.sh` regenerates it and diffs.
///
/// `dart run tool/gen_unit_admission.dart <out.md>` — the path defaults to the
/// committed file, and `scripts/gen_docs.sh` passes it explicitly.
library;

import 'dart:io';

import 'package:ansi/core/units/macros.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/ingredients/domain/allowed_units.dart';
import 'package:ansi/features/ingredients/domain/ingredient.dart';

const _generatedHeader =
    '<!-- GENERATED FILE — do not edit. Regenerate with `make docs` '
    '(scripts/gen_docs.sh). -->';

/// The two macro bases a row can carry, with the heading each is printed under.
const _bases = <(MacrosBasis, String)>[
  (MacrosBasis.perG, 'per 100 g'),
  (MacrosBasis.perMl, 'per 100 ml'),
];

/// A bare vocabulary row in the shape one cell asks about: no explicit
/// `allowed_units` list (so the derived rule answers) and no category (so no
/// imprecise word is earned and table 3 owns that axis alone).
Ingredient _row(Unit defaultUnit, MacrosBasis basis, {double? density}) =>
    Ingredient(
      id: 'generated',
      canonicalName: 'row',
      defaultUnit: defaultUnit,
      status: IngredientStatus.complete,
      densityGPerMl: density,
      macrosBasis: basis,
    );

/// Unit labels joined in chip order, the row's own default emphasized.
String _labels(Iterable<Unit> units, Unit defaultUnit) =>
    units.map((u) => u == defaultUnit ? '**${u.label}**' : u.label).join(' · ');

/// One cell of table 1: what the row admits with no density stored.
String _plainCell(Unit defaultUnit, MacrosBasis basis) {
  final row = _row(defaultUnit, basis);
  if (!unitSayableAsDefault(row, defaultUnit)) {
    return '— (default needs a density)';
  }
  return _labels(allowedUnitsFor(row), defaultUnit);
}

/// One cell of table 2: what survives a density deletion, then `+` what the
/// density itself buys. Both halves stay in chip order, so the bold default
/// can sit in either — a stranded default (table 1's `—`) sits in the second.
String _densityCell(Unit defaultUnit, MacrosBasis basis) {
  final row = _row(defaultUnit, basis, density: 1);
  final unlocked = densityUnlockedUnits(row);
  final admitted = allowedUnitsFor(row);
  final kept = admitted.where((u) => !unlocked.contains(u));
  final added = admitted.where(unlocked.contains);
  final left = kept.isEmpty ? '—' : _labels(kept, defaultUnit);
  return added.isEmpty ? left : '$left + ${_labels(added, defaultUnit)}';
}

/// Tables 1 and 2: one row per possible default unit ([batches] excepted — a
/// batch is a component-line denomination, never an ingredient's unit), one
/// column per macro basis, each cell rendered by [cell].
List<String> _admissionTable(
  String Function(Unit defaultUnit, MacrosBasis basis) cell,
) {
  final rows = <String>[
    '| Default unit | ${_bases.map((b) => b.$2).join(' | ')} |',
    '|---|${'---|' * _bases.length}',
  ];
  for (final unit in kAllUnits) {
    if (unit.family == UnitFamily.batch) continue;
    final cells = _bases.map((b) => cell(unit, b.$1)).join(' | ');
    rows.add('| `${unit.label}` | $cells |');
  }
  return rows;
}

/// Table 3: the per-word category gates, read straight off
/// [kImpreciseCategoryGates] — categories are the union of its values, so a
/// category that earns no word never appears.
List<String> _impreciseTable() {
  final words = kImpreciseCategoryGates.keys.toList();
  final categories = {
    for (final gate in kImpreciseCategoryGates.values) ...gate,
  }.toList()..sort();
  final rows = <String>[
    '| Category | ${words.map((w) => w.label).join(' | ')} |',
    '|---|${'---|' * words.length}',
  ];
  for (final category in categories) {
    final ticks = words
        .map((w) => kImpreciseCategoryGates[w]!.contains(category) ? '✓' : '—')
        .join(' | ');
    rows.add('| `$category` | $ticks |');
  }
  return rows;
}

void main(List<String> args) {
  final out = File(
    args.isEmpty ? 'docs/generated/unit-admission.md' : args.first,
  );
  // Prose is emitted pre-wrapped, one source line per rendered line, to match
  // the ~80-column markdown the rest of the knowledge base is written in.
  final lines = <String>[
    _generatedHeader,
    '# Unit admission — what a line may be said in (generated)',
    '',
    'Which units a recipe line or a shopping top-up may be denominated in, for',
    'every default unit the catalog offers and both macro bases. Each cell is',
    'the real domain rule run over a bare vocabulary row — no explicit per-row',
    '`allowed_units` list and no category — so it is what `allowedUnitsFor`',
    'actually returns, in the chip order the pickers draw, rather than a',
    'restatement of the rule.',
    '',
    'The rule lives in `app/lib/features/ingredients/domain/allowed_units.dart`',
    'and is mirrored in SQL by `default_allowed_units()`, which stamps the',
    'stored list on insert. It was decided by',
    '[ADR-0008](../decisions/0008-unit-admission-model.md) (the model),',
    '[ADR-0009](../decisions/0009-density-unlocks-both-families.md) (a density',
    'unlocks the other family whatever the default unit is),',
    '[ADR-0010](../decisions/0010-piece-is-an-admission-fact.md) (`piece` is',
    'curated, never inferred) and',
    '[ADR-0014](../decisions/0014-all-to-all-admission.md) (all to all — a',
    'family is admitted whole and the household prunes per row).',
    '',
    '## 1. No density stored',
    '',
    'The common case: a row with macros and no density. A cell reading `—',
    '(default needs a density)` is a shape the app refuses to store — the',
    'default unit sits on the far side of the basis family with nothing to',
    'bridge it, so the form flags it and Save offers `g`/`ml` instead.',
    '',
    ..._admissionTable(_plainCell),
    '',
    '## 2. With a density stored',
    '',
    'The same rows once a `density_g_per_ml` is known. Each cell reads **what',
    'survives the density being deleted** `+` **what the density buys** — the',
    'second half is `densityUnlockedUnits`, which is exactly what deleting the',
    'number takes back. Both halves are in chip order, so a default that was',
    'stranded in table 1 appears in the second half.',
    '',
    ..._admissionTable(_densityCell),
    '',
    '## 3. Imprecise words, by category',
    '',
    'The tables above use a row with no category, so they show no imprecise',
    'word except an imprecise default keeping its own. The words are gated per',
    "WORD by the row's category — greens earn `handful` without earning",
    '`pinch` — and a category absent from this table earns none of them. (The',
    'import amount editor admits `to taste` on top of this for any food:',
    '"plus more, to serve" is legitimately imprecise whatever the ingredient.)',
    '',
    ..._impreciseTable(),
    '',
    '## How to read it',
    '',
    '- **Order is meaning.** The default unit is fronted, then the rest of its',
    '  family in kitchen order, then `piece`, then the demoted other',
    '  mass/volume family (reachable, never fronted — "g of milk" is doable but',
    '  strange), then the imprecise words last.',
    '- **The basis family is unconditional, and whole.** A per-100 g row can',
    '  always say every weight, a per-100 ml row every volume — the canonical',
    '  dimension needs no density, and a family is admitted whole or not at',
    '  all.',
    '- **The user prunes, not the rule.** These are the units a row is created',
    '  with; a household that will never say a litre of yeast turns that chip',
    "  off on the row itself, in the flesh-out form's admission section.",
    '- **A stored list overrides all of this, per row.** A household that',
    "  curates a row's chips owns them, and this table is the fallback for a",
    '  row carrying no list. The one thing an explicit list cannot do is make',
    '  a unit sayable that no density supports — that half is subtracted while',
    '  the number is missing.',
    '',
  ];
  out.writeAsStringSync('${lines.join('\n').trimRight()}\n');
  stdout.writeln(
    'gen_unit_admission: wrote ${out.path} '
    '(${kAllUnits.where((u) => u.family != UnitFamily.batch).length} default '
    'units × ${_bases.length} bases)',
  );
}
