/**
 * LumenPass – Background Service Worker (Manifest V3)
 * Handles all communication between popup/content scripts and the desktop app.
 */

import browser from "webextension-polyfill";
import { ping, searchEntries, getEntry, savePasskey, saveEntry, saveNote, saveCreditCard, getCategories, getVaultSettings, saveDisabledAutofillDomains, focusDesktop, openNewItem, openEditItem, deleteItem, isApiError, getUnlockOptions, unlockWithPassword, unlockWithPin, unlockWithBiometric } from "../lib/api";
import type { DisabledAutofillDomain, EntryItem } from "../lib/api";
import { getSettings, saveSettings, getPersistedVaultState, setPersistedVaultState } from "../lib/storage";
import type { PersistedVaultState } from "../lib/storage";
import type { ExtMessage, ExtResponse } from "../lib/utils";
import { ConnectionMonitor, type VaultState } from "./connection-monitor";
import { shouldAllowSaveLoginOffers, type SavePromptSuppressionReason } from "./save-prompt-guard";

// ─── URL helpers ──────────────────────────────────────────────────────────────

function isBrowserInternalUrl(url: string): boolean {
  if (!url) return true;
  const internalPrefixes = [
    "chrome://",
    "edge://",
    "about:",
    "favorites://",
    "safari-extension://",
    "safari-resource://",
    "webkit-fake-url://",
    "chrome-extension://",
    "moz-extension://",
    "extension://",
  ];
  return internalPrefixes.some((prefix) => url.startsWith(prefix));
}

function normalizeAutofillDomain(domain: string): string {
  const trimmed = domain.trim().toLowerCase();
  if (!trimmed) return "";
  try {
    return new URL(trimmed.includes("://") ? trimmed : `https://${trimmed}`).hostname
      .replace(/^www\./, "");
  } catch {
    return trimmed.replace(/^www\./, "");
  }
}

function pruneDisabledAutofillDomains(
  domains: DisabledAutofillDomain[] = [],
  now = Date.now(),
): DisabledAutofillDomain[] {
  const byDomain = new Map<string, DisabledAutofillDomain>();
  for (const item of domains) {
    const domain = normalizeAutofillDomain(item.domain);
    if (!domain) continue;
    if (item.expiresAt !== null && item.expiresAt <= now) continue;
    const next: DisabledAutofillDomain = {
      domain,
      disabledAt: Number.isFinite(item.disabledAt) ? item.disabledAt : now,
      expiresAt: item.expiresAt === null ? null : item.expiresAt,
    };
    const existing = byDomain.get(domain);
    if (!existing || next.disabledAt >= existing.disabledAt) {
      byDomain.set(domain, next);
    }
  }
  return Array.from(byDomain.values()).sort((a, b) => a.domain.localeCompare(b.domain));
}

async function syncVaultSettings(): Promise<void> {
  try {
    const vaultSettings = await getVaultSettings(3000);
    await saveSettings({
      domainSetting: vaultSettings.domainSetting,
      disabledAutofillDomains: pruneDisabledAutofillDomains(
        vaultSettings.disabledAutofillDomains ?? [],
      ),
    });
    logTrace("vault settings synced", vaultSettings);
  } catch {
    // Older app versions may not expose this endpoint; ignore.
  }
}

async function persistDisabledAutofillDomains(
  domains: DisabledAutofillDomain[],
): Promise<DisabledAutofillDomain[]> {
  const next = pruneDisabledAutofillDomains(domains);
  await saveDisabledAutofillDomains(next);
  await saveSettings({ disabledAutofillDomains: next });
  return next;
}

async function disableAutofillForDomain(
  domain: string,
  durationMs?: number | null,
): Promise<DisabledAutofillDomain[]> {
  const normalizedDomain = normalizeAutofillDomain(domain);
  if (!normalizedDomain) {
    throw new Error("Domain is required");
  }
  const settings = await getSettings();
  const now = Date.now();
  const nextRule: DisabledAutofillDomain = {
    domain: normalizedDomain,
    disabledAt: now,
    expiresAt:
      durationMs == null
        ? null
        : now + Math.max(0, Math.floor(durationMs)),
  };
  const next = settings.disabledAutofillDomains.filter(
    (item) => normalizeAutofillDomain(item.domain) !== normalizedDomain,
  );
  next.unshift(nextRule);
  return persistDisabledAutofillDomains(next);
}

async function enableAutofillForDomain(
  domain: string,
): Promise<DisabledAutofillDomain[]> {
  const normalizedDomain = normalizeAutofillDomain(domain);
  const settings = await getSettings();
  const next = settings.disabledAutofillDomains.filter(
    (item) => normalizeAutofillDomain(item.domain) !== normalizedDomain,
  );
  return persistDisabledAutofillDomains(next);
}

// ─── Connection health check ──────────────────────────────────────────────────

let connectionHealthy = false;
let vaultUnlocked = false;
let stateRestoredFromSession = false;
let reconnectTimer: ReturnType<typeof setTimeout> | null = null;
let reconnectDelayMs = 0;

/** Returns the persisted vault state without touching module globals.
 *  Callers decide how to use the returned data — globals are only ever
 *  updated by `checkConnection()` so a stale session read can never
 *  overwrite a live ping result. */
async function restoreStateFromSession(): Promise<PersistedVaultState | null> {
  if (stateRestoredFromSession) return null;
  stateRestoredFromSession = true;
  const persisted = await getPersistedVaultState();
  if (persisted) {
    logTrace("state restored from session (not applied)", persisted);
  }
  return persisted;
}

async function persistState(): Promise<void> {
  await setPersistedVaultState(connectionHealthy, vaultUnlocked);
}

function cancelReconnectLoop(): void {
  if (reconnectTimer) {
    clearTimeout(reconnectTimer);
    reconnectTimer = null;
  }
  reconnectDelayMs = 0;
}

function scheduleReconnect(): void {
  // Don't duplicate — a timer is already armed.
  if (reconnectTimer) return;
  if (reconnectDelayMs === 0) {
    reconnectDelayMs = 1000; // Start at 1 s
  } else {
    reconnectDelayMs = Math.min(reconnectDelayMs * 2, 30_000); // Double, cap at 30 s
  }
  reconnectTimer = setTimeout(async () => {
    reconnectTimer = null;
    await checkConnection();
    if (!connectionHealthy) {
      scheduleReconnect();
    }
  }, reconnectDelayMs);
}

// ─── Pending passkey selections (survive page navigation within a tab) ────────

interface PasskeyEntryRef {
  id: string;
  title: string;
  username: string;
  credentialId: string;
  rpId: string;
}

interface PendingPasskeySelection {
  entry: PasskeyEntryRef;
  expiresAt: number;
}

const pendingPasskeySelections = new Map<number, PendingPasskeySelection>();

function setPendingPasskey(tabId: number, entry: PasskeyEntryRef): void {
  pendingPasskeySelections.set(tabId, { entry, expiresAt: Date.now() + 90_000 });
}

function consumePendingPasskey(tabId: number, rpId: string): PasskeyEntryRef | null {
  const pending = pendingPasskeySelections.get(tabId);
  if (!pending) return null;
  pendingPasskeySelections.delete(tabId);
  if (Date.now() > pending.expiresAt) return null;
  if (pending.entry.rpId.toLowerCase() !== rpId.toLowerCase()) return null;
  return pending.entry;
}

function isActionActive(): boolean {
  return connectionHealthy && vaultUnlocked;
}

async function clearAllBadges(): Promise<void> {
  await browser.action.setBadgeText({ text: "" }).catch(() => {});

  const tabs = await browser.tabs.query({}).catch(() => []);
  await Promise.all(
    tabs
      .map((tab) => tab.id)
      .filter((tabId): tabId is number => typeof tabId === "number")
      .map((tabId) => browser.action.setBadgeText({ text: "", tabId }).catch(() => {})),
  );
}

async function refreshBadgeForActiveTab(): Promise<void> {
  if (!isActionActive()) {
    await clearAllBadges();
    return;
  }

  const tabs = await browser.tabs.query({ active: true, currentWindow: true }).catch(() => []);
  const activeTab = tabs[0];
  if (!activeTab?.id) {
    return;
  }

  await updateBadgeForTab(activeTab.id, activeTab.url ?? "");
}

async function syncActionAppearance(): Promise<void> {
  const iconPath = isActionActive() ? "icons/icon32.png" : "icons/icon32-grey.png";
  const title = !connectionHealthy
    ? "LumenPass – Desktop not running"
    : vaultUnlocked
      ? "LumenPass – Connected"
      : "LumenPass – Vault locked";

  await Promise.all([
    browser.action.setIcon({ path: { 32: iconPath } }).catch(() => {}),
    browser.action.setTitle({ title }).catch(() => {}),
    persistState(),
  ]);

  if (isActionActive()) {
    await refreshBadgeForActiveTab();
    return;
  }

  await clearAllBadges();
}

// ─── Pending login captures (tabId → credentials captured before submit) ─────

interface PendingCapture {
  username: string;
  password: string;
  fromUrl: string;
  expiresAt: number;
  fallbackTimer?: ReturnType<typeof setTimeout>;
}

const pendingLoginCaptures = new Map<number, PendingCapture>();

// ─── Pending social login captures (tabId → social auth in progress) ──────────

type SocialProvider =
  | "google"
  | "apple"
  | "facebook"
  | "github"
  | "microsoft"
  | "twitter"
  | "linkedin"
  | "other";

