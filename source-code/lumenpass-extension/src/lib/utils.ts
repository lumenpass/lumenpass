/** Shared utility functions */

// ─── URL helpers ──────────────────────────────────────────────────────────────

/** Extract the root domain from a full URL (e.g. "https://github.com/foo" → "github.com") */
export function extractDomain(url: string): string {
  try {
    return new URL(url).hostname;
  } catch {
    return url;
  }
}

/** Build a Google favicon URL for a given page URL */
export function faviconUrl(pageUrl: string): string {
  const domain = extractDomain(pageUrl);
  return `https://www.google.com/s2/favicons?sz=32&domain=${encodeURIComponent(domain)}`;
}

/**
 * Bump `sz` on Google’s s2 favicon URLs so raster icons stay sharp on HiDPI / flex layouts.
 * In-page suggestion sheets often use sz=64; the popup list was softer when sz=32 or when flex shrank the tile.
 */
export function googleFaviconUrlForDisplay(url: string, minSz = 128): string {
  try {
    const u = new URL(url);
    if (u.hostname !== "www.google.com" || !u.pathname.includes("/s2/favicons")) {
      return url;
    }
    const current = parseInt(u.searchParams.get("sz") ?? "0", 10);
    if (current >= minSz) return url;
    u.searchParams.set("sz", String(minSz));
    return u.toString();
  } catch {
    return url;
  }
}

// ─── Debounce ─────────────────────────────────────────────────────────────────

export function debounce<T extends (...args: unknown[]) => void>(
  fn: T,
  delayMs: number,
): (...args: Parameters<T>) => void {
  let timer: ReturnType<typeof setTimeout>;
  return (...args: Parameters<T>) => {
    clearTimeout(timer);
    timer = setTimeout(() => fn(...args), delayMs);
  };
}

// ─── Colour generation (for avatar fallbacks) ─────────────────────────────────

const PALETTE = [
  "#6172f3", "#ef6820", "#ee46bc", "#16b364",
  "#f79009", "#0ba5ec", "#e31b54", "#875bf7",
];

/** Deterministically pick a saturated palette colour based on a string seed */
export function seedColour(seed: string): string {
  let hash = 0;
  for (let i = 0; i < seed.length; i++) {
    hash = (hash * 31 + seed.charCodeAt(i)) & 0xffffffff;
  }
  return PALETTE[Math.abs(hash) % PALETTE.length];
}

/** 1Password-style pastel avatar: soft bg + matching darker text colour */
const PASTEL_PALETTE: Array<{ bg: string; fg: string }> = [
  { bg: "#dbe4ff", fg: "#3451b2" },
  { bg: "#ffd8a8", fg: "#b35800" },
  { bg: "#fcc2d7", fg: "#9b1144" },
  { bg: "#b2f2bb", fg: "#1a7431" },
  { bg: "#fff3bf", fg: "#8a5c00" },
  { bg: "#a5d8ff", fg: "#1862ab" },
  { bg: "#e5dbff", fg: "#5f3dc4" },
  { bg: "#c3fae8", fg: "#0b6259" },
];

export function pastelAvatar(seed: string): { bg: string; fg: string } {
  let hash = 0;
  for (let i = 0; i < seed.length; i++) {
    hash = (hash * 31 + seed.charCodeAt(i)) & 0xffffffff;
  }
  return PASTEL_PALETTE[Math.abs(hash) % PASTEL_PALETTE.length];
}

/** Generate initials (up to 2 chars) from a title string */
export function initials(title: string): string {
  const words = title.trim().split(/\s+/);
  if (words.length === 1) return words[0].slice(0, 2).toUpperCase();
  return (words[0][0] + words[words.length - 1][0]).toUpperCase();
}

// ─── Time helpers ─────────────────────────────────────────────────────────────

/** Format a TOTP countdown (seconds remaining) */
export function totpCountdown(period = 30): number {
  return period - (Math.floor(Date.now() / 1000) % period);
}

// ─── TOTP computation (RFC 6238) ──────────────────────────────────────────────

function base32Decode(input: string): Uint8Array {
  const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";
  const clean = input.toUpperCase().replace(/\s|=/g, "");
  let bits = 0, value = 0;
  const out: number[] = [];
  for (const ch of clean) {
    const idx = alphabet.indexOf(ch);
    if (idx === -1) continue;
    value = (value << 5) | idx;
    bits += 5;
    if (bits >= 8) { out.push((value >>> (bits - 8)) & 0xff); bits -= 8; }
  }
  return new Uint8Array(out);
}

