/// A shared recipe's public page, as HTML and as schema.org JSON-LD (pure
/// Dart, compiled to JS).
///
/// One renderer serves both ends. The server renders the whole document at
/// the recipe's own servings, so the JSON-LD and a link preview are in the
/// served HTML; the browser re-renders [renderShareBody] when the stepper
/// moves. The amounts, the scaling and the macros are the app's own
/// ([amountOfLine], [scaleGroups], [foldMethod], [summarizeRecipeMacros]), so
/// the page cannot disagree with the recipe page about a number.
///
/// The page is read by strangers, so it says what a cook needs and nothing of
/// the household's bookkeeping: no cost, no stub wording, no book.
library;

// The adjacent strings here are markup joined into one document, not prose a
// missing space would run together.
// ignore_for_file: missing_whitespace_between_adjacent_strings

import 'dart:convert';

import '../../../core/units/number_format.dart';
import '../../ingredients/presentation/macros_format.dart';
import '../../recipes/domain/line_display.dart';
import '../../recipes/domain/method_step.dart';
import '../../recipes/domain/recipe.dart';
import '../../recipes/domain/recipe_macros.dart';
import '../../recipes/domain/scaling.dart';
import '../../timers/domain/cook_timer.dart';
import 'share_payload.dart';

// Escapes `&`, `<`, `>` and `"`, and leaves a slash alone, so a URL in an
// attribute stays a URL.
const _escape = HtmlEscape(HtmlEscapeMode.attribute);

String _h(String text) => _escape.convert(text);

/// The whole document for [tree] at its own servings.
///
/// [url] is the link itself, for the canonical and preview tags. [bundleUrl]
/// is the compiled script that runs the stepper and the timers; [payloadJson]
/// is the payload it re-renders from, embedded as data.
String renderSharePage(
  ShareTree tree, {
  required String url,
  required String bundleUrl,
  required String payloadJson,
}) {
  final root = tree.root;
  final description = _description(root);
  return '<!doctype html>\n'
      '<html lang="en"><head>'
      '<meta charset="utf-8">'
      '<meta name="viewport" content="width=device-width, initial-scale=1">'
      '<title>${_h(root.title)}</title>'
      '<meta name="robots" content="noindex">'
      '<meta name="description" content="${_h(description)}">'
      '<meta property="og:type" content="article">'
      '<meta property="og:title" content="${_h(root.title)}">'
      '<meta property="og:description" content="${_h(description)}">'
      '<meta property="og:url" content="${_h(url)}">'
      '<link rel="canonical" href="${_h(url)}">'
      '<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>'
      '<link rel="stylesheet" href="$_fonts">'
      '<script type="application/ld+json">'
      '${_scriptSafe(jsonEncode(shareJsonLd(tree, url: url)))}'
      '</script>'
      '<style>$_css</style>'
      '</head><body>'
      '<main id="ansi-share">${renderShareBody(tree, root.servingsBase)}</main>'
      '<footer>Shared from Ansi, a recipe app for one household. '
      'Use Ansi? Paste this link into Import.</footer>'
      '<script id="ansi-share-data" type="application/json">'
      '${_scriptSafe(payloadJson)}</script>'
      '<script src="${_h(bundleUrl)}" defer></script>'
      '</body></html>';
}

/// The page's body for [tree] at [servings]: the recipe, then each component
/// it reaches as written.
String renderShareBody(ShareTree tree, double servings) {
  final root = tree.root;
  final factor = scaleFactorFor(root, servings);
  final out = StringBuffer()
    ..write('<article class="recipe">')
    ..write('<h1>${_h(root.title)}</h1>')
    ..write(_facts(root))
    ..write(_scaler(servings))
    ..write(
      _ingredients(scaleGroups(root, servings), tree, heading: 'Ingredients'),
    )
    ..write(_macros(root.macros))
    ..write(_method(root, factor))
    ..write('</article>');
  for (final component in tree.components) {
    out
      ..write('<section class="component" id="${_h(_anchor(component.id))}">')
      ..write('<h2>${_h(component.title)}</h2>')
      ..write(_facts(component))
      ..write(_ingredients(component.groups, tree, heading: 'Ingredients'))
      ..write(_method(component, 1))
      ..write('</section>');
  }
  return out.toString();
}