interface PendingSocialCapture {
  provider: SocialProvider;
  providerLabel: string;   // e.g. "Google", "Apple"
  fromUrl: string;         // full URL of the page that had the social button
  fromDomain: string;      // hostname only, for redirect detection
  expiresAt: number;
  emailHint: string;       // pre-click email hint (e.g. from Google One Tap data-hint_email)
  fromLoginSurface: true;  // capture source was verified by the content-script login detector
  loginSurfaceReason?: string;
}

const pendingSocialCaptures = new Map<number, PendingSocialCapture>();

function clearPendingSocialCapture(tabId: number): PendingSocialCapture | undefined {
  const pending = pendingSocialCaptures.get(tabId);
  pendingSocialCaptures.delete(tabId);
  return pending;
}

/** True when the tab has navigated through an OAuth provider and returned to the origin domain. */
function isOAuthReturnUrl(currentUrl: string, fromDomain: string): boolean {
  try {
    const current = new URL(currentUrl);
    // Must be back on the original site
    if (!current.hostname.endsWith(fromDomain) && current.hostname !== fromDomain) return false;
    // Must NOT look like a login/register page (that would mean we're still on the login surface)
    if (/\/(login|log-in|signin|sign-in|auth|authenticate|register|signup|sign-up)(\/|$)/i.test(current.pathname)) return false;
    return true;
  } catch {
    return false;
  }
}

async function sendSaveSocialPromptToTab(tabId: number, pending: PendingSocialCapture, username: string): Promise<void> {
  const message = {
    type: "SHOW_SAVE_SOCIAL_PROMPT" as const,
    payload: { provider: pending.provider, providerLabel: pending.providerLabel, username, fromUrl: pending.fromUrl },
  };

  const trySend = async (): Promise<void> => {
    if (!(await ensureSaveLoginOffersAllowed({ tabId, stage: "send-social-save-prompt" }))) return;

    try {
      await browser.tabs.sendMessage(tabId, message);
    } catch {
      setTimeout(async () => {
        if (!(await ensureSaveLoginOffersAllowed({ tabId, stage: "retry-social-save-prompt" }))) return;

        try { await browser.tabs.sendMessage(tabId, message); } catch { /* give up */ }
      }, 1000);
    }
  };

  setTimeout(() => { void trySend(); }, 500);
}

async function maybePromptToSaveSocialLogin(tabId: number): Promise<void> {
  const pending = pendingSocialCaptures.get(tabId);
  if (!pending) return;

  if (pending.fromLoginSurface !== true) {
    clearPendingSocialCapture(tabId);
    logTrace("social save prompt suppressed: capture did not start on login surface", {
      tabId,
      provider: pending.provider,
      fromUrl: pending.fromUrl,
    });
    return;
  }

  if (!(await ensureSaveLoginOffersAllowed({ tabId, stage: "prepare-social-save-prompt" }))) {
    clearPendingSocialCapture(tabId);
    return;
  }

  if (Date.now() > pending.expiresAt) {
    clearPendingSocialCapture(tabId);
    return;
  }

  let tab: browser.Tabs.Tab;
  try { tab = await browser.tabs.get(tabId); } catch { return; }

  const currentUrl = tab.url ?? "";
  if (isBrowserInternalUrl(currentUrl)) return;

  if (!isOAuthReturnUrl(currentUrl, pending.fromDomain)) return;

  const surface = await probeLoginSurface(tabId);
  if (surface?.isLikelyLoginSurface) {
    logTrace("social save prompt deferred: tab still appears to be login surface", {
      tabId,
      provider: pending.provider,
      currentUrl,
    });
    return;
  }

  // Try to detect logged-in username from the surface (best-effort)
  let username = pending.emailHint || "";
  if (surface && typeof surface.detectedEmail === "string" && surface.detectedEmail) {
    username = surface.detectedEmail; // post-OAuth detection takes priority
  }

  // Skip if this provider + account is already saved for the site.
  try {
    const existingAtDomain = await searchEntries("", pending.fromUrl);
    const providerRows = existingAtDomain.filter(
      (e) => !!e.socialProvider && e.socialProvider === pending.provider,
    );

    const identity =
      normalizeUsername(username) ||
      normalizeUsername(pending.emailHint);

    let duplicateSocial = false;
    if (providerRows.length === 0) {
      duplicateSocial = false;
    } else if (identity) {
      duplicateSocial = providerRows.some(
        (e) => normalizeUsername(e.username) === identity,
      );
    } else {
      // OAuth return pages often hide the account email (e.g. Notion). When we
      // cannot detect identity, treat "exactly one saved row for this provider
      // on this domain" as already covered — otherwise we nag on every login.
      // If the user keeps two undifferentiated SSO items for the same provider,
      // they will still see the prompt until one is removed or given a username.
      duplicateSocial = providerRows.length === 1;
    }

    if (duplicateSocial) {
      clearPendingSocialCapture(tabId);
      logTrace("matching social entry already exists, skipping save prompt", {
        tabId,
        provider: pending.provider,
        fromDomain: pending.fromDomain,
        identity: identity || "(none)",
        providerRowCount: providerRows.length,
      });
      return;
    }
  } catch (err) {
    logTrace("social duplicate check failed", err);
  }

  clearPendingSocialCapture(tabId);
  logTrace("sending SHOW_SAVE_SOCIAL_PROMPT to tab", { tabId, provider: pending.provider, currentUrl });
  await sendSaveSocialPromptToTab(tabId, pending, username);
}

function isLoginLikePath(url: string): boolean {
  try {
    const path = new URL(url).pathname.toLowerCase();
    return /\/(login|log-in|signin|sign-in|auth|authenticate)(\/|$)/.test(path);
  } catch {
    return false;
  }
}

function isSameBasePath(urlA: string, urlB: string): boolean {
  try {
    return new URL(urlA).pathname === new URL(urlB).pathname;
  } catch {
    return false;
  }
}

function logTrace(message: string, details?: unknown): void {
  if (details === undefined) {
    console.log(`[LumenPass SW] ${message}`);
    return;
  }
  console.log(`[LumenPass SW] ${message}`, details);
}

async function broadcastVaultStatus(): Promise<void> {
  try {
    const tabs = await browser.tabs.query({});
    const payload = { connected: connectionHealthy, vaultOpen: vaultUnlocked };
    const contentTabs = tabs.filter(
      (tab): tab is browser.Tabs.Tab & { id: number } =>
        typeof tab.id === "number" && !isBrowserInternalUrl(tab.url ?? ""),
    );
    await Promise.all(
      contentTabs.map((tab) =>
        browser.tabs.sendMessage(tab.id, { type: "VAULT_STATUS_CHANGED", payload }).catch(() => {}),
      ),
    );
  } catch {
    // ignore
  }
}

// Connection monitor: shared in-flight ping, one transient retry, and
// broadcast-on-transition. See `connection-monitor.ts` for the testable core.
const monitor = new ConnectionMonitor({
  ping: async () => {
    const r = await ping();
    return { vaultOpen: r.vaultOpen !== false };
  },
  onSettled: async (state) => {
    connectionHealthy = state.connected;
    vaultUnlocked = state.vaultOpen;
    const iconUpdate = syncActionAppearance();
    if (state.connected) {
      void syncVaultSettings();
      // Connection is healthy — cancel any in-progress backoff reconnect loop.
      cancelReconnectLoop();
    }
    await iconUpdate;
  },
  onStateChange: async (state) => {
    logTrace("vault state transition", state);
    await broadcastVaultStatus();
    // When we transition to disconnected, start an exponential-backoff
    // reconnect loop so the extension recovers automatically without
    // waiting for the next 15 s alarm tick or a manual user action.
    if (!state.connected) {
      scheduleReconnect();
    } else {
      cancelReconnectLoop();
    }
  },
});

async function checkConnection(): Promise<void> {
  await monitor.check();
}

/** Trigger a connection check at most once every `minIntervalMs`. */
async function maybeCheckConnection(minIntervalMs = 1000): Promise<void> {
  await monitor.maybeCheck(minIntervalMs);
}

function currentVaultState(): VaultState {
  return { connected: connectionHealthy, vaultOpen: vaultUnlocked };
}

function logSaveOfferSuppressed(reason: SavePromptSuppressionReason, details?: Record<string, unknown>): void {
  logTrace("save-login offer suppressed", { reason, ...details });
}

/**
 * Save-login offers are only valid while the desktop app reports an unlocked
 * vault. The background worker keeps this state fresh via `/ping` (see the
 * ConnectionMonitor above) and refreshes it before capture/prompt decisions.
 * Locked or disconnected states are silent: pending captures are discarded and
 * no content-script prompt/toast/notification is sent to the page.
 */
async function ensureSaveLoginOffersAllowed(details?: Record<string, unknown>): Promise<boolean> {
  await checkConnection();

  const result = shouldAllowSaveLoginOffers(currentVaultState());
  if (!result.allowed) {
    logSaveOfferSuppressed(result.reason!, details);
    return false;
  }

  return true;
}

function clearPendingCapture(tabId: number): PendingCapture | undefined {
  const pending = pendingLoginCaptures.get(tabId);
  if (pending?.fallbackTimer) {
    clearTimeout(pending.fallbackTimer);
  }
  pendingLoginCaptures.delete(tabId);
  return pending;
}

function normalizeUsername(username: string | undefined): string {
  return (username ?? "").trim().toLowerCase();
}