/** Compute a TOTP code from an otpauth:// URI or a raw Base32 secret.
 *  Returns the zero-padded code string, or null on error. */
export async function computeTotp(input: string): Promise<string | null> {
  try {
    let secret: string;
    let digits = 6;
    let period = 30;
    let algorithm = "SHA-1";

    if (input.startsWith("otpauth://")) {
      const url = new URL(input);
      const p = url.searchParams;
      secret = p.get("secret") ?? "";
      digits = parseInt(p.get("digits") ?? "6", 10);
      period = parseInt(p.get("period") ?? "30", 10);
      const alg = (p.get("algorithm") ?? "SHA1").toUpperCase().replace("SHA", "SHA-");
      algorithm = alg === "SHA-1" || alg === "SHA-256" || alg === "SHA-512" ? alg : "SHA-1";
    } else {
      secret = input;
    }

    if (!secret) return null;
    const raw = base32Decode(secret);
    const keyBuffer = raw.buffer.slice(raw.byteOffset, raw.byteOffset + raw.byteLength) as ArrayBuffer;
    const counter = Math.floor(Date.now() / 1000 / period);

    const cryptoKey = await crypto.subtle.importKey(
      "raw", keyBuffer,
      { name: "HMAC", hash: algorithm },
      false, ["sign"],
    );

    const buf = new ArrayBuffer(8);
    new DataView(buf).setUint32(4, counter >>> 0, false);
    const hmac = new Uint8Array(await crypto.subtle.sign("HMAC", cryptoKey, buf));

    const offset = hmac[hmac.length - 1] & 0x0f;
    const code = (
      ((hmac[offset] & 0x7f) << 24) |
      ((hmac[offset + 1] & 0xff) << 16) |
      ((hmac[offset + 2] & 0xff) << 8) |
      (hmac[offset + 3] & 0xff)
    ) % (10 ** digits);

    return code.toString().padStart(digits, "0");
  } catch {
    return null;
  }
}

// ─── Clipboard ────────────────────────────────────────────────────────────────

export async function copyToClipboard(text: string): Promise<boolean> {
  try {
    await navigator.clipboard.writeText(text);
    return true;
  } catch {
    return false;
  }
}

// ─── Message types (content ↔ background ↔ popup) ────────────────────────────

export type MessageType =
  | "SEARCH_ENTRIES"
  | "GET_ENTRY"
  | "AUTOFILL"
  | "AUTOFILL_GENERATED_PASSWORD"
  | "PING"
  | "GET_SETTINGS"
  | "SAVE_SETTINGS"
  | "DISABLE_AUTOFILL_DOMAIN"
  | "ENABLE_AUTOFILL_DOMAIN"
  | "GET_CURRENT_TAB_URL"
  | "PASSKEY_GET"
  | "PASSKEY_ASSERT"
  | "PASSKEY_FIND_MATCHES"
  | "PASSKEY_CREATE"
  | "SAVE_LOGIN"
  | "CAPTURE_LOGIN"
  | "SHOW_SAVE_PROMPT"
  | "GET_LOGIN_SURFACE_STATE"
  | "GET_CATEGORIES"
  | "SET_PENDING_PASSKEY"
  | "GET_VAULT_STATUS"
  | "FOCUS_DESKTOP"
  | "OPEN_NEW_ITEM"
  | "OPEN_EDIT_ITEM"
  | "DELETE_ITEM"
  | "VAULT_STATUS_CHANGED"
  | "GET_UNLOCK_OPTIONS"
  | "UNLOCK_WITH_PASSWORD"
  | "UNLOCK_WITH_PIN"
  | "UNLOCK_WITH_BIOMETRIC"
  // ── Social login ──────────────────────────────────────────────────────────────
  | "CAPTURE_SOCIAL_LOGIN"
  | "SHOW_SAVE_SOCIAL_PROMPT"
  | "SAVE_SOCIAL_LOGIN"
  // ── Quick create (right-click context menu) ───────────────────────────────────
  | "OPEN_QUICK_CREATE_LOGIN"
  | "OPEN_QUICK_CREATE_NOTE"
  | "OPEN_PASSWORD_GENERATOR"
  | "SAVE_CREDIT_CARD"
  | "SAVE_NOTE";

export interface ExtMessage<T = unknown> {
  type: MessageType;
  payload?: T;
}

export interface ExtResponse<T = unknown> {
  ok: boolean;
  data?: T;
  error?: string;
}
