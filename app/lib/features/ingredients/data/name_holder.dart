/// The name namespace, asked inside a write transaction.
///
/// `domain/name_namespace.dart` holds the rule in pure Dart over names the UI
/// has in hand. This asks the same question in SQL: exact equality over
/// `match_text`, names and aliases alike. Every writer of a name or alias must
/// ask it; one that skips it puts one `match_text` on two rows, and exact
/// matches between them become arbitrary.
library;

import 'package:sqlite_async/sqlite_async.dart';

/// The live row already carrying a `match_text`, as its id and the canonical
/// name a refusal says out loud.
typedef NameHolder = ({String id, String name});

/// The live row that already carries [matchText] as its name or an alias, or
/// null when the text is free. Includes the row being written; the caller
/// decides what its own ownership means. Null for an empty [matchText].
Future<NameHolder?> nameHolderFor(
  SqliteWriteContext tx,
  String matchText,
) async {
  if (matchText.isEmpty) return null;
  // The name leg first, so a row that owns the text outright is the answer
  // even when another row carries it as an alias too.
  final row = await tx.getOptional(
    'SELECT i.id, i.canonical_name FROM ingredient i '
    'WHERE i.match_text = ? AND i.deleted_at IS NULL '
    'UNION ALL '
    'SELECT i.id, i.canonical_name FROM ingredient_alias a '
    'JOIN ingredient i ON i.id = a.ingredient_id '
    'WHERE a.match_text = ? AND a.deleted_at IS NULL '
    'AND i.deleted_at IS NULL '
    'LIMIT 1',
    [matchText, matchText],
  );
  if (row == null) return null;
  return (id: row['id'] as String, name: row['canonical_name'] as String);
}
