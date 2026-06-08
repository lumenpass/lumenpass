export interface ParsedCardExpiry {
  month: string;
  year: string;
}

function normalizeParsedExpiry(month: string, year: string): ParsedCardExpiry | null {
  const monthNumber = parseInt(month, 10);
  if (!Number.isFinite(monthNumber) || monthNumber < 1 || monthNumber > 12) return null;

  if (year.length !== 2 && year.length !== 4) return null;

  return {
    month: String(monthNumber).padStart(2, "0"),
    year: year.length === 2 ? `20${year}` : year,
  };
}

export function parseCardExpiry(raw: string): ParsedCardExpiry | null {
  const trimmed = raw.trim();
  if (!trimmed) return null;

  const compactSeparators = trimmed.replace(/\s*([/-])\s*/g, "$1");

  // YYYY-MM (e.g. "2030-03")
  const yearMonth = compactSeparators.match(/^(\d{4})[/-](\d{1,2})$/);
  if (yearMonth) return normalizeParsedExpiry(yearMonth[2], yearMonth[1]);

  // MM/YYYY, MM/YY, MM - YYYY, etc.
  const monthYear = compactSeparators.match(/^(\d{1,2})[/-](\d{2}|\d{4})$/);
  if (monthYear) return normalizeParsedExpiry(monthYear[1], monthYear[2]);

  // Stripe and some vault imports display expiry as "MM / YY"; older imports may
  // have spaces but no slash, or only digits.
  const digits = trimmed.replace(/\D+/g, "");
  if (digits.length === 4) return normalizeParsedExpiry(digits.slice(0, 2), digits.slice(2));
  if (digits.length === 6) {
    const monthFirst = normalizeParsedExpiry(digits.slice(0, 2), digits.slice(2));
    if (monthFirst) return monthFirst;
    if (digits.startsWith("20")) return normalizeParsedExpiry(digits.slice(4), digits.slice(0, 4));
  }

  return null;
}
