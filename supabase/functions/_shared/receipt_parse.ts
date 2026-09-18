// Reading the paper's printed strings honestly — money, a date, a weight unit.
//
// The model prints what the receipt printed and stops there (ADR-0004 in its
// own small way: the model is not asked to convert, because a conversion is a
// thing we can get right deterministically and it cannot). Everything numeric
// in the payload is therefore parsed HERE, from the printed words, by code with
// tests.
//
// "Honestly" is the whole rule: a figure that cannot be read comes back `null`
// and becomes a note in the review, never a zero. A zero would add up.

// -----------------------------------------------------------------------------
// Money → integer cents
// -----------------------------------------------------------------------------

/**
 * Every character a till has been seen to put in front of a negative number.
 * The ASCII hyphen, the real minus sign (U+2212 — what a good transcription of
 * a laser-printed receipt gives back), and the en dash.
 */
const MINUS = /[-−–]/;

/**
 * A printed money figure → integer cents, or `null` when it cannot be read.
 *
 * Reads, in this order: a parenthesised figure `(0.55)` as negative; a leading
 * or TRAILING minus (`-0.55`, `0.55-` — the trailing form is what a lot of
 * tills print for a credit); a currency symbol or code anywhere; and either
 * separator as the decimal point. `3,49` is three dollars forty-nine, and
 * `1,234.56` is a thousand-odd — the LAST separator is the decimal one, unless
 * a lone comma is followed by three digits, which makes it a thousands mark.
 *
 * Parsed as digits, never through a float: `parseFloat("3.49") * 100` is
 * 348.99999999999994, and money that rounds is money that stops adding up.
 *
 * A bare integer is read as whole dollars (`3` ⇒ 300). Tills print the cents,
 * so this is rare, and dollars is the only reading that is ever right.
 */
export function parseCents(printed: string | null | undefined): number | null {
  if (printed === null || printed === undefined) return null;
  let s = printed.trim();
  if (s === "") return null;

  let negative = false;
  // (0.55) — the accountant's minus.
  const parens = s.match(/^\((.*)\)$/);
  if (parens) {
    negative = true;
    s = parens[1].trim();
  }
  // A sign at either end. Stripped before the digits are read so "0.55-" and
  // "-0.55" reach the same place.
  if (MINUS.test(s.charAt(0))) {
    negative = true;
    s = s.slice(1).trim();
  }
  if (s.length > 0 && MINUS.test(s.charAt(s.length - 1))) {
    negative = true;
    s = s.slice(0, -1).trim();
  }
  // Currency: the symbol, the code, and the space that follows either.
  s = s.replace(/usd/ig, "").replace(/[$£€]/g, "").replace(
    /\s+/g,
    "",
  );
  if (s === "") return null;
  if (!/^[0-9.,]+$/.test(s)) return null;

  const lastDot = s.lastIndexOf(".");
  const lastComma = s.lastIndexOf(",");
  let decimalAt = Math.max(lastDot, lastComma);
  // A lone comma with three digits behind it is a thousands mark, not a point.
  if (
    decimalAt === lastComma && lastDot === -1 &&
    s.length - lastComma - 1 === 3
  ) {
    decimalAt = -1;
  }

  let whole: string;
  let frac: string;
  if (decimalAt === -1) {
    whole = s.replace(/[.,]/g, "");
    frac = "00";
  } else {
    whole = s.slice(0, decimalAt).replace(/[.,]/g, "");
    frac = s.slice(decimalAt + 1).replace(/[.,]/g, "");
    if (frac.length === 0) return null;
    // A till prints two; anything longer is truncated rather than rounded,
    // because rounding a figure we are copying would be inventing one.
    frac = (frac + "00").slice(0, 2);
  }
  if (whole === "") whole = "0";
  if (!/^\d+$/.test(whole) || !/^\d{2}$/.test(frac)) return null;

  const cents = Number(whole) * 100 + Number(frac);
  if (!Number.isSafeInteger(cents)) return null;
  return negative ? -cents : cents;
}

/** {@link parseCents}, with the sign dropped — for a deduction, which is stated as an amount. */
export function parseDiscountCents(
  printed: string | null | undefined,
): number | null {
  const cents = parseCents(printed);
  return cents === null ? null : Math.abs(cents);
}

// -----------------------------------------------------------------------------
// The printed date → ISO-8601 local wall time
// -----------------------------------------------------------------------------

const MONTHS: Record<string, number> = {
  jan: 1,
  feb: 2,
  mar: 3,
  apr: 4,
  may: 5,
  jun: 6,
  jul: 7,
  aug: 8,
  sep: 9,
  sept: 9,
  oct: 10,
  nov: 11,
  dec: 12,
};

const pad = (n: number, width = 2) => String(n).padStart(width, "0");

/** Days in a month, so 31 February is refused rather than rolled forward. */
function validDate(y: number, m: number, d: number): boolean {
  if (m < 1 || m > 12 || d < 1) return false;
  const leap = (y % 4 === 0 && y % 100 !== 0) || y % 400 === 0;
  const days = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  return d <= days[m - 1];
}

/**
 * A two-digit year on a till receipt is this century. There is no receipt from
 * 1926 in anybody's kitchen drawer, and the alternative reading would file a
 * shop a hundred years out of the week it belongs to.
 */
function fullYear(raw: string): number {
  const n = Number(raw);
  return raw.length <= 2 ? 2000 + n : n;
}

