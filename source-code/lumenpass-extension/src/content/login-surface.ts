/**
 * Pure, DOM-free helpers used by the content script to decide whether the
 * current page is an unauthenticated login surface where it is safe to offer
 * a passkey or autofill prompt.
 *
 * These helpers are extracted into their own module so they can be unit-tested
 * with Vitest in a Node environment (no jsdom). The content script collects the
 * raw signals from the live DOM and feeds them in as a `LoginSurfaceSignals`
 * object.
 *
 * Design notes:
 *  - Showing a passkey/autofill prompt on an *authenticated* page (e.g.
 *    `console.cloud.google.com/auth/clients`) is considered a critical bug.
 *    The previous implementation short-circuited on any URL containing
 *    `/auth/` which matched many post-login admin sections. This module
 *    intentionally:
 *      1. Only treats a URL as a login indicator when paired with at least
 *         one DOM-level login signal (password field, login keyword in body,
 *         or a login-style submit button).
 *      2. Drops the bare `/auth/` keyword in favour of explicit login paths
 *         (`/login`, `/signin`, `/sso`, `/sign-in`, `/log-in`, …).
 *      3. ALWAYS suppresses the prompt when a logged-in email is detected
 *         on the page – even if other heuristics would have matched.
 */

/**
 * Signals collected from the live DOM by the content script. Keep this
 * intentionally narrow: every field must be cheap to compute.
 */
export interface LoginSurfaceSignals {
  /** `window.location.pathname.toLowerCase()` */
  pathname: string;
  /** `window.location.hostname.toLowerCase()` (optional context for tests) */
  hostname?: string;
  /** `document.title.toLowerCase()` (optional context for tests) */
  pageTitle?: string;
  /** Number of visible `<input type="password">` (excluding signup fields). */
  passwordFieldCount: number;
  /** Number of visible username/email fields, clustered near auth controls. */
  usernameFieldCount: number;
  /** Number of visible one-time-code / OTP challenge fields. */
  otpFieldCount: number;
  /** Whether any visible button text matches login-style copy. */
  hasLoginActionButton: boolean;
  /** Whether any visible button text matches passkey/security-key copy. */
  hasPasskeyActionButton: boolean;
  /** First ~3000 lower-cased chars of `document.body.innerText`. */
  pageTextSample: string;
  /** Email address detected in logged-in UI chrome (avatar, account menu…). */
  detectedLoggedInEmail: string;
  /** Whether the active auth form/page is for account registration. */
  isRegistrationSurface: boolean;
  /** Whether any visible heading mentions creating/registering a passkey. */
  isPasskeyManagementPage: boolean;
}

/**
 * Patterns describing URL paths that are *almost certainly* a login surface.
 *
 * Note: `/auth` alone is intentionally excluded — many products (Google Cloud
 * Auth Platform, AWS IAM, GitHub OAuth admin, …) use `/auth/...` for
 * post-login admin pages. We require a more specific token.
 */
const LOGIN_PATH_RE =
  /(^|\/)(login|log-in|signin|sign-in|sign_in|sso|oauth\/authorize|account\/login|users\/sign_in|account\/signin|auth\/login|auth\/signin)(\/|$|\?)/;

/** Strong textual hints that this is a login page (when found near top of body). */
const LOGIN_TEXT_RE =
  /(sign[\s-]?in to|log[\s-]?in to|welcome back|enter your password|enter your email|forgot password)/;

/** Explicit page titles frequently used on passwordless/email-first auth flows. */
const LOGIN_TITLE_RE = /\b(sign[\s-]?in|log[\s-]?in|login)\b/;

/** Phrases that imply the user is *managing* passkeys, not authenticating. */
const PASSKEY_MANAGEMENT_RE =
  /(add a passkey|create a passkey|set up a passkey|save a passkey|configure passwordless|passwordless authentication|register a passkey|manage passkeys|your passkeys)/;

/**
 * Pure check: does the URL look like a dedicated login route?
 *
 * Exported for unit tests so we can guard against regressions where a broad
 * `/auth/` match sneaks back in.
 */
export function isLoginPath(pathname: string): boolean {
  if (!pathname) return false;
  return LOGIN_PATH_RE.test(pathname.toLowerCase());
}

/**
 * Returns true if `pageTextSample` indicates the user is reading help/marketing
 * copy *about* passkeys rather than being prompted to authenticate.
 */
