/// The aisle order — PURE DART.
///
/// One walk through a shop, said once. The shopping list groups what to buy by
/// it and the ingredients manager groups the vocabulary by it, and somebody who
/// learned the order on one screen should not meet a different one two taps
/// away. It lives in `core/` because neither feature may reach into the other
/// for a shared rule.
///
/// An ingredient's stored `category` is free text — a household can coin one —
/// so the order is a *preference*, never a whitelist: a category nobody here
/// named still gets a group, sorted after the known aisles.
library;

/// The known aisles, in shop-walk order. Lower-cased, because that is how a
/// stored `category` is keyed ([aisleKey]).
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
/// which no stored category carries, so it sorts ahead of every coined aisle —
/// "Other" is where you look once the named sections have run out.
const kUncategorisedAisle = '\u0000other';

/// The group key for a stored `category`: trimmed and lower-cased, or
/// [kUncategorisedAisle] when the row names none.
String aisleKey(String? category) {
  final c = category?.trim().toLowerCase();
  return (c == null || c.isEmpty) ? kUncategorisedAisle : c;
}

/// The display label for a key from [aisleKey] — "spices & seasoning" reads
/// "Spices & Seasoning", and the uncategorised key reads "Other".
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