/** Plain logins only (not social / passkey rows from search). */
function isPasswordLoginSearchHit(e: EntryItem): boolean {
  if (e.kind && e.kind !== "login") return false;
  if (e.socialProvider) return false;
  return true;
}

async function gatherDomainMatchedEntries(url: string, fromUrl?: string): Promise<EntryItem[]> {
  const trySearch = async (searchUrl: string): Promise<EntryItem[]> => {
    try {
      return await searchEntries("", searchUrl);
    } catch {
      return [];
    }
  };

  let existing = await trySearch(url);
  if (fromUrl && fromUrl !== url) {
    const fromExisting = await trySearch(fromUrl);
    const seen = new Set(existing.map((e) => e.id));
    for (const e of fromExisting) {
      if (!seen.has(e.id)) {
        seen.add(e.id);
        existing.push(e);
      }
    }
  }
  return existing.filter(isPasswordLoginSearchHit);
}

type SavePromptMode = "new" | "update" | "multi-choice";

interface SaveCandidateEntry {
  id: string;
  title: string;
}

interface SaveLoginPromptPayload {
  username: string;
  password: string;
  mode: SavePromptMode;
  existingEntryId?: string;
  existingTitle?: string;
  candidates?: SaveCandidateEntry[];
}

/**
 * Decide whether to skip the save UI, show "save new", "update existing", or
 * "multi-choice" (when multiple records share the same domain+username but
 * have different passwords — common on localhost where port is ignored).
 * Compares captured password to vault entries via GET /entry/:id (search hits
 * do not include passwords).
 */
async function classifyLoginSavePrompt(
  currentUrl: string,
  username: string,
  password: string,
  fromUrl?: string,
): Promise<{ action: "skip" } | { action: "prompt"; payload: SaveLoginPromptPayload }> {
  try {
    const candidates = await gatherDomainMatchedEntries(currentUrl, fromUrl);
    const normalizedUsername = normalizeUsername(username);

    const usernameMatches = normalizedUsername
      ? candidates.filter((e) => normalizeUsername(e.username) === normalizedUsername)
      : candidates;

    const mismatches: EntryItem[] = [];

    for (const entry of usernameMatches.slice(0, 8)) {
      let storedPassword = "";
      try {
        const detail = await getEntry(entry.id, 8000);
        storedPassword = detail.password ?? "";
      } catch {
        continue;
      }
      if (storedPassword === password) {
        return { action: "skip" };
      }
      mismatches.push(entry);
    }

    if (mismatches.length > 1) {
      return {
        action: "prompt",
        payload: {
          username,
          password,
          mode: "multi-choice",
          candidates: mismatches.map((e) => ({ id: e.id, title: e.title })),
        },
      };
    }

    if (mismatches.length === 1) {
      return {
        action: "prompt",
        payload: {
          username,
          password,
          mode: "update",
          existingEntryId: mismatches[0].id,
          existingTitle: mismatches[0].title,
        },
      };
    }

    return {
      action: "prompt",
      payload: { username, password, mode: "new" },
    };
  } catch (error) {
    logTrace("classifyLoginSavePrompt failed", error);
    return { action: "prompt", payload: { username, password, mode: "new" } };
  }
}

interface LoginSurfaceProbeResult {
  isLikelyLoginSurface: boolean;
  detectedEmail?: string;
  url?: string;
  passwordFieldCount?: number;
  otpFieldCount?: number;
}

async function probeLoginSurface(tabId: number): Promise<LoginSurfaceProbeResult | null> {
  try {
    const response = await browser.tabs.sendMessage(tabId, {
      type: "GET_LOGIN_SURFACE_STATE",
    });
    if (response && typeof response.isLikelyLoginSurface === "boolean") {
      return response as LoginSurfaceProbeResult;
    }
  } catch {
    // Content script may not be ready yet.
  }

  return null;
}

async function sendSavePromptToTab(tabId: number, payload: SaveLoginPromptPayload): Promise<void> {
  const message = {
    type: "SHOW_SAVE_PROMPT" as const,
    payload,
  };

  const sendPrompt = async (): Promise<void> => {
    if (!(await ensureSaveLoginOffersAllowed({ tabId, stage: "send-save-prompt" }))) return;

    try {
      await browser.tabs.sendMessage(tabId, message);
    } catch {
      setTimeout(async () => {
        if (!(await ensureSaveLoginOffersAllowed({ tabId, stage: "retry-save-prompt" }))) return;

        try {
          await browser.tabs.sendMessage(tabId, message);
        } catch {
          // Give up if the destination tab no longer has a ready content script.
        }
      }, 1000);
    }
  };

  setTimeout(() => { void sendPrompt(); }, 500);
}

async function maybePromptToSaveLogin(
  tabId: number,
  reason: "url-change" | "tab-complete" | "fallback" | "fallback-spa",
): Promise<void> {
  const pending = pendingLoginCaptures.get(tabId);
  if (!pending) return;

  if (!(await ensureSaveLoginOffersAllowed({ tabId, reason, stage: "prepare-save-prompt" }))) {
    clearPendingCapture(tabId);
    return;
  }

  if (Date.now() > pending.expiresAt) {
    clearPendingCapture(tabId);
    return;
  }

  let tab: browser.Tabs.Tab;
  try {
    tab = await browser.tabs.get(tabId);
  } catch {
    return;
  }

  const currentUrl = tab.url ?? "";
  if (isBrowserInternalUrl(currentUrl)) {
    return;
  }

  const samePath = isSameBasePath(currentUrl, pending.fromUrl);
  const loginLike = isLoginLikePath(currentUrl);

  if (reason === "fallback-spa") {
  } else if (reason === "fallback") {
    if (samePath || loginLike) {
      const surface = await probeLoginSurface(tabId);
      logTrace("fallback login surface probe", { tabId, currentUrl, surface });
      if (!surface || surface.isLikelyLoginSurface) {
        return;
      }
    }
  } else if (samePath || loginLike) {
    return;
  }

  const classification = await classifyLoginSavePrompt(
    currentUrl,
    pending.username,
    pending.password,
    pending.fromUrl,
  );
  if (classification.action === "skip") {
    clearPendingCapture(tabId);
    logTrace("same username + password as vault — skipping save prompt", {
      tabId,
      username: pending.username,
      currentUrl,
      reason,
    });
    return;
  }

  clearPendingCapture(tabId);
  logTrace("sending SHOW_SAVE_PROMPT to tab", {
    tabId,
    username: pending.username,
    currentUrl,
    reason,
    mode: classification.payload.mode,
  });
  await sendSavePromptToTab(tabId, classification.payload);
}

// ─── Badge count ──────────────────────────────────────────────────────────────

async function updateBadgeForTab(tabId: number, url: string): Promise<void> {
  if (!isActionActive() || isBrowserInternalUrl(url)) {
    await browser.action.setBadgeText({ text: "", tabId }).catch(() => {});
    return;
  }
  try {
    logTrace("badge search start", { tabId, url });
    const results = await searchEntries("", url);
    const count = results.length;
    logTrace("badge search result", { tabId, count });
    await browser.action.setBadgeBackgroundColor({ color: "#444ce7" }).catch(() => {});
    await browser.action.setBadgeText({
      text: count > 0 ? String(count) : "",
      tabId,
    }).catch(() => {});
  } catch (error) {
    logTrace("badge search failed", error);
    await browser.action.setBadgeText({ text: "", tabId }).catch(() => {});
  }
}

browser.tabs.onActivated.addListener(async ({ tabId }) => {
  let url = "";
  try {
    const tab = await browser.tabs.get(tabId);
    url = tab.url ?? "";
  } catch {
    // Tab may have been closed already.
  }
  await updateBadgeForTab(tabId, url);
});

browser.tabs.onUpdated.addListener(async (tabId, changeInfo) => {
  if (changeInfo.url !== undefined) {
    await updateBadgeForTab(tabId, changeInfo.url);
    if (pendingLoginCaptures.has(tabId)) {
      await maybePromptToSaveLogin(tabId, "url-change");
    }
    if (pendingSocialCaptures.has(tabId)) {
      await maybePromptToSaveSocialLogin(tabId);
    }
  }

  if (changeInfo.status === "complete") {
    let currentUrl = "";
    try {
      currentUrl = (await browser.tabs.get(tabId)).url ?? "";
    } catch {
      // Ignore if the tab is gone.
    }
    await updateBadgeForTab(tabId, currentUrl);
    if (pendingLoginCaptures.has(tabId)) {
      await maybePromptToSaveLogin(tabId, "tab-complete");
    }
    if (pendingSocialCaptures.has(tabId)) {
      await maybePromptToSaveSocialLogin(tabId);
    }
  }
});

browser.tabs.onRemoved.addListener((tabId) => {
  clearPendingCapture(tabId);
  clearPendingSocialCapture(tabId);
});

// ─── Cold-start initialisation ─────────────────────────────────────────────────
// The "try ping → fallback to session → sync UI" dance must run in order.
// Calling syncActionAppearance() *before* checkConnection() can persist
// stale {false,false} from session storage and overwrite a concurrent
// successful ping from the popup's message-handler path (Bug 1).
async function coldStartInit(): Promise<void> {
  const persisted = await restoreStateFromSession();

  // 1. Try to reach the desktop — this is the source of truth.
  await checkConnection();

  // 2. If the ping failed but we have recently-valid session state, use it
  //    as a temporary optimistic fallback (the icon will show "connected"
  //    until the next health-check confirmation or refutation).
  if (!connectionHealthy && persisted?.connected) {
    connectionHealthy = persisted.connected;
    vaultUnlocked = persisted.vaultOpen ?? false;
    logTrace("cold start: ping failed, falling back to session", persisted);
  }

  // 3. Synchronise UI (icon, badge, title) with whatever state we settled on.
  await syncActionAppearance();

  // 4. If we're still disconnected after everything, start the reconnect loop.
  if (!connectionHealthy) {
    scheduleReconnect();
  }
}