/** The time of day, if the paper printed one. `null` ⇒ midnight. */
function parseClock(s: string): { h: number; min: number; sec: number } | null {
  // The hour must not be preceded by a digit or a colon: without that,
  // "2026-09-13T11:04:09" matches at "04:09" and the receipt lands four
  // minutes past midnight.
  const m = s.match(
    /(?<![\d:])(\d{1,2}):(\d{2})(?::(\d{2}))?\s*([ap]\.?m\.?)?/i,
  );
  if (!m) return null;
  let h = Number(m[1]);
  const min = Number(m[2]);
  const sec = m[3] ? Number(m[3]) : 0;
  const meridiem = m[4]?.toLowerCase().replace(/\./g, "");
  if (meridiem === "pm" && h < 12) h += 12;
  if (meridiem === "am" && h === 12) h = 0;
  if (h > 23 || min > 59 || sec > 59) return null;
  return { h, min, sec };
}

/**
 * The printed date and time → `YYYY-MM-DDTHH:MM:SS`, local wall time with NO
 * zone, or `null` when it cannot be read.
 *
 * No zone on purpose: a receipt states the moment the shop happened in the
 * shop's own clock, there is nothing on the paper that says which offset that
 * was, and a receipt scanned in another time zone must still land on the day it
 * was printed. The week it files under is the household's own week start, read
 * off these wall-clock digits.
 *
 * Reads the US forms a till prints — `09/13/26`, `9/13/2026`, `2026-09-13`,
 * `SEP 13 2026`, `13 SEP 2026` — each with an optional 12- or 24-hour time.
 * A slashed date is READ MONTH-FIRST; the household shops in the US, and a
 * paper that means otherwise is a note away from being corrected by hand in the
 * review, which is the door the board draws beside the date.
 */
export function parseReceiptDate(
  printed: string | null | undefined,
): string | null {
  if (!printed || printed.trim() === "") return null;
  const s = printed.trim();

  let y: number | null = null;
  let mo = 0;
  let d = 0;

  const iso = s.match(/\b(\d{4})-(\d{1,2})-(\d{1,2})(?!\d)/);
  const slashed = s.match(/\b(\d{1,2})[/.](\d{1,2})[/.](\d{2,4})(?!\d)/);
  const monthFirst = s.match(
    /\b([a-z]{3,9})\.?\s+(\d{1,2})(?:st|nd|rd|th)?,?\s+(\d{2,4})\b/i,
  );
  const dayFirst = s.match(/\b(\d{1,2})\s+([a-z]{3,9})\.?,?\s+(\d{2,4})\b/i);

  if (iso) {
    y = Number(iso[1]);
    mo = Number(iso[2]);
    d = Number(iso[3]);
  } else if (slashed) {
    mo = Number(slashed[1]);
    d = Number(slashed[2]);
    y = fullYear(slashed[3]);
  } else if (
    monthFirst && MONTHS[monthFirst[1].toLowerCase().slice(0, 4)] !== undefined
  ) {
    mo = MONTHS[monthFirst[1].toLowerCase().slice(0, 4)];
    d = Number(monthFirst[2]);
    y = fullYear(monthFirst[3]);
  } else if (
    monthFirst && MONTHS[monthFirst[1].toLowerCase().slice(0, 3)] !== undefined
  ) {
    mo = MONTHS[monthFirst[1].toLowerCase().slice(0, 3)];
    d = Number(monthFirst[2]);
    y = fullYear(monthFirst[3]);
  } else if (dayFirst) {
    const key = dayFirst[2].toLowerCase();
    const month = MONTHS[key.slice(0, 4)] ?? MONTHS[key.slice(0, 3)];
    if (month === undefined) return null;
    d = Number(dayFirst[1]);
    mo = month;
    y = fullYear(dayFirst[3]);
  }

  if (y === null || !validDate(y, mo, d)) return null;
  const clock = parseClock(s) ?? { h: 0, min: 0, sec: 0 };
  return `${pad(y, 4)}-${pad(mo)}-${pad(d)}T${pad(clock.h)}:${pad(clock.min)}:${
    pad(clock.sec)
  }`;
}

// -----------------------------------------------------------------------------
// The printed weight unit → a units.dart canonical id
// -----------------------------------------------------------------------------

/**
 * Every printed spelling of the four units a till weighs in, mapped to the
 * canonical id `app/lib/core/units/units.dart` holds. The payload carries the
 * id, so the app converts with the same catalog every other amount in the
 * system uses — a receipt is not a second unit vocabulary.
 *
 * Volume is deliberately absent: a till does not sell by the litre, and a
 * printed `@ /ea` is a count, not a weight (it comes back as no weight at all).
 */
const WEIGHT_UNITS: Record<string, string> = {
  lb: "lb",
  lbs: "lb",
  "lb.": "lb",
  "#": "lb",
  pound: "lb",
  pounds: "lb",
  kg: "kg",
  kgs: "kg",
  "kg.": "kg",
  kilo: "kg",
  kilos: "kg",
  kilogram: "kg",
  kilograms: "kg",
  oz: "oz",
  "oz.": "oz",
  ounce: "oz",
  ounces: "oz",
  g: "g",
  "g.": "g",
  gm: "g",
  gms: "g",
  gram: "g",
  grams: "g",
};

/** A printed unit word → its canonical id, or `null` when it is not a weight we know. */
export function canonicalWeightUnit(printed: string | null): string | null {
  if (!printed) return null;
  const key = printed.trim().toLowerCase().replace(/\s+/g, "");
  return WEIGHT_UNITS[key] ?? null;
}
