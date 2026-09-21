/// The aisle order (pure Dart), shared by the shopping list and the
/// ingredients manager.
///
/// A stored `category` is free text, so the order is a preference, not a
/// whitelist: an unknown category still gets a group, after the known aisles.
library;

/// The known aisles, in shop-walk order, lower-cased as [aisleKey] keys them.
const kAisleOrder = <String>[
  'produce',
  'meat',
  'dairy',
  'baking',
  'grains',
  'pantry',
  'spices & seasoning',
  'fats & oils',
];

/// The key an ingredient with no category groups under. It opens with a NUL,
/// which no stored category carries, so it sorts ahead of every coined aisle.
const kUncategorisedAisle = '\u0000other';

/// The group key for a stored `category`: trimmed and lower-cased, or
/// [kUncategorisedAisle] when the row names none.
String aisleKey(String? category) {
  final c = category?.trim().toLowerCase();
  return (c == null || c.isEmpty) ? kUncategorisedAisle : c;
}

/// The display label for a key from [aisleKey], in Title Case; the
/// uncategorised key reads "Other".
String aisleLabel(String key) => key == kUncategorisedAisle
    ? 'Other'
    : key
          .split(' ')
          .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
          .join(' ');

/// Orders two keys from [aisleKey]: the [kAisleOrder] aisles first, in that
/// order, then everything a household coined, alphabetically.
int compareAisles(String a, String b) {
  final ai = kAisleOrder.indexOf(a);
  final bi = kAisleOrder.indexOf(b);
  if (ai != -1 && bi != -1) return ai.compareTo(bi);
  if (ai != -1) return -1;
  if (bi != -1) return 1;
  return a.compareTo(b);
}