/// One line's amount as the page prints it: the recipe's own word with the
/// amount it stands for (`2 blob (30 g)`), otherwise the app's own amount.
String shareAmountOf(LineItem line) {
  final amount = amountOfLine(line);
  final word = recipeMeasureOfLine(line);
  final count = line.quantity;
  if (word == null || count == null) return amount;
  final total = count * word.amount;
  return '$amount (${formatAmountIn(total, word.unit)} ${word.unit.label})';
}

/// The schema.org Recipe for [tree], read by Import and by other recipe apps.
///
/// Its ingredients are the shared recipe's lines, then each component's; its
/// instructions are one section per component, then the recipe's own, so a
/// cook reading it top to bottom makes the sauce before the dish.
Map<String, Object?> shareJsonLd(ShareTree tree, {required String url}) {
  final root = tree.root;
  List<String> lines(Recipe r) => [
    for (final g in r.groups)
      for (final l in g.items) _lineText(l),
  ];
  List<Map<String, Object?>> steps(Recipe r) => [
    for (final text in _stepTexts(r)) {'@type': 'HowToStep', 'text': text},
  ];
  final total = root.macros?.perServing;
  return {
    '@context': 'https://schema.org',
    '@type': 'Recipe',
    'name': root.title,
    'url': url,
    'recipeYield': [
      _servingsText(root.servingsBase),
      for (final y in root.yields)
        '${formatAmountIn(y.qty, y.unit)} ${y.unit.label}',
    ],
    if (root.totalTimeSeconds case final s?) 'totalTime': _isoDuration(s),
    if (root.cookTimeSeconds case final s?) 'cookTime': _isoDuration(s),
    'recipeIngredient': [
      ...lines(root),
      for (final c in tree.components) ...lines(c),
    ],
    'recipeInstructions': tree.components.isEmpty
        ? steps(root)
        : [
            for (final c in tree.components)
              {
                '@type': 'HowToSection',
                'name': c.title,
                'itemListElement': steps(c),
              },
            {
              '@type': 'HowToSection',
              'name': root.title,
              'itemListElement': steps(root),
            },
          ],
    if (total != null)
      'nutrition': {
        '@type': 'NutritionInformation',
        'servingSize': '1 serving',
        'calories': '${formatKcal(total.kcal)} kcal',
        'proteinContent': '${formatGrams(total.protein)} g',
        'carbohydrateContent': '${formatGrams(total.carb)} g',
        'fatContent': '${formatGrams(total.fat)} g',
        if (total.fiber case final f?) 'fiberContent': '${formatGrams(f)} g',
      },
  };
}

String _description(Recipe recipe) {
  final names = [
    for (final g in recipe.groups)
      for (final l in g.items) l.ingredientName,
  ];
  final shown = names.take(6).join(', ');
  final more = names.length > 6 ? ', and more' : '';
  return names.isEmpty
      ? _servingsText(recipe.servingsBase)
      : '${_servingsText(recipe.servingsBase)} · $shown$more';
}

/// What a recipe makes and how long it takes. The servings are the stepper's
/// to say, since they move.
String _facts(Recipe recipe) {
  final facts = [
    for (final y in recipe.yields)
      'makes ${formatAmountIn(y.qty, y.unit)} ${y.unit.label}',
    if (recipe.totalTimeSeconds case final s?) '${formatDuration(s)} in all',
    if (recipe.cookTimeSeconds case final s?) '${formatDuration(s)} cooking',
  ];
  if (facts.isEmpty) return '';
  return '<p class="facts">${_h(facts.join(' · '))}</p>';
}

String _scaler(double servings) {
  final fewer = servings > 1 ? servings - 1 : null;
  return '<div class="scaler">'
      '<button type="button" aria-label="Fewer servings"'
      '${fewer == null ? ' disabled' : ' data-servings="${_num(fewer)}"'}>'
      '−</button>'
      '<output aria-live="polite">${_h(_servingsText(servings))}</output>'
      '<button type="button" aria-label="More servings" '
      'data-servings="${_num(servings + 1)}">+</button>'
      '</div>';
}

