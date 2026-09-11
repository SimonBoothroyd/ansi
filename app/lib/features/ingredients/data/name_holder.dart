/// The one name namespace, asked **inside a write transaction**.
///
/// `domain/name_namespace.dart` holds the rule in pure Dart, over the list of
/// names the UI already has in hand. This file is its write-seam twin:
/// the same question — exact equality over `match_text`, a row's own name and
/// any row's aliases counted alike — asked in SQL, under the transaction that
/// is about to write, where reading the whole vocabulary to compare one string
/// would be the expensive way to ask.
///
/// **Every writer of a name or an alias asks it here**, because a rule held by
/// only some of the writers is not held at all: one writer that skips it —
/// learning "extra-firm tofu" onto *Super Firm Tofu*, which is *Extra Firm
/// Tofu*'s own name — puts one `match_text` on two rows, and from then on
/// every exact match between them is a coin toss.
library;

import 'package:sqlite_async/sqlite_async.dart';

/// The live row already carrying a `match_text`, as its id and the canonical
/// name a refusal says out loud.
typedef NameHolder = ({String id, String name});

/// The live row that already carries [matchText] as its own name or one of its
/// aliases, or null when the text is free.
///
/// **Includes the row being written** — the caller decides what its own
/// ownership means. A save under the name it already has is not a duplicate of
/// anything (so `saveForm` skips a holder that is itself), while an alias the
/// picked row already owns is simply nothing to learn.
///
/// Null for an empty [matchText]: a phrase with no identity word is not a name
/// here, and nothing can hold it.
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
