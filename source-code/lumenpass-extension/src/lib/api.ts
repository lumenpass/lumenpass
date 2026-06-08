/** LumenPass Desktop API client */

const DESKTOP_BASE_URL = "http://127.0.0.1:19455";
const REQUEST_TIMEOUT_MS = 5000;

// ─── Types ────────────────────────────────────────────────────────────────────

export interface PingResponse {
  status: "ok";
  version: string;
  vaultOpen?: boolean;
}

export interface AuthResponse {
  success: boolean;
  vaultName?: string;
  error?: string;
}

export interface EntryItem {
  id: string;
  title: string;
  username: string;
  password?: string;
  url?: string;
  totp?: string;
  favicon?: string;
  hasPasskey?: boolean;
  subtitle?: string;
  socialProvider?: string;
  kind?:
    | "login"
    | "passkey"
    | "secure-note"
    | "software-license"
    | "ssh-key"
    | "credit-card"
    | "identity"
    | "totp"
    | "unknown";
}

export interface EntryDetail extends EntryItem {
  notes?: string;
  customFields?: Array<{ label: string; value: string; secret: boolean }>;
  tags?: string[];
  createdAt?: string;
  updatedAt?: string;
}

export interface PasskeyMatchItem {
  id: string;
  title: string;
  username: string;
  rpId: string;
  credentialId: string;
  usernameMatched?: boolean;
}

export interface CategoryItem {
  id: string;
  name: string;
}

export interface ApiError {
  code: "NETWORK_ERROR" | "TIMEOUT" | "NOT_FOUND" | "SERVER_ERROR";
  message: string;
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

async function fetchWithTimeout(
  url: string,
  options: RequestInit = {},
  timeoutMs = REQUEST_TIMEOUT_MS,
): Promise<Response> {
  const controller = new AbortController();
  const id = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const response = await fetch(url, { ...options, signal: controller.signal });
    return response;
  } catch (err: unknown) {
    if (err instanceof Error && err.name === "AbortError") {
      throw buildError("TIMEOUT", "Request timed out");
    }
    throw buildError("NETWORK_ERROR", "Cannot reach LumenPass Desktop");
  } finally {
    clearTimeout(id);
  }
}

function buildError(code: ApiError["code"], message: string): ApiError {
  return { code, message };
}

const JSON_HEADERS: HeadersInit = { "Content-Type": "application/json" };

// ─── API Methods ──────────────────────────────────────────────────────────────

/** Check if the desktop app is reachable. */
export async function ping(): Promise<PingResponse> {
  const response = await fetchWithTimeout(`${DESKTOP_BASE_URL}/ping`);
  if (!response.ok) throw buildError("SERVER_ERROR", `Server returned ${response.status}`);
  return response.json() as Promise<PingResponse>;
}

/** Fetch the vault name from the desktop app. */
export async function authenticate(): Promise<AuthResponse> {
  const response = await fetchWithTimeout(`${DESKTOP_BASE_URL}/auth`, {
    method: "POST",
    headers: JSON_HEADERS,
    body: JSON.stringify({}),
  });
  if (!response.ok) throw buildError("SERVER_ERROR", `Server returned ${response.status}`);
  return response.json() as Promise<AuthResponse>;
}

/** Search entries by query string + current page URL. */
export async function searchEntries(
  query: string,
  url?: string,
  submitUrl?: string,
  timeoutMs?: number,
  type?: string,
  domainSetting?: string,
): Promise<EntryItem[]> {
  const params = new URLSearchParams({ query });
  if (url) params.set("url", url);
  if (submitUrl) params.set("submitUrl", submitUrl);
  if (type) params.set("type", type);
  if (domainSetting) params.set("domainSetting", domainSetting);

  const response = await fetchWithTimeout(
    `${DESKTOP_BASE_URL}/search?${params.toString()}`,
    {},
    timeoutMs,
  );
  if (!response.ok) throw buildError("SERVER_ERROR", `Server returned ${response.status}`);
  return response.json() as Promise<EntryItem[]>;
}

/** Fetch full entry details by ID. */
export async function getEntry(id: string, timeoutMs?: number): Promise<EntryDetail> {
  const response = await fetchWithTimeout(
    `${DESKTOP_BASE_URL}/entry/${encodeURIComponent(id)}`,
    {},
    timeoutMs,
  );
  if (response.status === 404) throw buildError("NOT_FOUND", "Entry not found");
  if (!response.ok) throw buildError("SERVER_ERROR", `Server returned ${response.status}`);
  return response.json() as Promise<EntryDetail>;
}

/** Fetch available save categories/groups for the current vault. */
export async function getCategories(timeoutMs?: number): Promise<CategoryItem[]> {
  const response = await fetchWithTimeout(`${DESKTOP_BASE_URL}/categories`, {}, timeoutMs);
  if (!response.ok) throw buildError("SERVER_ERROR", `Server returned ${response.status}`);
  return response.json() as Promise<CategoryItem[]>;
}