// Check connection on startup, every 15 seconds via alarm, and any time the
// user shifts focus to a different tab/window (covers cases where chrome.alarms
// is throttled or skipped while the SW is dormant — notably Safari MV3).
browser.runtime.onStartup.addListener(() => {
  void coldStartInit();
});
browser.runtime.onInstalled.addListener(() => {
  void checkConnection();
  void setupContextMenus();
});
browser.alarms.create("healthCheck", { periodInMinutes: 0.25 });
browser.alarms.onAlarm.addListener((alarm) => {
  if (alarm.name === "healthCheck") void checkConnection();
});

browser.tabs.onActivated.addListener(() => { void maybeCheckConnection(2000); });
if (browser.windows && browser.windows.onFocusChanged) {
  browser.windows.onFocusChanged.addListener((windowId) => {
    // -1 means "no focused window" — ignore that transition.
    if (windowId === browser.windows.WINDOW_ID_NONE) return;
    void maybeCheckConnection(2000);
  });
}

// Cold-start: on first module evaluation (SW restart after idle termination
// on Edge/Chromium MV3) run the ordered init sequence that avoids the race.
void coldStartInit();

// Ensure context menus exist after a service-worker cold start (the
// onInstalled handler only runs on install/update — service workers can be
// terminated and restarted at any point during a session on Chromium MV3).
void setupContextMenus();

// ─── Right-click context menu (Chrome / Edge / Firefox) ───────────────────────

const CTX_MENU_PARENT = "lumenpass-root";
const CTX_MENU_RELOAD = "lumenpass-reload-extension";
const CTX_MENU_RELOAD_DIVIDER = "lumenpass-reload-divider";
const CTX_MENU_NEW_LOGIN = "lumenpass-new-login";
const CTX_MENU_NEW_NOTE = "lumenpass-new-note";
const CTX_MENU_GEN_PASSWORD = "lumenpass-generate-password";
const CTX_MENU_FILL_DIVIDER = "lumenpass-fill-divider";
const CTX_MENU_FILL_EMAIL = "lumenpass-fill-email";
const CTX_MENU_FILL_USERNAME = "lumenpass-fill-username";
const CTX_MENU_FILL_OTP = "lumenpass-fill-otp";

async function setupContextMenus(): Promise<void> {
  if (!browser.contextMenus) return;
  try {
    await browser.contextMenus.removeAll();
  } catch {
    // ignore — first call after install has nothing to remove
  }

  const contexts: browser.Menus.ContextType[] = ["page", "selection", "link", "frame", "editable"];

  try {
    browser.contextMenus.create({
      id: CTX_MENU_PARENT,
      title: "LumenPass",
      contexts,
      documentUrlPatterns: ["http://*/*", "https://*/*"],
    });
    browser.contextMenus.create({
      id: CTX_MENU_RELOAD,
      parentId: CTX_MENU_PARENT,
      title: "Reload Extension",
      contexts,
      documentUrlPatterns: ["http://*/*", "https://*/*"],
    });
    browser.contextMenus.create({
      id: CTX_MENU_RELOAD_DIVIDER,
      parentId: CTX_MENU_PARENT,
      type: "separator",
      contexts,
      documentUrlPatterns: ["http://*/*", "https://*/*"],
    });
    browser.contextMenus.create({
      id: CTX_MENU_NEW_LOGIN,
      parentId: CTX_MENU_PARENT,
      title: "Create Login for this site",
      contexts,
      documentUrlPatterns: ["http://*/*", "https://*/*"],
    });
    browser.contextMenus.create({
      id: CTX_MENU_NEW_NOTE,
      parentId: CTX_MENU_PARENT,
      title: "Create Quick Note",
      contexts,
      documentUrlPatterns: ["http://*/*", "https://*/*"],
    });
    browser.contextMenus.create({
      id: CTX_MENU_GEN_PASSWORD,
      parentId: CTX_MENU_PARENT,
      title: "Password Generator",
      contexts,
      documentUrlPatterns: ["http://*/*", "https://*/*"],
    });
    browser.contextMenus.create({
      id: CTX_MENU_FILL_DIVIDER,
      parentId: CTX_MENU_PARENT,
      type: "separator",
      contexts,
      documentUrlPatterns: ["http://*/*", "https://*/*"],
    });
    browser.contextMenus.create({
      id: CTX_MENU_FILL_EMAIL,
      parentId: CTX_MENU_PARENT,
      title: "Fill Email",
      contexts,
      documentUrlPatterns: ["http://*/*", "https://*/*"],
    });
    browser.contextMenus.create({
      id: CTX_MENU_FILL_USERNAME,
      parentId: CTX_MENU_PARENT,
      title: "Fill Username",
      contexts,
      documentUrlPatterns: ["http://*/*", "https://*/*"],
    });
    browser.contextMenus.create({
      id: CTX_MENU_FILL_OTP,
      parentId: CTX_MENU_PARENT,
      title: "Fill OTP",
      contexts,
      documentUrlPatterns: ["http://*/*", "https://*/*"],
    });
  } catch (error) {
    logTrace("setupContextMenus failed", error);
  }
}

async function notifyTab(tabId: number, message: string, tone: "info" | "error" = "info"): Promise<void> {
  try {
    await browser.scripting.executeScript({
      target: { tabId },
      func: (text: string, variant: "info" | "error") => {
        const ID = "lumenpass-ctx-toast";
        document.getElementById(ID)?.remove();
        const el = document.createElement("div");
        el.id = ID;
        el.textContent = text;
        Object.assign(el.style, {
          position: "fixed",
          bottom: "24px",
          right: "24px",
          zIndex: "2147483647",
          padding: "10px 14px",
          borderRadius: "10px",
          font: "500 13px/1.4 -apple-system, BlinkMacSystemFont, Segoe UI, Roboto, sans-serif",
          color: "#fff",
          background: variant === "error" ? "rgba(190, 18, 60, 0.95)" : "rgba(17, 24, 39, 0.95)",
          boxShadow: "0 8px 24px rgba(15,23,42,0.25)",
          pointerEvents: "none",
          opacity: "0",
          transform: "translateY(8px)",
          transition: "opacity 160ms ease, transform 160ms ease",
        } as Partial<CSSStyleDeclaration>);
        document.documentElement.appendChild(el);
        requestAnimationFrame(() => {
          el.style.opacity = "1";
          el.style.transform = "translateY(0)";
        });
        setTimeout(() => {
          el.style.opacity = "0";
          el.style.transform = "translateY(8px)";
          setTimeout(() => el.remove(), 200);
        }, 2200);
      },
      args: [message, tone],
    });
  } catch {
    // Tab may be on a privileged URL (chrome://, etc.) where scripting is
    // forbidden. Silently ignore — the desktop app will still surface the
    // result via its own UI.
  }
}

