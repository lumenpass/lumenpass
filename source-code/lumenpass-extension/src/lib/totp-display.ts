export interface TotpCustomField {
  label: string;
  value: string;
}

export interface FeaturedTotpDisplay {
  key: string;
  label: string;
  totp: string;
  customFieldIndex?: number;
}

interface BuildFeaturedTotpsOptions<T extends TotpCustomField> {
  standardTotp?: string | null;
  standardKey?: string;
  standardLabel?: string;
  customFields?: readonly T[];
  isCustomTotpField?: (field: T, index: number) => boolean;
  customKey?: (field: T, index: number) => string;
  customLabel?: (field: T, index: number) => string;
}

const CANONICAL_TOTP_STORAGE_LABELS = new Set([
  "otp",
  "totp",
  "otpauth",
  "timeotp",
  "timebasedotp",
]);

export function hasTotpDisplayValue(value: string | undefined | null): value is string {
  return !!value && value.trim() !== "" && value.trim() !== "-" && value.trim() !== "\u2014";
}

export function isOtpLikeFieldLabel(label: string): boolean {
  return /otp|totp/i.test(label);
}

export function isCanonicalTotpStorageLabel(label: string): boolean {
  const normalized = label.trim().toLowerCase().replace(/[^a-z0-9]/g, "");
  return CANONICAL_TOTP_STORAGE_LABELS.has(normalized);
}

export function totpDisplayIdentity(value: string): string {
  const trimmed = value.trim();
  if (!trimmed) return "";

  if (trimmed.toLowerCase().startsWith("otpauth://")) {
    try {
      const uri = new URL(trimmed);
      const secret = (uri.searchParams.get("secret") ?? "").replace(/\s|=/g, "").toUpperCase();
      const algorithm = (uri.searchParams.get("algorithm") ?? "SHA1").toUpperCase().replace(/[^A-Z0-9]/g, "");
      const digits = uri.searchParams.get("digits") ?? "6";
      const period = uri.searchParams.get("period") ?? "30";
      if (secret) return `otpauth:${secret}:${algorithm}:${digits}:${period}`;
    } catch {
      // Fall through to simple string normalization.
    }
  }

  return trimmed.replace(/\s+/g, "").toLowerCase();
}

export function buildFeaturedTotps<T extends TotpCustomField>({
  standardTotp,
  standardKey = "__std_totp",
  standardLabel = "one-time password",
  customFields = [],
  isCustomTotpField = (field) => isOtpLikeFieldLabel(field.label),
  customKey = (field, index) => `custom_totp:${index}:${field.label}`,
  customLabel = (field) => field.label,
}: BuildFeaturedTotpsOptions<T>): FeaturedTotpDisplay[] {
  const featuredTotps: FeaturedTotpDisplay[] = [];
  const seen = new Set<string>();
  const hasStandardTotp = hasTotpDisplayValue(standardTotp);

  const addTotp = (
    key: string,
    label: string,
    value: string | undefined | null,
    customFieldIndex?: number,
  ) => {
    if (!hasTotpDisplayValue(value)) return;
    const identity = totpDisplayIdentity(value);
    if (identity && seen.has(identity)) return;
    if (identity) seen.add(identity);
    featuredTotps.push({
      key,
      label,
      totp: value.trim(),
      ...(customFieldIndex === undefined ? {} : { customFieldIndex }),
    });
  };

  addTotp(standardKey, standardLabel, standardTotp);

  customFields.forEach((field, index) => {
    if (!isCustomTotpField(field, index)) return;
    if (hasStandardTotp && isCanonicalTotpStorageLabel(field.label)) return;
    addTotp(customKey(field, index), customLabel(field, index), field.value, index);
  });

  return featuredTotps;
}