/** Save a new passkey entry to the desktop vault. */
export async function savePasskey(
  data: {
    title: string;
    url: string;
    rpId: string;
    username: string;
    credentialId: string;
    privateKey: string;
    userHandle: string;
    existingEntryId?: string;
  },
): Promise<{ ok: boolean; id?: string; mode?: "created" | "updated" }> {
  const response = await fetchWithTimeout(`${DESKTOP_BASE_URL}/passkey/create`, {
    method: "POST",
    headers: JSON_HEADERS,
    body: JSON.stringify(data),
  });
  if (!response.ok) throw buildError("SERVER_ERROR", `Server returned ${response.status}`);
  return response.json() as Promise<{ ok: boolean; id?: string; mode?: "created" | "updated" }>;
}

/** Save a new login entry to the desktop vault, or update when `existingEntryId` is set. */
export async function saveEntry(
  data: {
    title: string;
    username: string;
    password: string;
    url: string;
    categoryUuid?: string;
    existingEntryId?: string;
    notes?: string;
    totp?: string;
    customFields?: Array<{ label: string; value: string; secret?: boolean }>;
  },
): Promise<{ ok: boolean; id?: string; mode?: "created" | "updated" }> {
  const response = await fetchWithTimeout(`${DESKTOP_BASE_URL}/entry/create`, {
    method: "POST",
    headers: JSON_HEADERS,
    body: JSON.stringify(data),
  });
  if (!response.ok) throw buildError("SERVER_ERROR", `Server returned ${response.status}`);
  return response.json() as Promise<{ ok: boolean; id?: string; mode?: "created" | "updated" }>;
}

/** Save a new secure-note entry to the desktop vault. */
export async function saveNote(
  data: {
    title: string;
    notes: string;
    url?: string;
    categoryUuid?: string;
    tags?: string[];
    customFields?: Array<{ label: string; value: string; secret?: boolean }>;
  },
): Promise<{ ok: boolean; id?: string; mode?: "created" | "updated" }> {
  const response = await fetchWithTimeout(`${DESKTOP_BASE_URL}/note/create`, {
    method: "POST",
    headers: JSON_HEADERS,
    body: JSON.stringify(data),
  });
  if (!response.ok) throw buildError("SERVER_ERROR", `Server returned ${response.status}`);
  return response.json() as Promise<{ ok: boolean; id?: string; mode?: "created" | "updated" }>;
}

/** Save a new credit-card entry to the desktop vault. */
export async function saveCreditCard(
  data: {
    title: string;
    cardholder?: string;
    url?: string;
    categoryUuid?: string;
    notes?: string;
    customFields?: Array<{ label: string; value: string; secret?: boolean }>;
  },
): Promise<{ ok: boolean; id?: string; mode?: "created" | "updated" }> {
  return saveEntry({
    title: data.title,
    username: data.cardholder ?? "",
    password: "",
    url: data.url ?? "",
    categoryUuid: data.categoryUuid,
    notes: data.notes,
    customFields: data.customFields,
  });
}

export interface VaultSettings {
  domainSetting: "default" | "baseDomain" | "subdomain";
  disabledAutofillDomains?: DisabledAutofillDomain[];
}

export interface DisabledAutofillDomain {
  domain: string;
  disabledAt: number;
  expiresAt: number | null;
}

/** Fetch autofill and domain-matching preferences from the desktop app. */
export async function getVaultSettings(timeoutMs?: number): Promise<VaultSettings> {
  const response = await fetchWithTimeout(`${DESKTOP_BASE_URL}/vault-settings`, {}, timeoutMs);
  if (!response.ok) throw buildError("SERVER_ERROR", `Server returned ${response.status}`);
  return response.json() as Promise<VaultSettings>;
}

/** Persist the domain-level autofill disable list in the desktop app. */
export async function saveDisabledAutofillDomains(
  domains: DisabledAutofillDomain[],
): Promise<{ ok: boolean }> {
  const response = await fetchWithTimeout(`${DESKTOP_BASE_URL}/vault-settings/disabled-autofill-domains`, {
    method: "POST",
    headers: JSON_HEADERS,
    body: JSON.stringify({ disabledAutofillDomains: domains }),
  });
  if (!response.ok) throw buildError("SERVER_ERROR", `Server returned ${response.status}`);
  return response.json() as Promise<{ ok: boolean }>;
}

/** Ask the desktop app to bring its window to the front. */
export async function focusDesktop(): Promise<{ ok: boolean }> {
  const response = await fetchWithTimeout(`${DESKTOP_BASE_URL}/focus`, { method: "POST" }, 2000);
  if (!response.ok) throw buildError("SERVER_ERROR", `Server returned ${response.status}`);
  return response.json() as Promise<{ ok: boolean }>;
}