if (browser.contextMenus?.onClicked) {
  browser.contextMenus.onClicked.addListener(async (info, tab) => {
    const tabId = tab?.id;
    const targetFrameId = typeof info.frameId === "number" ? info.frameId : 0;
    const tabUrl = tab?.url ?? "";
    const targetUrl = info.frameUrl ?? info.pageUrl ?? tabUrl;
    const tabTitle = tab?.title ?? "";

    if (
      info.menuItemId !== CTX_MENU_RELOAD &&
      info.menuItemId !== CTX_MENU_NEW_LOGIN &&
      info.menuItemId !== CTX_MENU_NEW_NOTE &&
      info.menuItemId !== CTX_MENU_GEN_PASSWORD &&
      info.menuItemId !== CTX_MENU_FILL_EMAIL &&
      info.menuItemId !== CTX_MENU_FILL_USERNAME &&
      info.menuItemId !== CTX_MENU_FILL_OTP
    ) {
      return;
    }

    if (info.menuItemId === CTX_MENU_RELOAD) {
      browser.runtime.reload();
      return;
    }

    if (isBrowserInternalUrl(targetUrl)) {
      if (tabId !== undefined) {
        await notifyTab(tabId, "LumenPass cannot run on this page.", "error");
      }
      return;
    }

    // Password Generator runs entirely in-page — no desktop/vault required.
    if (info.menuItemId === CTX_MENU_GEN_PASSWORD) {
      if (tabId === undefined) return;
      try {
        await browser.tabs.sendMessage(tabId, {
          type: "OPEN_PASSWORD_GENERATOR",
          payload: { url: targetUrl },
        }, { frameId: targetFrameId });
      } catch (error) {
        logTrace("context-menu generate-password failed (tab message)", error);
        await notifyTab(tabId, "Refresh the page and try again.", "error");
      }
      return;
    }

    if (info.menuItemId === CTX_MENU_FILL_EMAIL || info.menuItemId === CTX_MENU_FILL_USERNAME || info.menuItemId === CTX_MENU_FILL_OTP) {
      if (tabId === undefined) return;
      await checkConnection();
      if (!connectionHealthy) {
        await notifyTab(tabId, "Open LumenPass Desktop to continue.", "error");
        return;
      }
      if (!vaultUnlocked) {
        await notifyTab(tabId, "Unlock your vault in LumenPass Desktop.", "error");
        return;
      }
      try {
        await browser.tabs.sendMessage(tabId, {
          type:
            info.menuItemId === CTX_MENU_FILL_EMAIL
              ? "OPEN_FILL_EMAIL"
              : info.menuItemId === CTX_MENU_FILL_USERNAME
                ? "OPEN_FILL_USERNAME"
                : "OPEN_FILL_OTP",
          payload: { url: targetUrl },
        }, { frameId: targetFrameId });
      } catch (error) {
        logTrace("context-menu fill-email/username failed (tab message)", error);
        await notifyTab(tabId, "Refresh the page and try again.", "error");
      }
      return;
    }

    await checkConnection();
    if (!connectionHealthy) {
      if (tabId !== undefined) {
        await notifyTab(tabId, "Open LumenPass Desktop to continue.", "error");
      }
      return;
    }
    if (!vaultUnlocked) {
      if (tabId !== undefined) {
        await notifyTab(tabId, "Unlock your vault in LumenPass Desktop.", "error");
      }
      return;
    }

    let host = "";
    try { host = new URL(targetUrl).hostname.replace(/^www\./, ""); } catch { /* ignore */ }

    if (info.menuItemId === CTX_MENU_NEW_LOGIN) {
      if (tabId === undefined) return;
      try {
        await browser.tabs.sendMessage(tabId, {
          type: "OPEN_QUICK_CREATE_LOGIN",
          payload: {
            url: targetUrl,
            title: tabTitle || host,
          },
        }, { frameId: targetFrameId });
      } catch (error) {
        logTrace("context-menu new-login failed (tab message)", error);
        await notifyTab(tabId, "Refresh the page and try again.", "error");
      }
      return;
    }

    if (info.menuItemId === CTX_MENU_NEW_NOTE) {
      if (tabId === undefined) return;
      const selection = (info.selectionText ?? "").trim();
      const noteTitle = tabTitle || host || "Quick note";
      try {
        await browser.tabs.sendMessage(tabId, {
          type: "OPEN_QUICK_CREATE_NOTE",
          payload: {
            url: targetUrl,
            title: noteTitle,
            selection,
          },
        }, { frameId: targetFrameId });
      } catch (error) {
        logTrace("context-menu new-note failed (tab message)", error);
        await notifyTab(tabId, "Refresh the page and try again.", "error");
      }
    }
  });
}

// ─── Message router ───────────────────────────────────────────────────────────

browser.runtime.onMessage.addListener(
  (rawMessage: unknown, sender): Promise<ExtResponse> => {
    const message = rawMessage as ExtMessage;
    return restoreStateFromSession().then(() => handleMessage(message, sender));
  },
);