String _ingredients(
  List<IngredientGroup> groups,
  ShareTree tree, {
  required String heading,
}) {
  final out = StringBuffer('<section class="ingredients"><h2>$heading</h2>');
  for (final group in groups) {
    if (group.items.isEmpty) continue;
    final name = group.name?.trim() ?? '';
    if (name.isNotEmpty) out.write('<h3>${_h(name)}</h3>');
    out.write('<ul>');
    for (final line in group.items) {
      final amount = shareAmountOf(line);
      final subId = line.subRecipeId;
      final named = subId != null && tree.shows(subId)
          ? '<a href="#${_h(_anchor(subId))}">${_h(line.ingredientName)}</a>'
          : _h(line.ingredientName);
      final note = line.note?.trim() ?? '';
      out
        ..write('<li>')
        ..write(amount.isEmpty ? '' : '<span class="amt">${_h(amount)}</span> ')
        ..write('<span class="name">$named</span>')
        ..write(note.isEmpty ? '' : '<span class="note">, ${_h(note)}</span>')
        ..write(line.optional ? ' <span class="tag">optional</span>' : '')
        ..write('</li>');
    }
    out.write('</ul>');
  }
  out.write('</section>');
  return out.toString();
}

/// Per serving, by the app's own rule: a line the walk could not count leaves
/// no total at all, and the page says so rather than printing part of one.
String _macros(RecipeMacroSummary? summary) {
  if (summary == null) return '';
  final total = summary.perServing;
  if (total == null) {
    if (summary.noLines) return '';
    return '<section class="macros"><h2>Per serving</h2>'
        '<p class="none">No nutrition total: some ingredients in this recipe '
        'have no nutrition data yet, and a partial sum would mislead.</p>'
        '</section>';
  }
  final cells = [
    (formatKcal(total.kcal), 'kcal'),
    ('${formatGrams(total.protein)} g', 'protein'),
    ('${formatGrams(total.carb)} g', 'carb'),
    ('${formatGrams(total.fat)} g', 'fat'),
    if (total.fiber case final f?) ('${formatGrams(f)} g', 'fibre'),
  ];
  final figures = [
    for (final (value, name) in cells)
      '<div><dt>${_h(name)}</dt><dd>${_h(value)}</dd></div>',
  ].join();
  return '<section class="macros"><h2>Per serving</h2><dl>$figures</dl>'
      '</section>';
}

String _method(Recipe recipe, double factor) {
  final steps = recipe.methodSteps;
  if ((steps == null || steps.isEmpty) && recipe.steps.isEmpty) return '';
  final lineById = {
    for (final g in recipe.groups)
      for (final l in g.items) l.id: l,
  };
  final out = StringBuffer('<section class="method"><h2>Method</h2><ol>');
  if (steps != null && steps.isNotEmpty) {
    for (final step in steps) {
      out.write('<li>');
      for (final span in foldMethod(step, lineById: lineById, factor: factor)) {
        out.write(switch (span) {
          MethodTextSpan(:final text) => _h(text),
          MethodChipSpan() =>
            '<span class="chip">${_h(_chipText(span))}</span>',
          MethodTimerSpan(:final text, :final lowSeconds, :final highSeconds) =>
            '<button type="button" class="timer" data-seconds='
                '"${midpointSeconds(lowSeconds, highSeconds)}">'
                '${_h(text)}</button>',
        });
      }
      out.write('</li>');
    }
  } else {
    for (final text in recipe.steps) {
      out.write('<li>${_h(text)}</li>');
    }
  }
  out.write('</ol></section>');
  return out.toString();
}

/// A chip as words: its amount, then its name; a collective with no label of
/// its own names its constituents.
String _chipText(MethodChipSpan chip) {
  final label = chip.label.isNotEmpty
      ? chip.label
      : chip.constituents.join(', ');
  final amount = chip.amount;
  return amount == null || amount.isEmpty ? label : '$amount $label';
}

/// A step as plain text, for the JSON-LD.
List<String> _stepTexts(Recipe recipe) {
  final steps = recipe.methodSteps;
  if (steps == null || steps.isEmpty) return recipe.steps;
  final lineById = {
    for (final g in recipe.groups)
      for (final l in g.items) l.id: l,
  };
  return [
    for (final step in steps)
      [
        for (final span in foldMethod(step, lineById: lineById))
          switch (span) {
            MethodTextSpan(:final text) => text,
            MethodChipSpan() => _chipText(span),
            MethodTimerSpan(:final text) => text,
          },
      ].join().trim(),
  ];
}