export function isPasskeyManagementText(pageTextSample: string): boolean {
  if (!pageTextSample) return false;
  return PASSKEY_MANAGEMENT_RE.test(pageTextSample);
}

export type LoginSurfaceDecision =
  | { isLoginSurface: true; reason: "password-field" | "login-path-with-form-signal" | "login-text" | "passkey-button" }
  | { isLoginSurface: false; reason: "passkey-management-page" | "logged-in-email" | "registration-surface" | "otp-challenge" | "no-form-signal" | "no-signal" };

/**
 * The single source of truth for "is the current page an unauthenticated
 * login surface?". This must return `false` for any page where the user is
 * already authenticated, regardless of URL.
 */
export function decideLoginSurface(signals: LoginSurfaceSignals): LoginSurfaceDecision {
  // 1. A logged-in email anywhere in the chrome trumps every other signal.
  //    This is the key fix for the `console.cloud.google.com/auth/clients`
  //    regression: even though the URL contains `/auth/`, the page shows
  //    the user's email, so we MUST NOT prompt.
  if (signals.detectedLoggedInEmail) {
    return { isLoginSurface: false, reason: "logged-in-email" };
  }

  // 2. Pages that talk about "create a passkey" / "manage passkeys" are
  //    settings surfaces; they are accessed by an authenticated user.
  if (signals.isPasskeyManagementPage || isPasskeyManagementText(signals.pageTextSample)) {
    return { isLoginSurface: false, reason: "passkey-management-page" };
  }

  // 3. Registration forms may contain password fields, but they are not safe
  //    targets for full login autofill because that would inject an existing
  //    password into a "create account" flow.
  if (signals.isRegistrationSurface) {
    return { isLoginSurface: false, reason: "registration-surface" };
  }

  // 4. OTP/email-code challenge screens are part of auth, but they are not a
  //    credential-entry surface. Do not offer login/passkey autofill there.
  if (signals.otpFieldCount > 0 && signals.passwordFieldCount === 0 && signals.usernameFieldCount === 0) {
    return { isLoginSurface: false, reason: "otp-challenge" };
  }

  // 5. A visible password input is the strongest positive signal.
  if (signals.passwordFieldCount > 0) {
    return { isLoginSurface: true, reason: "password-field" };
  }

  // 6. URL paths only count when paired with at least one DOM-level form
  //    signal: a username/email input, a login-style button, or a passkey
  //    action button. Otherwise an admin page like `/auth/clients` would
  //    falsely match.
  const hasFormSignal =
    signals.usernameFieldCount > 0
    || signals.hasLoginActionButton
    || signals.hasPasskeyActionButton;

  if (isLoginPath(signals.pathname) && hasFormSignal) {
    return { isLoginSurface: true, reason: "login-path-with-form-signal" };
  }

  // 7. Strong textual login hints near the top of the body, but only when
  //    a login-style action exists in the DOM.
  const sample = signals.pageTextSample.slice(0, 3000);
  if (LOGIN_TEXT_RE.test(sample) && hasFormSignal) {
    return { isLoginSurface: true, reason: "login-text" };
  }

  // 8. Email-first flows often use a root URL ("/") with a terse "Sign in"
  //    page title plus a username field and generic "Continue" button. Those
  //    surfaces do not trip the stronger body-copy or URL-path heuristics, so
  //    accept the title as an explicit auth hint when a real identifier field
  //    and login-style action are both present.
  const title = signals.pageTitle?.trim().toLowerCase() ?? "";
  if (signals.usernameFieldCount > 0 && signals.hasLoginActionButton && LOGIN_TITLE_RE.test(title)) {
    return { isLoginSurface: true, reason: "login-text" };
  }

  // 9. A page offering "Sign in with passkey" without any other login
  //    surface hint is rare but legitimate (e.g. usernameless flows).
  if (signals.hasPasskeyActionButton && (isLoginPath(signals.pathname) || LOGIN_TEXT_RE.test(sample))) {
    return { isLoginSurface: true, reason: "passkey-button" };
  }

  return { isLoginSurface: false, reason: "no-form-signal" };
}

/** Convenience wrapper used by the content script. */
export function isLikelyLoginSurfaceFromSignals(signals: LoginSurfaceSignals): boolean {
  return decideLoginSurface(signals).isLoginSurface;
}