async function handleMessage(message: ExtMessage, sender?: browser.Runtime.MessageSender): Promise<ExtResponse> {
  try {
    switch (message.type) {
      case "PING": {
        await checkConnection();
        logTrace("message PING", { connectionHealthy, vaultUnlocked });
        return {
          ok: connectionHealthy,
          data: {
            connected: connectionHealthy,
            vaultOpen: vaultUnlocked,
          },
          ...(connectionHealthy ? {} : { error: "Cannot reach LumenPass Desktop" }),
        };
      }

      case "GET_VAULT_STATUS": {
        return { ok: true, data: { connected: connectionHealthy, vaultOpen: vaultUnlocked } };
      }

      case "FOCUS_DESKTOP": {
        try { await focusDesktop(); } catch { /* ignore */ }
        return { ok: true };
      }

      case "OPEN_NEW_ITEM": {
        await openNewItem();
        return { ok: true };
      }

      case "OPEN_EDIT_ITEM": {
        const { id } = (message.payload ?? {}) as { id?: string };
        const trimmedId = id?.trim() ?? "";
        if (!trimmedId) {
          return { ok: false, error: "Item id is required" };
        }
        await openEditItem(trimmedId);
        return { ok: true };
      }

      case "DELETE_ITEM": {
        const { id } = (message.payload ?? {}) as { id?: string };
        const trimmedId = id?.trim() ?? "";
        if (!trimmedId) {
          return { ok: false, error: "Item id is required" };
        }
        await deleteItem(trimmedId);
        return { ok: true };
      }

      case "GET_UNLOCK_OPTIONS": {
        try {
          const options = await getUnlockOptions();
          const prevOpen = vaultUnlocked;
          connectionHealthy = true;
          vaultUnlocked = options.locked === false;
          await syncActionAppearance();
          if (prevOpen !== vaultUnlocked) {
            await broadcastVaultStatus();
          }
          return { ok: true, data: options };
        } catch (error) {
          logTrace("GET_UNLOCK_OPTIONS failed", error);
          return {
            ok: false,
            error: isApiError(error) ? error.message : "Cannot reach LumenPass Desktop",
          };
        }
      }

      case "UNLOCK_WITH_PASSWORD": {
        const { password } = (message.payload ?? {}) as { password?: string };
        try {
          const result = await unlockWithPassword(password ?? "");
          if (result.ok) {
            vaultUnlocked = true;
            connectionHealthy = true;
            await syncActionAppearance();
            await broadcastVaultStatus();
          }
          return { ok: true, data: result };
        } catch (error) {
          return {
            ok: false,
            error: isApiError(error) ? error.message : String(error),
          };
        }
      }

      case "UNLOCK_WITH_PIN": {
        const { pin } = (message.payload ?? {}) as { pin?: string };
        try {
          const result = await unlockWithPin(pin ?? "");
          if (result.ok) {
            vaultUnlocked = true;
            connectionHealthy = true;
            await syncActionAppearance();
            await broadcastVaultStatus();
          }
          return { ok: true, data: result };
        } catch (error) {
          return {
            ok: false,
            error: isApiError(error) ? error.message : String(error),
          };
        }
      }

      case "UNLOCK_WITH_BIOMETRIC": {
        try {
          const result = await unlockWithBiometric();
          if (result.ok) {
            vaultUnlocked = true;
            connectionHealthy = true;
            await syncActionAppearance();
            await broadcastVaultStatus();
          }
          return { ok: true, data: result };
        } catch (error) {
          return {
            ok: false,
            error: isApiError(error) ? error.message : String(error),
          };
        }
      }

      case "SEARCH_ENTRIES": {
        const payload = message.payload as { query: string; url?: string; submitUrl?: string; type?: string };
        logTrace("message SEARCH_ENTRIES start", payload);
        const currentSettings = await getSettings();
        const results = await searchEntries(
          payload.query,
          payload.url,
          payload.submitUrl,
          undefined,
          payload.type,
          currentSettings.domainSetting,
        );
        logTrace("message SEARCH_ENTRIES result", {
          count: results.length,
          titles: results.slice(0, 5).map((entry) => entry.title),
        });
        return { ok: true, data: results };
      }

      case "GET_ENTRY": {
        const { id } = message.payload as { id: string };
        logTrace("message GET_ENTRY start", { id });
        const entry = await getEntry(id);
        logTrace("message GET_ENTRY result", {
          id: entry.id,
          title: entry.title,
        });
        return { ok: true, data: entry };
      }

      case "GET_CATEGORIES": {
        const categories = await getCategories();
        logTrace("message GET_CATEGORIES result", {
          count: categories.length,
          names: categories.slice(0, 10).map((category) => category.name),
        });
        return { ok: true, data: categories };
      }

      case "AUTOFILL": {
        const { tabId, entry } = message.payload as {
          tabId: number;
          entry: { username: string; password: string; totp?: string };
        };
        await browser.scripting.executeScript({
          target: { tabId },
          func: performAutofill,
          args: [entry],
        });
        return { ok: true };
      }

      case "AUTOFILL_GENERATED_PASSWORD": {
        const { tabId, password } = message.payload as {
          tabId: number;
          password: string;
        };
        await browser.scripting.executeScript({
          target: { tabId },
          func: performGeneratedPasswordFill,
          args: [password],
        });
        return { ok: true };
      }

      case "GET_SETTINGS": {
        if (connectionHealthy) {
          await syncVaultSettings();
        }
        const settings = await getSettings();
        return { ok: true, data: settings };
      }

      case "SAVE_SETTINGS": {
        const partial = message.payload as Record<string, unknown>;
        await saveSettings(partial);
        await checkConnection();
        return { ok: true };
      }

      case "DISABLE_AUTOFILL_DOMAIN": {
        const payload = message.payload as { domain?: string; durationMs?: number | null };
        const domains = await disableAutofillForDomain(
          payload.domain ?? "",
          payload.durationMs,
        );
        return { ok: true, data: { disabledAutofillDomains: domains } };
      }

      case "ENABLE_AUTOFILL_DOMAIN": {
        const payload = message.payload as { domain?: string };
        const domains = await enableAutofillForDomain(payload.domain ?? "");
        return { ok: true, data: { disabledAutofillDomains: domains } };
      }

      case "GET_CURRENT_TAB_URL": {
        const tabs = await browser.tabs.query({ active: true, currentWindow: true });
        return { ok: true, data: { url: tabs[0]?.url ?? "" } };
      }

      case "SET_PENDING_PASSKEY": {
        const tabId = sender?.tab?.id;
        if (tabId !== undefined) {
          const { entry } = message.payload as { entry: PasskeyEntryRef };
          setPendingPasskey(tabId, entry);
          console.log("[LumenPass SW] SET_PENDING_PASSKEY tab:", tabId, "entry:", entry.title);
        }
        return { ok: true };
      }

      case "PASSKEY_GET": {
        const { rpId, origin } = message.payload as { rpId: string; origin: string };
        const tabId = sender?.tab?.id;

        // If the user already selected an entry (e.g., proactive popup before navigation),
        // auto-assert it without showing the picker again.
        if (tabId !== undefined) {
          const preSelected = consumePendingPasskey(tabId, rpId);
          if (preSelected) {
            console.log("[LumenPass SW] PASSKEY_GET auto-selecting pre-selected entry:", preSelected.title);
            return { ok: true, data: [preSelected], autoSelectId: preSelected.id } as unknown as { ok: boolean; data: unknown };
          }
        }

        const url = origin ?? `https://${rpId}`;
        console.log("[LumenPass SW] PASSKEY_GET rpId:", rpId, "url:", url);
        const results = await searchEntries("", url, undefined, 15_000);
        console.log("[LumenPass SW] search results:", results.map((r) => r.title));
        const passkeyEntries: Array<{ id: string; title: string; username: string; credentialId: string; rpId: string }> = [];
        for (const entry of results) {
          const detail = await getEntry(entry.id, 15_000);
          const fieldLabels = detail.customFields?.map((f) => f.label) ?? [];
          console.log("[LumenPass SW] entry", entry.title, "fields:", fieldLabels);
          const rpField = detail.customFields?.find((f) => /^kpex_passkey_relying_party/i.test(f.label));
          const credField = detail.customFields?.find((f) => /^kpex_passkey_credential_id/i.test(f.label));
          if (rpField && credField) {
            passkeyEntries.push({ id: entry.id, title: entry.title, username: entry.username, credentialId: credField.value, rpId: rpField.value });
          }
        }
        console.log("[LumenPass SW] passkey entries found:", passkeyEntries.length);
        return { ok: true, data: passkeyEntries };
      }

      case "PASSKEY_FIND_MATCHES": {
        const { rpId, username, origin } = message.payload as {
          rpId: string;
          username: string;
          origin: string;
        };
        const normalizedRpId = rpId.trim().toLowerCase();
        const normalizedUsername = username.trim().toLowerCase();

        const results = await searchEntries(
          "",
          origin ?? `https://${rpId}`,
          undefined,
          15_000,
        );
        const matches: Array<{
          id: string;
          title: string;
          username: string;
          rpId: string;
          credentialId: string;
          usernameMatched: boolean;
        }> = [];

        for (const entry of results) {
          const detail = await getEntry(entry.id, 15_000);
          const rpField = detail.customFields?.find((f) => /^kpex_passkey_relying_party/i.test(f.label));
          const credField = detail.customFields?.find((f) => /^kpex_passkey_credential_id/i.test(f.label));
          const passkeyUsernameField = detail.customFields?.find((f) => /^kpex_passkey_username/i.test(f.label));
          const existingUsername = (passkeyUsernameField?.value || detail.username || "").trim().toLowerCase();

          if (!rpField || !credField) continue;
          if (rpField.value.trim().toLowerCase() !== normalizedRpId) continue;

          const usernameMatched = !!normalizedUsername && existingUsername === normalizedUsername;

          matches.push({
            id: detail.id,
            title: detail.title,
            username: detail.username ?? passkeyUsernameField?.value ?? "",
            rpId: rpField.value,
            credentialId: credField.value,
            usernameMatched,
          });
        }

        matches.sort((a, b) => Number(b.usernameMatched) - Number(a.usernameMatched));

        console.log("[LumenPass SW] passkey site matches found:", matches.length, "usernameMatches:", matches.filter((m) => m.usernameMatched).length);
        return { ok: true, data: matches };
      }

      case "PASSKEY_CREATE": {
        const { rpId, rpName, userId, userName, challenge, origin, existingEntryId } = message.payload as {
          rpId: string; rpName: string; userId: number[]; userName: string;
          userDisplayName: string; challenge: number[]; origin: string; existingEntryId?: string;
        };
        console.log("[LumenPass SW] PASSKEY_CREATE rpId:", rpId, "userName:", userName);

        // ── Generate EC P-256 key pair ──
        const keyPair = await crypto.subtle.generateKey(
          { name: "ECDSA", namedCurve: "P-256" },
          true,
          ["sign", "verify"],
        );
        const pkcs8 = new Uint8Array(await crypto.subtle.exportKey("pkcs8", keyPair.privateKey));
        const spki  = new Uint8Array(await crypto.subtle.exportKey("spki",  keyPair.publicKey));

        const privateKeyPem =
          "-----BEGIN PRIVATE KEY-----\n" +
          btoa(String.fromCharCode(...pkcs8)).match(/.{1,64}/g)!.join("\n") +
          "\n-----END PRIVATE KEY-----";

        // ── Credential ID (16 random bytes) ──
        const credentialId = crypto.getRandomValues(new Uint8Array(16));
        const credIdB64 = btoa(String.fromCharCode(...credentialId))
          .replace(/\+/g, "-").replace(/\//g, "_").replace(/=/g, "");

        // ── Extract P-256 public key coordinates from SPKI ──
        // P-256 SPKI = 91 bytes: 27 header bytes + 0x04 + x(32) + y(32)
        const xBytes = spki.slice(27, 59);
        const yBytes = spki.slice(59, 91);

        // ── Build COSE key (CBOR) ──
        const coseKey = cborEncode({ t: "map", v: [
          [{ t: "uint", v: 1  }, { t: "uint", v: 2  }], // kty: EC2
          [{ t: "uint", v: 3  }, { t: "nint", v: -7 }], // alg: ES256
          [{ t: "nint", v: -1 }, { t: "uint", v: 1  }], // crv: P-256
          [{ t: "nint", v: -2 }, { t: "bstr", v: xBytes }],
          [{ t: "nint", v: -3 }, { t: "bstr", v: yBytes }],
        ]});

        // ── Build attestedCredentialData ──
        const aaguid    = new Uint8Array(16);
        const credIdLen = new Uint8Array(2);
        new DataView(credIdLen.buffer).setUint16(0, credentialId.length, false);
        const attestedCred = concatBytes([aaguid, credIdLen, credentialId, coseKey]);

        // ── Build authData ──
        const rpIdHash  = new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(rpId)));
        const flags     = new Uint8Array([0x45]); // UP | UV | AT
        const signCount = new Uint8Array(4);
        const authData  = concatBytes([rpIdHash, flags, signCount, attestedCred]);

        // ── Build attestationObject (CBOR) ──
        const attestationObject = cborEncode({ t: "map", v: [
          [{ t: "tstr", v: "fmt"      }, { t: "tstr", v: "none" }],
          [{ t: "tstr", v: "attStmt"  }, { t: "map",  v: []     }],
          [{ t: "tstr", v: "authData" }, { t: "bstr", v: authData }],
        ]});

        // ── Build clientDataJSON ──
        const challengeB64 = btoa(String.fromCharCode(...challenge))
          .replace(/\+/g, "-").replace(/\//g, "_").replace(/=/g, "");
        const clientDataJSON = new TextEncoder().encode(JSON.stringify({
          type: "webauthn.create", challenge: challengeB64, origin, crossOrigin: false,
        }));

        // ── User handle (base64url of userId bytes) ──
        const userHandleB64 = btoa(String.fromCharCode(...userId))
          .replace(/\+/g, "-").replace(/\//g, "_").replace(/=/g, "");

        // ── Save to desktop vault ──
        try {
          await savePasskey({
            title: rpName || rpId,
            url: origin,
            rpId,
            username: userName,
            credentialId: credIdB64,
            privateKey: privateKeyPem,
            userHandle: userHandleB64,
            existingEntryId,
          });
          console.log("[LumenPass SW] passkey saved to desktop vault");
        } catch (e) {
          console.warn("[LumenPass SW] failed to save passkey to desktop:", e);
        }

        return {
          ok: true,
          data: {
            credentialId: Array.from(credentialId),
            clientDataJSON: Array.from(clientDataJSON),
            attestationObject: Array.from(attestationObject),
            authData: Array.from(authData),
          },
        };
      }

      case "PASSKEY_ASSERT": {
        const { entryId, rpId, challenge, origin } = message.payload as {
          entryId: string; rpId: string; challenge: number[]; origin: string;
        };
        console.log("[LumenPass SW] PASSKEY_ASSERT entryId:", entryId, "rpId:", rpId);
        const detail = await getEntry(entryId, 15_000);
        const fields = detail.customFields ?? [];
        const allFieldLabels = fields.map((f) => f.label);
        console.log("[LumenPass SW] all custom field labels:", allFieldLabels);
        const findFieldByLabel = (label: string): { label: string; value: string } | undefined =>
          fields.find((f) => f.label.trim().toLowerCase() == label);
        const privateKeyField =
          findFieldByLabel("kpex_passkey_private_key_pem") ??
          findFieldByLabel("kpex_passkey_private_key_pbf") ??
          fields.find((f) => /^kpex_passkey_private_key/i.test(f.label));
        const credIdField = fields.find((f) => /^kpex_passkey_credential_id/i.test(f.label));
        const userHandleField = fields.find((f) => /^kpex_passkey_user_handle/i.test(f.label));
        console.log("[LumenPass SW] privateKeyField found:", !!privateKeyField, "label:", privateKeyField?.label);
        console.log("[LumenPass SW] credIdField found:", !!credIdField, "label:", credIdField?.label);
        console.log("[LumenPass SW] userHandleField found:", !!userHandleField, "label:", userHandleField?.label);
        const privateKeyPem = privateKeyField?.value ?? "";
        const credIdB64 = credIdField?.value ?? "";
        const userHandleB64 = userHandleField?.value ?? "";
        console.log("[LumenPass SW] privateKey length:", privateKeyPem.length, "credId length:", credIdB64.length);
        if (!privateKeyPem || !credIdB64) {
          console.error("[LumenPass SW] passkey data missing — privateKey:", !!privateKeyPem, "credId:", !!credIdB64);
          return { ok: false, error: "Passkey data missing — check custom field names in entry" };
        }
        const assertion = await generatePasskeyAssertion({ privateKeyPem, credIdB64, userHandleB64, rpId, challenge, origin });
        console.log("[LumenPass SW] assertion generated, credentialId bytes:", assertion.credentialId.length);
        return { ok: true, data: assertion };
      }

      case "CAPTURE_LOGIN": {
        const tabId = sender?.tab?.id;
        if (tabId !== undefined) {
          clearPendingCapture(tabId);
          const { username, password, fromUrl } = message.payload as {
            username: string;
            password: string;
            fromUrl: string;
          };

          if (!(await ensureSaveLoginOffersAllowed({ tabId, stage: "capture-login", fromUrl }))) {
            return { ok: true };
          }

          const pending: PendingCapture = {
            username,
            password,
            fromUrl,
            expiresAt: Date.now() + 30_000,
          };
          pending.fallbackTimer = setTimeout(() => {
            void maybePromptToSaveLogin(tabId, "fallback");
          }, 1800);
          setTimeout(() => {
            void maybePromptToSaveLogin(tabId, "fallback-spa");
          }, 4000);
          pendingLoginCaptures.set(tabId, pending);
          logTrace("CAPTURE_LOGIN stored", { tabId, username, fromUrl });
        }
        return { ok: true };
      }

      case "SAVE_LOGIN": {
        const { title, username, password, url, existingEntryId, customFields, notes, totp } = message.payload as {
          title: string;
          username: string;
          password: string;
          url: string;
          categoryUuid?: string;
          existingEntryId?: string;
          notes?: string;
          totp?: string;
          customFields?: Array<{ label: string; value: string; secret?: boolean }>;
        };
        const { categoryUuid } = message.payload as { categoryUuid?: string };
        logTrace("message SAVE_LOGIN start", { title, username, url, categoryUuid, existingEntryId });
        const result = await saveEntry({
          title,
          username,
          password,
          url,
          categoryUuid,
          existingEntryId,
          notes,
          totp,
          customFields,
        });
        logTrace("message SAVE_LOGIN result", result);
        return { ok: true, data: result };
      }

      case "CAPTURE_SOCIAL_LOGIN": {
        const tabId = sender?.tab?.id;
        if (tabId !== undefined) {
          clearPendingSocialCapture(tabId);
          const { provider, providerLabel, fromUrl, emailHint, loginSurfaceReason } = message.payload as {
            provider: SocialProvider;
            providerLabel: string;
            fromUrl: string;
            emailHint?: string;
            loginSurfaceReason?: string;
          };

          if (!(await ensureSaveLoginOffersAllowed({ tabId, stage: "capture-social-login", fromUrl, provider }))) {
            return { ok: true };
          }

          // The provider click can start OAuth navigation immediately. Trust the
          // content script's same-tick login-surface decision instead of probing
          // the tab again while it may already be unloading.
          if (!loginSurfaceReason) {
            logTrace("CAPTURE_SOCIAL_LOGIN ignored without content-script login-surface confirmation", {
              tabId,
              provider,
              fromUrl,
            });
            return { ok: true };
          }

          let fromDomain = "";
          try { fromDomain = new URL(fromUrl).hostname; } catch { fromDomain = fromUrl; }
          pendingSocialCaptures.set(tabId, {
            provider,
            providerLabel,
            fromUrl,
            fromDomain,
            expiresAt: Date.now() + 120_000, // 2-minute window
            emailHint: emailHint || "",
            fromLoginSurface: true,
            loginSurfaceReason,
          });
          logTrace("CAPTURE_SOCIAL_LOGIN stored", { tabId, provider, fromUrl, fromDomain, loginSurfaceReason });
        }
        return { ok: true };
      }

      case "SAVE_NOTE": {
        const { title, notes, url, categoryUuid, tags, customFields } = message.payload as {
          title: string;
          notes: string;
          url?: string;
          categoryUuid?: string;
          tags?: string[];
          customFields?: Array<{ label: string; value: string; secret?: boolean }>;
        };
        logTrace("message SAVE_NOTE start", { title, url, categoryUuid });
        const result = await saveNote({ title, notes, url, categoryUuid, tags, customFields });
        logTrace("message SAVE_NOTE result", result);
        return { ok: true, data: result };
      }

      case "SAVE_CREDIT_CARD": {
        const {
          title,
          cardholder,
          url,
          notes,
          categoryUuid,
          cardType,
          cardNumber,
          verificationNumber,
          expiryDate,
          validFrom,
          issuingBank,
          customFields,
        } = message.payload as {
          title: string;
          cardholder?: string;
          url?: string;
          notes?: string;
          categoryUuid?: string;
          cardType?: string;
          cardNumber?: string;
          verificationNumber?: string;
          expiryDate?: string;
          validFrom?: string;
          issuingBank?: string;
          customFields?: Array<{ label: string; value: string; secret?: boolean }>;
        };

        const extraFields: Array<{ label: string; value: string; secret?: boolean }> = [];
        const pushField = (label: string, value: string | undefined, secret = false) => {
          const trimmed = value?.trim() ?? "";
          if (!trimmed) return;
          extraFields.push({ label, value: trimmed, secret });
        };

        pushField("Type", cardType);
        pushField("Card Number", cardNumber);
        pushField("CVC", verificationNumber, true);
        pushField("Expiry Date", expiryDate);
        pushField("Valid From", validFrom);
        pushField("Issuing Bank", issuingBank);
        extraFields.push(...(customFields ?? []).filter((field) => field.label.trim() && field.value.trim()));

        logTrace("message SAVE_CREDIT_CARD start", {
          title,
          cardholder,
          url,
          categoryUuid,
        });
        const result = await saveCreditCard({
          title,
          cardholder,
          url,
          notes,
          categoryUuid,
          customFields: extraFields,
        });
        logTrace("message SAVE_CREDIT_CARD result", result);
        return { ok: true, data: result };
      }

      case "SAVE_SOCIAL_LOGIN": {
        const { title, username, url, provider, providerLabel, categoryUuid } = message.payload as {
          title: string;
          username: string;
          url: string;
          provider: string;
          providerLabel: string;
          categoryUuid?: string;
        };
        logTrace("message SAVE_SOCIAL_LOGIN start", { title, username, url, provider });
        // Store as a standard login entry with an empty password.
        // We use custom fields to persist the social provider identity.
        const socialResult = await saveEntry({
          title,
          username,
          password: "",
          url,
          categoryUuid,
          customFields: [
            { label: "lp_social_provider", value: provider, secret: false },
            { label: "lp_social_label", value: providerLabel, secret: false },
          ],
        });
        logTrace("message SAVE_SOCIAL_LOGIN result", socialResult);
        return { ok: true, data: socialResult };
      }

      default:
        return { ok: false, error: `Unknown message type: ${(message as ExtMessage).type}` };
    }
  } catch (err: unknown) {
    if (isApiError(err)) return { ok: false, error: err.message };
    const msg = err instanceof Error ? err.message : "Unexpected error";
    return { ok: false, error: msg };
  }
}

// ─── CBOR encoder (minimal, for WebAuthn attestation objects) ────────────────

type CborValue =
  | { t: "uint"; v: number }
  | { t: "nint"; v: number }               // v is the actual negative integer
  | { t: "bstr"; v: Uint8Array }
  | { t: "tstr"; v: string }
  | { t: "map";  v: [CborValue, CborValue][] }

function cborEncode(val: CborValue): Uint8Array {
  switch (val.t) {
    case "uint": {
      const n = val.v;
      if (n < 24)    return new Uint8Array([n]);
      if (n < 0x100) return new Uint8Array([0x18, n]);
      return new Uint8Array([0x19, n >> 8, n & 0xFF]);
    }
    case "nint": {
      const n = -1 - val.v; // val.v is negative (e.g. -7 → n=6)
      if (n < 24)    return new Uint8Array([0x20 | n]);
      if (n < 0x100) return new Uint8Array([0x38, n]);
      return new Uint8Array([0x39, n >> 8, n & 0xFF]);
    }
    case "bstr": {
      const len = val.v.length;
      const hdr = len < 24 ? new Uint8Array([0x40 | len]) : new Uint8Array([0x58, len]);
      return concatBytes([hdr, val.v]);
    }
    case "tstr": {
      const b = new TextEncoder().encode(val.v);
      const hdr = b.length < 24 ? new Uint8Array([0x60 | b.length]) : new Uint8Array([0x78, b.length]);
      return concatBytes([hdr, b]);
    }
    case "map": {
      const parts = val.v.flatMap(([k, v]) => [cborEncode(k), cborEncode(v)]);
      const hdr = new Uint8Array([0xA0 | val.v.length]);
      return concatBytes([hdr, ...parts]);
    }
  }
}

function concatBytes(arrays: Uint8Array[]): Uint8Array {
  const total = arrays.reduce((n, a) => n + a.length, 0);
  const out = new Uint8Array(total);
  let off = 0;
  for (const a of arrays) { out.set(a, off); off += a.length; }
  return out;
}

// ─── Convert P1363 (raw r||s) to DER for WebAuthn ────────────────────────────
// WebCrypto ECDSA sign() returns IEEE P1363 (64-byte r||s for P-256).
// WebAuthn servers require DER/ASN.1 SEQUENCE { INTEGER r, INTEGER s }.
function p1363ToDer(sig: Uint8Array): Uint8Array {
  const half = sig.length / 2;
  const r = sig.slice(0, half);
  const s = sig.slice(half);

  function asn1Int(bytes: Uint8Array): Uint8Array {
    let start = 0;
    while (start < bytes.length - 1 && bytes[start] === 0) start++;
    const trimmed = bytes.slice(start);
    const needsPad = (trimmed[0] & 0x80) !== 0;
    const out = new Uint8Array(2 + (needsPad ? 1 : 0) + trimmed.length);
    out[0] = 0x02;
    out[1] = trimmed.length + (needsPad ? 1 : 0);
    if (needsPad) out[2] = 0x00;
    out.set(trimmed, needsPad ? 3 : 2);
    return out;
  }

  const rDer = asn1Int(r);
  const sDer = asn1Int(s);
  const body = new Uint8Array(rDer.length + sDer.length);
  body.set(rDer, 0);
  body.set(sDer, rDer.length);
  const der = new Uint8Array(2 + body.length);
  der[0] = 0x30;
  der[1] = body.length;
  der.set(body, 2);
  return der;
}

// ─── Passkey assertion (ECDSA-P256, RFC 8152) ────────────────────────────────

async function generatePasskeyAssertion(params: {
  privateKeyPem: string;
  credIdB64: string;
  userHandleB64: string;
  rpId: string;
  challenge: number[];
  origin: string;
}): Promise<{
  credentialId: number[];
  clientDataJSON: number[];
  authenticatorData: number[];
  signature: number[];
  userHandle: number[] | null;
}> {
  const { privateKeyPem, credIdB64, userHandleB64, rpId, challenge, origin } = params;

  // ── 1. Import private key (PKCS#8 PEM) ──
  const pemBody = privateKeyPem.replace(/-----[^-]+-----/g, "").replace(/\s/g, "");
  const keyDer = Uint8Array.from(atob(pemBody), (c) => c.charCodeAt(0));
  const privateKey = await crypto.subtle.importKey(
    "pkcs8",
    keyDer.buffer.slice(keyDer.byteOffset, keyDer.byteOffset + keyDer.byteLength) as ArrayBuffer,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );

  // ── 2. Decode credential ID (Base64URL) ──
  const b64pad = credIdB64.replace(/-/g, "+").replace(/_/g, "/") + "==".slice(0, (4 - credIdB64.length % 4) % 4);
  const credentialId = Uint8Array.from(atob(b64pad), (c) => c.charCodeAt(0));

  // ── 3. Build clientDataJSON ──
  const challengeB64 = btoa(String.fromCharCode(...challenge))
    .replace(/\+/g, "-").replace(/\//g, "_").replace(/=/g, "");
  const clientDataJSON = new TextEncoder().encode(JSON.stringify({
    type: "webauthn.get",
    challenge: challengeB64,
    origin,
    crossOrigin: false,
  }));

  // ── 4. Build authenticatorData (rpIdHash || flags || signCount) ──
  const rpIdHash = new Uint8Array(
    await crypto.subtle.digest("SHA-256", new TextEncoder().encode(rpId)),
  );
  const authData = new Uint8Array(37);
  authData.set(rpIdHash, 0);
  authData[32] = 0x05; // UP | UV flags
  new DataView(authData.buffer).setUint32(33, 0, false); // signCount = 0

  // ── 5. Sign authData || SHA-256(clientDataJSON) ──
  const cdHash = new Uint8Array(
    await crypto.subtle.digest("SHA-256", clientDataJSON),
  );
  const sigInput = new Uint8Array(authData.length + cdHash.length);
  sigInput.set(authData, 0);
  sigInput.set(cdHash, authData.length);

  const rawSig = new Uint8Array(
    await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, privateKey, sigInput),
  );
  // Convert from IEEE P1363 (raw r||s) to DER — required by WebAuthn servers
  const signature = p1363ToDer(rawSig);

  // ── 6. Decode user handle ──
  let userHandle: number[] | null = null;
  if (userHandleB64) {
    const uhPad = userHandleB64.replace(/-/g, "+").replace(/_/g, "/") + "==".slice(0, (4 - userHandleB64.length % 4) % 4);
    userHandle = Array.from(Uint8Array.from(atob(uhPad), (c) => c.charCodeAt(0)));
  }

  return {
    credentialId: Array.from(credentialId),
    clientDataJSON: Array.from(clientDataJSON),
    authenticatorData: Array.from(authData),
    signature: Array.from(signature),
    userHandle,
  };
}

// ─── Autofill injected function (runs in page context) ────────────────────────

function performAutofill(entry: { username: string; password: string; totp?: string }): void {
  function fillField(el: HTMLInputElement, value: string): void {
    el.focus();
    const nativeInputValueSetter = Object.getOwnPropertyDescriptor(
      window.HTMLInputElement.prototype,
      "value",
    )?.set;
    nativeInputValueSetter?.call(el, value);
    el.dispatchEvent(new Event("focus", { bubbles: true }));
    try {
      el.dispatchEvent(new InputEvent("beforeinput", { bubbles: true, cancelable: true, inputType: "insertText", data: value }));
    } catch (_) {
      el.dispatchEvent(new Event("beforeinput", { bubbles: true }));
    }
    try {
      el.dispatchEvent(new InputEvent("input", { bubbles: true, cancelable: false, inputType: "insertText", data: value }));
    } catch (_) {
      el.dispatchEvent(new Event("input", { bubbles: true }));
    }
    el.dispatchEvent(new Event("change", { bubbles: true }));
    el.dispatchEvent(new Event("blur", { bubbles: true }));
  }

  // Find password field
  const passwordFields = Array.from(
    document.querySelectorAll<HTMLInputElement>("input[type='password']"),
  ).filter((el) => el.offsetParent !== null);

  if (passwordFields.length === 0) return;

  const passwordField = passwordFields[0];

  // Walk DOM backwards to find the nearest username/email field
  const usernameSelectors = [
    "input[type='email']",
    "input[type='text'][name*='user']",
    "input[type='text'][name*='email']",
    "input[type='text'][name*='login']",
    "input[type='text'][autocomplete*='username']",
    "input[type='text'][autocomplete*='email']",
    "input[type='text']",
  ];

  let usernameField: HTMLInputElement | null = null;
  for (const selector of usernameSelectors) {
    const candidates = Array.from(
      document.querySelectorAll<HTMLInputElement>(selector),
    ).filter((el) => el.offsetParent !== null && el !== passwordField);
    if (candidates.length > 0) {
      usernameField = candidates[candidates.length - 1];
      break;
    }
  }

  if (usernameField && entry.username) fillField(usernameField, entry.username);
  if (entry.password) fillField(passwordField, entry.password);

  // TOTP field
  if (entry.totp) {
    const totpField = document.querySelector<HTMLInputElement>(
      "input[autocomplete='one-time-code'], input[name*='otp'], input[name*='totp'], input[name*='code']",
    );
    if (totpField) fillField(totpField, entry.totp);
  }
}

function performGeneratedPasswordFill(password: string): void {
  function isVisible(el: HTMLInputElement): boolean {
    const style = window.getComputedStyle(el);
    return style.display !== "none" && style.visibility !== "hidden" && el.offsetParent !== null;
  }

  function fillField(el: HTMLInputElement, value: string): void {
    el.focus();
    const nativeInputValueSetter = Object.getOwnPropertyDescriptor(
      window.HTMLInputElement.prototype,
      "value",
    )?.set;
    nativeInputValueSetter?.call(el, value);
    el.dispatchEvent(new Event("focus", { bubbles: true }));
    try {
      el.dispatchEvent(new InputEvent("beforeinput", { bubbles: true, cancelable: true, inputType: "insertText", data: value }));
    } catch (_) {
      el.dispatchEvent(new Event("beforeinput", { bubbles: true }));
    }
    try {
      el.dispatchEvent(new InputEvent("input", { bubbles: true, cancelable: false, inputType: "insertText", data: value }));
    } catch (_) {
      el.dispatchEvent(new Event("input", { bubbles: true }));
    }
    el.dispatchEvent(new Event("change", { bubbles: true }));
    el.dispatchEvent(new Event("blur", { bubbles: true }));
  }

  const passwordFields = Array.from(
    document.querySelectorAll<HTMLInputElement>("input[type='password']"),
  ).filter(isVisible);

  if (passwordFields.length === 0) return;

  const activeElement = document.activeElement;
  const activePasswordField = activeElement instanceof HTMLInputElement && activeElement.type === "password" && isVisible(activeElement)
    ? activeElement
    : null;

  const primaryField = activePasswordField ?? passwordFields[0];
  fillField(primaryField, password);

  const primaryForm = primaryField.form;
  const fallbackForm = primaryField.closest("form");
  const siblingPasswordFields = passwordFields.filter((field) => (
    field !== primaryField
    && (
      (primaryForm && field.form === primaryForm)
      || (!primaryForm && fallbackForm !== null && field.closest("form") === fallbackForm)
    )
  ));

  for (const field of siblingPasswordFields) {
    fillField(field, password);
  }
}
