const AUTOCOMPLETE_TOKEN_SEPARATOR = /\s+/;

const OTP_STRONG_DESCRIPTOR_RE =
  /\b(one[\s-]?time(?:\s+code|\s+password)?|otp|totp|2fa|mfa|authenticator|authentication\s+code|auth\s+code|login\s+code|sign[\s-]?in\s+code|verification\s+token)\b/;

const OTP_CHALLENGE_DESCRIPTOR_RE =
  /\b(verification\s+code|verification|pin\s+code|code)\b/;

const OTP_CHALLENGE_CONTEXT_RE =
  /\b(digit|6\s*digit|six\s+digit|email|e-mail|sms|text\s+message)\b/;

const CARD_CONTEXT_DESCRIPTOR_RE =
  /\b(cc|credit\s+card|card|cvc|cvv|cvn|csc|cid|security\s+code|cardholder|billing|pan|expiry|expiration)\b/;

const EMAIL_IDENTIFIER_DESCRIPTOR_RE = /\b(e[\s-]?mail|mail\s+address)\b/;
const USERNAME_IDENTIFIER_DESCRIPTOR_RE =
  /\b(user[\s_-]?name|login[\s_-]?name|user[\s_-]?id|account[\s_-]?name|screen[\s_-]?name|handle)\b/;

export type CredentialIdentifierKind = "email" | "username" | "any";

function normalizeDescriptor(value: string): string {
  return value
    .toLowerCase()
    .replace(/[_./,-]+/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function autocompleteTokens(value: string): string[] {
  return value
    .toLowerCase()
    .split(AUTOCOMPLETE_TOKEN_SEPARATOR)
    .filter(Boolean);
}

export function isOneTimeCodeAutocomplete(value: string): boolean {
  return autocompleteTokens(value).includes("one-time-code");
}

export function isCredentialIdentifierPurpose(inputType: string, autocomplete: string): boolean {
  const tokens = autocompleteTokens(autocomplete);
  return inputType.toLowerCase() === "email"
    || tokens.includes("email")
    || tokens.includes("username");
}

export function getCredentialIdentifierKind(
  inputType: string,
  autocomplete: string,
  descriptor = "",
): CredentialIdentifierKind {
  const tokens = autocompleteTokens(autocomplete);
  const normalizedDescriptor = normalizeDescriptor(descriptor);

  const emailSignal = inputType.toLowerCase() === "email"
    || tokens.includes("email")
    || EMAIL_IDENTIFIER_DESCRIPTOR_RE.test(normalizedDescriptor);
  const usernameSignal = tokens.includes("username")
    || USERNAME_IDENTIFIER_DESCRIPTOR_RE.test(normalizedDescriptor);

  if (emailSignal && !usernameSignal) return "email";
  if (usernameSignal && !emailSignal) return "username";
  return "any";
}

export function isOneTimeCodeDescriptor(descriptor: string): boolean {
  const normalized = normalizeDescriptor(descriptor);
  if (!normalized) return false;

  if (OTP_STRONG_DESCRIPTOR_RE.test(normalized)) return true;

  return OTP_CHALLENGE_DESCRIPTOR_RE.test(normalized)
    && OTP_CHALLENGE_CONTEXT_RE.test(normalized)
    && !CARD_CONTEXT_DESCRIPTOR_RE.test(normalized);
}