/** Ask the desktop app to open the new-item flow. */
export async function openNewItem(
  payload: {
    kind?: "login" | "secure-note";
    url?: string;
    title?: string;
    notes?: string;
  } = {},
): Promise<{ ok: boolean }> {
  const response = await fetchWithTimeout(
    `${DESKTOP_BASE_URL}/item/new`,
    {
      method: "POST",
      headers: JSON_HEADERS,
      body: JSON.stringify(payload),
    },
    2000,
  );
  if (!response.ok) throw buildError("SERVER_ERROR", `Server returned ${response.status}`);
  return response.json() as Promise<{ ok: boolean }>;
}

/** Ask the desktop app to open the edit flow for an existing item. */
export async function openEditItem(id: string): Promise<{ ok: boolean }> {
  const response = await fetchWithTimeout(
    `${DESKTOP_BASE_URL}/item/edit`,
    {
      method: "POST",
      headers: JSON_HEADERS,
      body: JSON.stringify({ id }),
    },
    2000,
  );
  if (response.status === 404) {
    throw buildError(
      "NOT_FOUND",
      "Restart or update LumenPass Desktop to edit items from the browser.",
    );
  }
  if (!response.ok) throw buildError("SERVER_ERROR", `Server returned ${response.status}`);
  return response.json() as Promise<{ ok: boolean }>;
}

/** Ask the desktop app to delete an existing item without showing a second prompt. */
export async function deleteItem(id: string): Promise<{ ok: boolean; id?: string }> {
  const response = await fetchWithTimeout(
    `${DESKTOP_BASE_URL}/item/delete`,
    {
      method: "POST",
      headers: JSON_HEADERS,
      body: JSON.stringify({ id }),
    },
    5000,
  );
  if (response.status === 404) {
    throw buildError(
      "NOT_FOUND",
      "Item not found or this desktop build does not support extension deletes yet.",
    );
  }
  if (!response.ok) throw buildError("SERVER_ERROR", `Server returned ${response.status}`);
  return response.json() as Promise<{ ok: boolean; id?: string }>;
}

// ─── Unlock (extension-driven) ───────────────────────────────────────────────

export interface UnlockOptionsResponse {
  locked: boolean;
  vaultReady?: boolean;
  vaultName?: string;
  hasPin?: boolean;
  hasBiometric?: boolean;
  biometricAvailable?: boolean;
  /** "biometric" | "pin" | "none" */
  lastMethod?: string;
}

export interface UnlockResultResponse {
  ok: boolean;
  error?: string;
  alreadyUnlocked?: boolean;
}

/** Fetch the unlock capabilities (password / PIN / biometric) for the currently
 *  selected vault, plus the UX hint for the last unlock method used. */
export async function getUnlockOptions(timeoutMs?: number): Promise<UnlockOptionsResponse> {
  const response = await fetchWithTimeout(
    `${DESKTOP_BASE_URL}/unlock/options`,
    {},
    timeoutMs,
  );
  if (!response.ok) throw buildError("SERVER_ERROR", `Server returned ${response.status}`);
  return response.json() as Promise<UnlockOptionsResponse>;
}

/** Attempt to unlock the vault with the supplied master password. */
export async function unlockWithPassword(password: string): Promise<UnlockResultResponse> {
  // Password unlock can be slow (KDF) — extend the timeout well beyond the
  // default so the extension does not give up mid-unlock.
  const response = await fetchWithTimeout(
    `${DESKTOP_BASE_URL}/unlock`,
    {
      method: "POST",
      headers: JSON_HEADERS,
      body: JSON.stringify({ password }),
    },
    60000,
  );
  return response.json() as Promise<UnlockResultResponse>;
}

/** Attempt to unlock via the stored PIN. */
export async function unlockWithPin(pin: string): Promise<UnlockResultResponse> {
  const response = await fetchWithTimeout(
    `${DESKTOP_BASE_URL}/unlock/pin`,
    {
      method: "POST",
      headers: JSON_HEADERS,
      body: JSON.stringify({ pin }),
    },
    60000,
  );
  return response.json() as Promise<UnlockResultResponse>;
}

/** Ask the desktop app to show its biometric prompt and unlock. */
export async function unlockWithBiometric(): Promise<UnlockResultResponse> {
  // Biometric auth is user-gated on the desktop and may take a while.
  const response = await fetchWithTimeout(
    `${DESKTOP_BASE_URL}/unlock/biometric`,
    { method: "POST", headers: JSON_HEADERS, body: "{}" },
    120000,
  );
  return response.json() as Promise<UnlockResultResponse>;
}

/** Type guard: check if a value is an ApiError. */
export function isApiError(value: unknown): value is ApiError {
  return (
    typeof value === "object" &&
    value !== null &&
    "code" in value &&
    "message" in value
  );
}
