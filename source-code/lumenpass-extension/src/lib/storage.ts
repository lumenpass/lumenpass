/** Chrome/Firefox storage helpers using webextension-polyfill */

import browser from "webextension-polyfill";

// ─── Types ────────────────────────────────────────────────────────────────────

export interface ExtensionSettings {
  /** Whether autofill icons should be injected into login forms */
  autofillEnabled: boolean;
  /** Whether to auto-submit after filling credentials */
  autoSubmit: boolean;
  /** Vault display name returned from the desktop app */
  vaultName: string;
  /** ISO timestamp of the last successful connection */
  lastConnectedAt: string | null;
  /** When true, silently auto-fills the top matching item on page load */
  autofillOnPageLoad: boolean;
  /** How to match entry domains to the current page: default | baseDomain | subdomain */
  domainSetting: "default" | "baseDomain" | "subdomain";
  /** Domain-level autofill disables synced from LumenPass Desktop. */
  disabledAutofillDomains: DisabledAutofillDomain[];
}

export interface DisabledAutofillDomain {
  domain: string;
  disabledAt: number;
  expiresAt: number | null;
}

export interface CachedSearchResults {
  query: string;
  url: string;
  results: import("./api").EntryItem[];
  cachedAt: number;
}

export type GeneratorType = "smart" | "memorable" | "pin";

export interface GeneratorHistoryItem {
  password: string;
  type: GeneratorType;
  createdAt: number;
}

export interface GeneratorPreferences {
  defaultType: GeneratorType;
  useAsDefaultForSuggestions: boolean;
  history: GeneratorHistoryItem[];
}

const DEFAULTS: ExtensionSettings = {
  autofillEnabled: true,
  autoSubmit: false,
  vaultName: "LumenPass",
  lastConnectedAt: null,
  autofillOnPageLoad: false,
  domainSetting: "default",
  disabledAutofillDomains: [],
};

const GENERATOR_DEFAULTS: GeneratorPreferences = {
  defaultType: "smart",
  useAsDefaultForSuggestions: false,
  history: [],
};

const MAX_GENERATOR_HISTORY_ITEMS = 12;

// ─── Settings ─────────────────────────────────────────────────────────────────

export async function getSettings(): Promise<ExtensionSettings> {
  const stored = await browser.storage.local.get("settings");
  return { ...DEFAULTS, ...(stored.settings as Partial<ExtensionSettings> | undefined) };
}

export async function saveSettings(partial: Partial<ExtensionSettings>): Promise<void> {
  const current = await getSettings();
  await browser.storage.local.set({ settings: { ...current, ...partial } });
}

export async function clearSettings(): Promise<void> {
  await browser.storage.local.remove("settings");
}

// ─── Password generator preferences ──────────────────────────────────────────

export async function getGeneratorPreferences(): Promise<GeneratorPreferences> {
  const stored = await browser.storage.local.get("generatorPreferences");
  return {
    ...GENERATOR_DEFAULTS,
    ...(stored.generatorPreferences as Partial<GeneratorPreferences> | undefined),
  };
}

export async function saveGeneratorPreferences(
  partial: Partial<GeneratorPreferences>,
): Promise<void> {
  const current = await getGeneratorPreferences();
  await browser.storage.local.set({
    generatorPreferences: { ...current, ...partial },
  });
}

export async function appendGeneratorHistory(
  item: GeneratorHistoryItem,
): Promise<GeneratorPreferences> {
  const current = await getGeneratorPreferences();
  const history = [item, ...current.history.filter(
    (existing) => existing.password !== item.password || existing.type !== item.type,
  )].slice(0, MAX_GENERATOR_HISTORY_ITEMS);

  const next = { ...current, history };
  await browser.storage.local.set({ generatorPreferences: next });
  return next;
}

// ─── Vault state (session-scoped, survives SW restarts) ───────────────────────

export interface PersistedVaultState {
  connected: boolean;
  vaultOpen: boolean;
  updatedAt: number;
}

const VAULT_STATE_KEY = "vaultState";

export async function getPersistedVaultState(): Promise<PersistedVaultState | null> {
  try {
    const stored = await browser.storage.session.get(VAULT_STATE_KEY);
    const state = (stored as Record<string, PersistedVaultState | undefined>)[VAULT_STATE_KEY];
    if (!state || typeof state.connected !== "boolean") return null;
    return state;
  } catch {
    return null;
  }
}

export async function setPersistedVaultState(
  connected: boolean,
  vaultOpen: boolean,
): Promise<void> {
  const payload: PersistedVaultState = { connected, vaultOpen, updatedAt: Date.now() };
  await browser.storage.session.set({ [VAULT_STATE_KEY]: payload }).catch(() => {});
}

// ─── Search result cache (session-scoped) ─────────────────────────────────────

const CACHE_TTL_MS = 30_000; // 30 seconds

export async function getCachedResults(
  query: string,
  url: string,
): Promise<import("./api").EntryItem[] | null> {
  const stored = await browser.storage.session
    .get("searchCache")
    .catch(() => ({}));
  const cache = (stored as Record<string, CachedSearchResults>).searchCache;
  if (!cache) return null;
  if (cache.query !== query || cache.url !== url) return null;
  if (Date.now() - cache.cachedAt > CACHE_TTL_MS) return null;
  return cache.results;
}

export async function setCachedResults(
  query: string,
  url: string,
  results: import("./api").EntryItem[],
): Promise<void> {
  const payload: CachedSearchResults = { query, url, results, cachedAt: Date.now() };
  await browser.storage.session.set({ searchCache: payload }).catch(() => {
    // session storage may not be available in all contexts; silently ignore
  });
}