String _lineText(LineItem line) {
  final amount = shareAmountOf(line);
  final note = line.note?.trim() ?? '';
  return [if (amount.isNotEmpty) amount, line.ingredientName].join(' ') +
      (note.isEmpty ? '' : ', $note');
}

String _servingsText(double servings) =>
    servings == 1 ? '1 serving' : '${formatAmount(servings)} servings';

String _num(double value) => value == value.roundToDouble()
    ? value.round().toString()
    : value.toString();

String _anchor(String recipeId) => 'component-$recipeId';

String _isoDuration(int seconds) {
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final s = seconds % 60;
  return 'PT${h > 0 ? '${h}H' : ''}${m > 0 ? '${m}M' : ''}'
      '${s > 0 || seconds == 0 ? '${s}S' : ''}';
}

/// JSON inside a `<script>` ends the element at the first `</`; escaping the
/// slash keeps it JSON and keeps the element whole.
String _scriptSafe(String json) => json.replaceAll('</', r'<\/');

/// The app's three faces: Spectral for titles, Inter for the text, IBM Plex
/// Mono for amounts and figures.
const _fonts =
    'https://fonts.googleapis.com/css2?family=Spectral:wght@600'
    '&amp;family=Inter:wght@400;600'
    '&amp;family=IBM+Plex+Mono:wght@500&amp;display=swap';

const _css = '''
:root{--ink:#18211c;--muted:#5d6b62;--line:#dfe5df;--paper:#fbfaf6;--herb:#2f6b45;--wash:#eef3ee}
@media (prefers-color-scheme:dark){:root{--ink:#e8ece8;--muted:#a4b0a7;--line:#2c352f;--paper:#141a16;--herb:#7fc39a;--wash:#1d2620}}
*{box-sizing:border-box}
body{margin:0;background:var(--paper);color:var(--ink);font:16px/1.55 Inter,system-ui,-apple-system,sans-serif}
main,footer{max-width:640px;margin:0 auto;padding:0 16px}
h1{font:600 30px/1.2 Spectral,Georgia,serif;margin:28px 0 6px}
h2{font:600 19px/1.3 Spectral,Georgia,serif;margin:26px 0 8px}
h3{font-size:13px;letter-spacing:.06em;text-transform:uppercase;color:var(--muted);margin:16px 0 4px}
.facts{color:var(--muted);margin:0 0 14px}
.scaler{display:flex;align-items:center;gap:12px;border:1px solid var(--line);border-radius:14px;padding:8px 12px;width:max-content}
.scaler button{font-size:20px;width:36px;height:36px;border-radius:10px;border:1px solid var(--line);background:transparent;color:var(--ink)}
.scaler button:disabled{opacity:.35}
.scaler output{font-weight:600;min-width:7em;text-align:center}
ul{list-style:none;padding:0;margin:0}
li{padding:7px 0;border-bottom:1px solid var(--line)}
.amt{font:500 15px "IBM Plex Mono",ui-monospace,monospace}
.note{color:var(--muted)}
.tag{font-size:12px;color:var(--muted);border:1px solid var(--line);border-radius:6px;padding:0 5px}
a{color:var(--herb)}
.macros dl{display:flex;flex-wrap:wrap;gap:16px;margin:0}
.macros dt{font-size:12px;color:var(--muted)}
.macros dd{margin:0;font:500 17px "IBM Plex Mono",ui-monospace,monospace}
.none{color:var(--muted)}
ol{padding-left:22px}
ol li{border:0;padding:6px 0}
.chip{background:var(--wash);border-radius:8px;padding:1px 6px;white-space:nowrap}
.timer{font:inherit;color:var(--herb);background:var(--wash);border:1px solid var(--line);border-radius:8px;padding:0 6px;cursor:pointer}
.timer.running{color:var(--paper);background:var(--herb)}
.timer.due{color:#fff;background:#b3261e}
.component{border-top:2px solid var(--line);margin-top:30px}
footer{color:var(--muted);font-size:13px;padding:30px 16px 40px}
''';
