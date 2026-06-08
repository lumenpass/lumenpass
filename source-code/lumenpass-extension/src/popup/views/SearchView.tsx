import React, { useState, useEffect, useRef, useCallback } from "react";
import {
  Plus, Loader2, Unlock, Eye, EyeOff,
  Copy, Check, ExternalLink, LogIn, KeyRound, ChevronDown,
  List, NotebookPen, ShieldCheck, FileKey2, IdCard, TimerReset,
  Sparkles, PencilLine, Trash2, AlertTriangle,
} from "lucide-react";
import browser from "webextension-polyfill";
import {
  debounce,
  extractDomain,
  googleFaviconUrlForDisplay,
  pastelAvatar,
  initials,
  totpCountdown,
  computeTotp,
  type ExtMessage,
  type ExtResponse,
} from "../../lib/utils";
import {
  buildFeaturedTotps,
  isOtpLikeFieldLabel,
} from "../../lib/totp-display";
import type { EntryItem, EntryDetail } from "../../lib/api";
import type { ExtensionSettings } from "../../lib/storage";

/** Same asset as the in-page “Sign in with a passkey” sheet (`content-script.ts`). */
const PASSKEY_ICON_URL = browser.runtime.getURL("icons/passkey_icon.png");

function PasskeyGlyph({ className }: { className?: string }) {
  return (
    <img
      src={PASSKEY_ICON_URL}
      alt=""
      draggable={false}
      className={className}
      style={{ objectFit: "contain" }}
    />
  );
}

interface Props {
  settings: ExtensionSettings | null;
  currentUrl: string;
  connected: boolean;
  vaultOpen: boolean;
  query: string;
  sendMessage: <T>(msg: ExtMessage) => Promise<ExtResponse<T>>;
}

type FilterValue =
  | "suggestions"
  | "all"
  | "login"
  | "passkey"
  | "secure-note"
  | "software-license"
  | "ssh-key"
  | "identity"
  | "totp";

const FILTER_OPTIONS: Array<{
  value: FilterValue;
  label: string;
  icon: React.ComponentType<{ className?: string }>;
  iconClassName: string;
}> = [
  { value: "suggestions", label: "Suggestions", icon: Sparkles, iconClassName: "text-emerald-500" },
  { value: "all", label: "All items", icon: List, iconClassName: "text-slate-500" },
  { value: "login", label: "Logins", icon: FileKey2, iconClassName: "text-cyan-500" },
  { value: "passkey", label: "Passkeys", icon: PasskeyGlyph, iconClassName: "" },
  { value: "secure-note", label: "Secure notes", icon: NotebookPen, iconClassName: "text-amber-500" },
  { value: "software-license", label: "Software licenses", icon: ShieldCheck, iconClassName: "text-blue-500" },
  { value: "ssh-key", label: "SSH keys", icon: FileKey2, iconClassName: "text-orange-500" },
  { value: "identity", label: "Identities", icon: IdCard, iconClassName: "text-emerald-500" },
  { value: "totp", label: "One-time passwords", icon: TimerReset, iconClassName: "text-sky-500" },
];

export default function SearchView({ settings, currentUrl, connected, vaultOpen, query, sendMessage }: Props) {
  const [results, setResults] = useState<EntryItem[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [fullEntry, setFullEntry] = useState<EntryDetail | null>(null);
  const [loadingDetail, setLoadingDetail] = useState(false);
  const [revealPassword, setRevealPassword] = useState(false);
  const [copiedField, setCopiedField] = useState<string | null>(null);
  const [toastMsg, setToastMsg] = useState<string | null>(null);
  const [activeFilter, setActiveFilter] = useState<FilterValue>("suggestions");
  const [filterMenuOpen, setFilterMenuOpen] = useState(false);
  const [pendingDeleteEntry, setPendingDeleteEntry] = useState<EntryItem | null>(null);
  const [editingItemId, setEditingItemId] = useState<string | null>(null);
  const [deletingItemId, setDeletingItemId] = useState<string | null>(null);
  const toastTimerRef = useRef<number | null>(null);
  const filterMenuRef = useRef<HTMLDivElement>(null);

  const domain = extractDomain(currentUrl);
  const selectedEntry = results.find((e) => e.id === selectedId) ?? null;
  const activeFilterMeta = FILTER_OPTIONS.find((option) => option.value === activeFilter) ?? FILTER_OPTIONS[0];
  const emptyDetailMessage = getEmptyDetailMessage(
    activeFilter,
    activeFilterMeta.label,
    results.length,
    connected,
    vaultOpen,
  );

  const showToast = (msg: string) => {
    setToastMsg(msg);
    if (toastTimerRef.current) window.clearTimeout(toastTimerRef.current);
    toastTimerRef.current = window.setTimeout(() => setToastMsg(null), 2000);
  };

  const logTrace = (message: string, details?: unknown) => {
    if (details === undefined) {
      console.log(`[LumenPass Popup] ${message}`);
      return;
    }
    console.log(`[LumenPass Popup] ${message}`, details);
  };

  const copyField = async (value: string, field: string) => {
    try {
      await navigator.clipboard.writeText(value);
      setCopiedField(field);
      setTimeout(() => setCopiedField(null), 1500);
    } catch {
      showToast("Copy failed");
    }
  };

  // ─── Search ────────────────────────────────────────────────────────────────

  const performSearch = useCallback(
    async (q: string, filter: FilterValue) => {
      if (!(connected && vaultOpen)) {
        logTrace("performSearch skipped", {
          connected,
          vaultOpen,
          query: q,
          filter,
        });
        return;
      }
      setLoading(true);
      setError(null);
      logTrace("performSearch start", {
        query: q,
        filter,
        currentUrl,
      });
      try {
        const fetchEntries = async (scopeUrl?: string): Promise<EntryItem[] | null> => {
          logTrace("fetchEntries request", { query: q, filter, scopeUrl });
          const res = await sendMessage<EntryItem[]>({
            type: "SEARCH_ENTRIES",
            payload: {
              query: q,
              url: scopeUrl,
              type: filter === "suggestions" || filter === "all" ? undefined : filter,
            },
          });
          if (!res.ok || !res.data) {
            logTrace("fetchEntries failed", {
              query: q,
              filter,
              scopeUrl,
              error: res.error,
            });
            setError(res.error ?? "Search failed");
            return null;
          }
          const filtered = applyEntryFilter(res.data, filter);
          logTrace("fetchEntries result", {
            scopeUrl,
            rawCount: res.data.length,
            filteredCount: filtered.length,
            titles: filtered.slice(0, 5).map((entry) => entry.title),
          });
          return filtered;
        };

        const scopeUrl = filter === "suggestions" ? currentUrl : undefined;
        const filteredResults = await fetchEntries(scopeUrl);
        if (filteredResults === null) return;

        setResults(filteredResults);
        logTrace("performSearch final result", {
          count: filteredResults.length,
          selectedId: filteredResults[0]?.id ?? null,
        });
        if (filteredResults.length > 0) {
          handleSelect(filteredResults[0]);
        } else {
          setSelectedId(null);
          setFullEntry(null);
        }
      } catch (error) {
        logTrace("performSearch exception", error);
        setError("Failed to search");
      } finally {
        setLoading(false);
      }
    },
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [connected, vaultOpen, currentUrl, sendMessage],
  );

  // eslint-disable-next-line react-hooks/exhaustive-deps
  const debouncedSearch = useCallback(
    debounce((payload: unknown) => {
      const { q, filter } = payload as { q: string; filter: FilterValue };
      void performSearch(q, filter);
    }, 300),
    [performSearch],
  );

  useEffect(() => {
    if (!(connected && vaultOpen)) {
      setResults([]);
      setSelectedId(null);
      setFullEntry(null);
      setLoading(false);
      setError(null);
      return;
    }
    if (!query.trim()) {
      void performSearch("", activeFilter);
      return;
    }
    debouncedSearch({ q: query, filter: activeFilter });
  }, [connected, vaultOpen, currentUrl, query, activeFilter, performSearch, debouncedSearch]);

  useEffect(() => () => {
    if (toastTimerRef.current) window.clearTimeout(toastTimerRef.current);
  }, []);

  useEffect(() => {
    if (!filterMenuOpen) return;
    const handleClickOutside = (event: MouseEvent) => {
      if (!filterMenuRef.current?.contains(event.target as Node)) {
        setFilterMenuOpen(false);
      }
    };
    document.addEventListener("mousedown", handleClickOutside);
    return () => document.removeEventListener("mousedown", handleClickOutside);
  }, [filterMenuOpen]);

  // ─── Entry selection ───────────────────────────────────────────────────────

  const handleSelect = useCallback(async (entry: EntryItem) => {
    console.log("[LumenPass Popup] handleSelect start", {
      id: entry.id,
      title: entry.title,
    });
    setSelectedId(entry.id);
    setRevealPassword(false);
    setFullEntry(null);
    setLoadingDetail(true);
    try {
      const res = await sendMessage<EntryDetail>({ type: "GET_ENTRY", payload: { id: entry.id } });
      if (res.ok && res.data) {
        console.log("[LumenPass Popup] handleSelect result", {
          id: res.data.id,
          title: res.data.title,
        });
        setFullEntry(res.data);
      } else {
        console.log("[LumenPass Popup] handleSelect failed", {
          id: entry.id,
          error: res.error,
        });
      }
    } finally {
      setLoadingDetail(false);
    }
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [sendMessage]);

  // ─── Autofill ─────────────────────────────────────────────────────────────

  const handleFill = useCallback(async (entry: EntryItem) => {
    const tabs = await browser.tabs.query({ active: true, currentWindow: true });
    const tabId = tabs[0]?.id;
    if (!tabId) return showToast("No active tab");

    const detail = fullEntry?.id === entry.id ? fullEntry : entry;
    const res = await sendMessage({
      type: "AUTOFILL",
      payload: {
        tabId,
        entry: {
          username: detail.username,
          password: detail.password ?? "",
          totp: detail.totp,
        },
      },
    });
    if (res.ok) showToast("Filled ✓");
    else showToast(res.error ?? "Autofill failed");
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [fullEntry, sendMessage]);

  const handleNewItem = useCallback(async () => {
    if (!(connected && vaultOpen)) {
      showToast(vaultOpen ? "Open LumenPass Desktop" : "Unlock your vault first");
      return;
    }
    const res = await sendMessage({ type: "OPEN_NEW_ITEM", payload: { url: currentUrl } });
    if (res.ok) showToast("Opening desktop…");
    else showToast(res.error ?? "Could not open new item");
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [connected, vaultOpen, currentUrl, sendMessage]);

  const handleOpenItemUrl = useCallback(async (entry: EntryItem) => {
    const detail = fullEntry?.id === entry.id ? fullEntry : entry;
    const targetUrl = normalizeOpenableUrl(detail.url ?? entry.url);
    if (!targetUrl) {
      showToast("No valid website URL");
      return;
    }

    try {
      await browser.tabs.create({ url: targetUrl });
    } catch {
      showToast("Could not open website");
    }
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [fullEntry]);

  const handleEditItem = useCallback(async (entry: EntryItem) => {
    if (!(connected && vaultOpen)) {
      showToast(vaultOpen ? "Open LumenPass Desktop" : "Unlock your vault first");
      return;
    }

    const id = entry.id.trim();
    if (!id) {
      showToast("Could not open editor");
      return;
    }

    setEditingItemId(id);
    try {
      const res = await sendMessage({ type: "OPEN_EDIT_ITEM", payload: { id } });
      if (res.ok) showToast("Opening desktop…");
      else showToast(res.error ?? "Could not open editor");
    } catch {
      showToast("Could not open editor");
    } finally {
      setEditingItemId(null);
    }
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [connected, vaultOpen, sendMessage]);

  const handleRequestDeleteItem = useCallback((entry: EntryItem) => {
    if (!(connected && vaultOpen)) {
      showToast(vaultOpen ? "Open LumenPass Desktop" : "Unlock your vault first");
      return;
    }
    setPendingDeleteEntry(entry);
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [connected, vaultOpen]);

  const handleCancelDelete = useCallback(() => {
    if (deletingItemId) return;
    setPendingDeleteEntry(null);
  }, [deletingItemId]);

  const handleConfirmDelete = useCallback(async () => {
    const entry = pendingDeleteEntry;
    if (!entry) return;

    const id = entry.id.trim();
    if (!id) {
      showToast("Could not delete item");
      setPendingDeleteEntry(null);
      return;
    }

    setDeletingItemId(id);
    try {
      const res = await sendMessage({ type: "DELETE_ITEM", payload: { id } });
      if (!res.ok) {
        showToast(res.error ?? "Could not delete item");
        return;
      }

      setResults((current) => current.filter((item) => item.id !== id));
      setSelectedId((current) => (current === id ? null : current));
      setFullEntry((current) => (current?.id === id ? null : current));
      setPendingDeleteEntry(null);
      showToast(`"${entry.title}" moved to Trash`);
      await performSearch(query, activeFilter);
    } catch {
      showToast("Could not delete item");
    } finally {
      setDeletingItemId(null);
    }
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [pendingDeleteEntry, sendMessage, performSearch, query, activeFilter]);

  // ─── Keyboard navigation ───────────────────────────────────────────────────

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (pendingDeleteEntry) return;
    const idx = results.findIndex((r) => r.id === selectedId);
    if (e.key === "ArrowDown") {
      e.preventDefault();
      const next = results[Math.min(idx + 1, results.length - 1)];
      if (next) handleSelect(next);
    } else if (e.key === "ArrowUp") {
      e.preventDefault();
      const prev = results[Math.max(idx - 1, 0)];
      if (prev) handleSelect(prev);
    } else if (e.key === "Enter" && selectedEntry) {
      handleFill(selectedEntry);
    }
  };

  // ─── Render ────────────────────────────────────────────────────────────────

  return (
    <div className="relative flex h-full min-h-0" onKeyDown={handleKeyDown}>

      {/* ── Left panel: search + list ───────────────────────────────── */}
      <div className="w-[260px] min-h-0 shrink-0 flex flex-col border-r border-[#dbe7ff] bg-[#f3f7ff] dark:border-gray-800 dark:bg-gray-950">

        {/* Filter dropdown */}
        <div className="px-3 pt-3 pb-2" ref={filterMenuRef}>
          <button
            type="button"
            onClick={() => setFilterMenuOpen((value) => !value)}
            className="flex w-full items-center gap-2 rounded-2xl border border-[#c7d8ff] bg-white px-3 py-2.5 text-left shadow-sm transition-colors hover:border-[#9fbaff] dark:border-gray-700 dark:bg-gray-900"
          >
            <activeFilterMeta.icon className={`h-4 w-4 shrink-0 ${activeFilterMeta.iconClassName}`} />
            <span className="min-w-0 flex-1 truncate text-[14px] font-semibold text-gray-800 dark:text-gray-100">
              {activeFilterMeta.label}
            </span>
            {loading ? (
              <Loader2 className="h-4 w-4 shrink-0 animate-spin text-gray-400" />
            ) : (
              <ChevronDown className={`h-4 w-4 shrink-0 text-gray-500 transition-transform ${filterMenuOpen ? "rotate-180" : ""}`} />
            )}
          </button>

          {filterMenuOpen && (
            <div className="absolute z-20 mt-2 w-[236px] overflow-hidden rounded-2xl border border-[#d9e5ff] bg-white shadow-xl dark:border-gray-700 dark:bg-gray-900">
              <div className="py-2">
                {FILTER_OPTIONS.map((option) => {
                  const Icon = option.icon;
                  const selected = option.value === activeFilter;
                  return (
                    <button
                      key={option.value}
                      type="button"
                      onClick={() => {
                        setActiveFilter(option.value);
                        setFilterMenuOpen(false);
                      }}
                      className={`flex w-full items-center gap-3 px-4 py-2.5 text-left transition-colors ${
                        selected ? "bg-[#eef4ff]" : "hover:bg-gray-50 dark:hover:bg-gray-800/60"
                      }`}
                    >
                      <Icon className={`h-4 w-4 shrink-0 ${option.iconClassName}`} />
                      <span className="flex-1 text-[14px] font-medium text-gray-800 dark:text-gray-100">
                        {option.label}
                      </span>
                      {selected && <Check className="h-4 w-4 text-brand-600" />}
                    </button>
                  );
                })}
              </div>
            </div>
          )}
        </div>

        {/* Entry list */}
        <div className="min-h-0 flex-1 overflow-y-auto pr-1">
          {!connected ? (
            <ListEmptyState title="Desktop app not running" />
          ) : !vaultOpen ? (
            <ListEmptyState title="Vault is locked" subtitle="Unlock or open your vault in LumenPass Desktop." />
          ) : error ? (
            <ListEmptyState title="Search failed" subtitle={error} />
          ) : !loading && results.length === 0 ? (
            <ListEmptyState
              title={query ? "No results" : `No ${activeFilterMeta.label.toLowerCase()} found`}
              subtitle={query ? undefined : activeFilter === "suggestions" ? "Try searching by name." : undefined}
            />
          ) : (
            results.map((entry) => (
              <ListRow
                key={entry.id}
                entry={entry}
                selected={entry.id === selectedId}
                onClick={() => handleSelect(entry)}
              />
            ))
          )}
        </div>

        {/* Footer */}
        <div className="px-3 py-2.5 border-t border-[#dbe7ff] dark:border-gray-800 flex items-center justify-between shrink-0">
          <span className="text-[12px] text-gray-400 tabular-nums">
            {results.length > 0 ? `${results.length} item${results.length !== 1 ? "s" : ""}` : ""}
          </span>
          <button
            type="button"
            onClick={handleNewItem}
            className="inline-flex items-center gap-1.5 rounded-lg border border-brand-700 bg-brand-600 px-3 py-1.5 text-[12px] font-semibold text-white shadow-sm transition-colors hover:bg-brand-700 dark:border-brand-500 dark:bg-brand-600 dark:hover:bg-brand-500"
          >
            <Plus className="w-3.5 h-3.5" />
            New item
          </button>
        </div>
      </div>

      {/* ── Right panel: detail ─────────────────────────────────────── */}
      <div className="min-w-0 min-h-0 flex-1 flex flex-col bg-white dark:bg-gray-900">
        <div className="min-h-0 flex-1 overflow-y-auto">
          {selectedEntry ? (
            <DetailPanel
              entry={selectedEntry}
              fullEntry={fullEntry}
              loading={loadingDetail}
              revealPassword={revealPassword}
              copiedField={copiedField}
              onReveal={() => setRevealPassword((v) => !v)}
              onCopy={copyField}
              onFill={() => handleFill(selectedEntry)}
              onOpenUrl={() => void handleOpenItemUrl(selectedEntry)}
            />
          ) : (
            <div className="flex-1 flex flex-col items-center justify-center gap-3 text-center px-8 h-full">
              {!connected ? (
                <>
                  <Unlock className="w-10 h-10 text-gray-200 dark:text-gray-700" />
                  <p className="text-sm font-medium text-gray-400 dark:text-gray-500">
                    Open LumenPass Desktop
                  </p>
                </>
              ) : (
                <>
                  <div className="w-12 h-12 rounded-2xl bg-gray-100 dark:bg-gray-800 flex items-center justify-center">
                    <KeyRound className="w-5 h-5 text-gray-300 dark:text-gray-600" />
                  </div>
                  <p className="text-sm font-medium text-gray-400 dark:text-gray-500">
                    {emptyDetailMessage}
                  </p>
                </>
              )}
            </div>
          )}
        </div>
        <DetailActionBar
          showActions={!!selectedEntry}
          onEdit={selectedEntry ? () => void handleEditItem(selectedEntry) : undefined}
          onDelete={selectedEntry ? () => handleRequestDeleteItem(selectedEntry) : undefined}
          editPending={selectedEntry ? editingItemId === selectedEntry.id : false}
          deletePending={selectedEntry ? deletingItemId === selectedEntry.id : false}
        />
      </div>

      {/* Toast */}
      {toastMsg && (
        <div className="absolute bottom-4 left-1/2 -translate-x-1/2 bg-gray-900/90 text-white text-xs font-medium px-3.5 py-1.5 rounded-full shadow-lg pointer-events-none whitespace-nowrap">
          {toastMsg}
        </div>
      )}

      {pendingDeleteEntry && (
        <DeleteConfirmationDialog
          entryTitle={pendingDeleteEntry.title}
          isDeleting={deletingItemId === pendingDeleteEntry.id}
          onCancel={handleCancelDelete}
          onConfirm={() => void handleConfirmDelete()}
        />
      )}
    </div>
  );
}

function applyEntryFilter(entries: EntryItem[], filter: FilterValue): EntryItem[] {
  if (filter === "suggestions" || filter === "all") return entries;
  // "totp" filter is handled server-side (matches any entry with an OTP secret,
  // regardless of its primary kind), so skip client-side kind filtering.
  if (filter === "totp") return entries;
  return entries.filter((entry) => entry.kind === filter);
}

function getEmptyDetailMessage(
  filter: FilterValue,
  filterLabel: string,
  resultCount: number,
  connected: boolean,
  vaultOpen: boolean,
): string {
  if (!connected) {
    return "Open LumenPass Desktop";
  }

  if (!vaultOpen) {
    return "Unlock your vault in LumenPass Desktop";
  }

  if (resultCount > 0) {
    return filter === "suggestions" ? "Select a login" : "Select an item";
  }

  if (filter === "suggestions") {
    return "No logins for this site";
  }

  if (filter === "all") {
    return "No items in your vault";
  }

  return `No ${filterLabel.toLowerCase()} found`;
}

// ─── List row ──────────────────────────────────────────────────────────────────

function ListRow({ entry, selected, onClick }: { entry: EntryItem; selected: boolean; onClick: () => void }) {
  return (
    <div className="px-2 py-0.5">
      <button
        onClick={onClick}
        className={`group w-full flex items-center gap-3 px-2.5 py-2.5 text-left rounded-xl transition-colors ${
          selected ? "bg-brand-600 dark:bg-brand-700" : "hover:bg-gray-50 dark:hover:bg-gray-800/40"
        }`}
      >
        {/* Avatar */}
        <EntryAvatar entry={entry} sizeClassName="w-10 h-10" textClassName="text-[11px]" />

        {/* Text */}
        <div className="flex-1 min-w-0">
          <p className={`text-[14px] font-semibold truncate leading-snug ${
            selected ? "text-white" : "text-gray-900 dark:text-gray-100"
          }`}>
            {entry.title}
          </p>
          {entry.username && (
            <p className={`text-[12px] truncate leading-snug mt-0.5 ${
              selected ? "text-white/70" : "text-gray-400 dark:text-gray-500"
            }`}>
              {entry.username}
            </p>
          )}
        </div>

        {entry.hasPasskey && (
          <div
            className={`shrink-0 rounded-lg p-1 transition-colors ${
              selected
                ? "bg-white shadow-sm ring-1 ring-black/10 dark:ring-white/20"
                : "bg-brand-50 group-hover:bg-brand-100 dark:bg-brand-950/40 dark:group-hover:bg-brand-900/40"
            }`}
            title="Passkey available"
          >
            <PasskeyGlyph className="h-[18px] w-[18px]" />
          </div>
        )}
      </button>
    </div>
  );
}

// ─── Detail panel ─────────────────────────────────────────────────────────────

interface DetailProps {
  entry: EntryItem;
  fullEntry: EntryDetail | null;
  loading: boolean;
  revealPassword: boolean;
  copiedField: string | null;
  onReveal: () => void;
  onCopy: (value: string, field: string) => void;
  onFill: () => void;
  onOpenUrl?: () => void;
}

// ─── Password strength ────────────────────────────────────────────────────────

function pwStrength(pwd: string): { label: string; color: string } {
  if (!pwd) return { label: "", color: "" };
  let s = 0;
  if (pwd.length >= 8) s++;
  if (pwd.length >= 14) s++;
  if (/[A-Z]/.test(pwd)) s++;
  if (/[a-z]/.test(pwd)) s++;
  if (/[0-9]/.test(pwd)) s++;
  if (/[^A-Za-z0-9]/.test(pwd)) s++;
  if (s <= 2) return { label: "Weak", color: "#ef4444" };
  if (s <= 3) return { label: "Fair", color: "#f59e0b" };
  if (s <= 4) return { label: "Good", color: "#84cc16" };
  return { label: "Fantastic", color: "#10b981" };
}

const FIELD_HAS_VALUE = (v: string | undefined | null) =>
  !!v && v.trim() !== "" && v.trim() !== "—" && v.trim() !== "-";

function normalizeOpenableUrl(value: string | undefined | null): string | null {
  const trimmed = value?.trim();
  if (!trimmed) return null;

  const candidate = /^[a-z][a-z0-9+.-]*:/i.test(trimmed) ? trimmed : `https://${trimmed}`;

  try {
    const parsed = new URL(candidate);
    if (parsed.protocol !== "http:" && parsed.protocol !== "https:") {
      return null;
    }
    return parsed.toString();
  } catch {
    return null;
  }
}

const HIDE_CUSTOM_FIELD = /secret|seed|base32|timeotp|^kpex_|^lp_social_/i;

function isProtectedCustomFieldLabel(label: string): boolean {
  const normalized = label.trim().toLowerCase();
  return normalized.includes("sensitive")
    || normalized === "otpauth"
    || normalized.includes("secret")
    || normalized.includes("token")
    || (normalized.includes("pass") && !normalized.includes("passkey"));
}

const SOCIAL_PROVIDER_LABEL: Record<string, string> = {
  google: "Google",
  apple: "Apple",
  facebook: "Facebook",
  github: "GitHub",
  microsoft: "Microsoft",
  twitter: "X (Twitter)",
  linkedin: "LinkedIn",
};

const SOCIAL_PROVIDER_COLOR: Record<string, string> = {
  google: "#4285F4",
  apple: "#1C1C1E",
  facebook: "#1877F2",
  github: "#24292E",
  microsoft: "#0078D4",
  twitter: "#1DA1F2",
  linkedin: "#0A66C2",
};

function DetailPanel({
  entry,
  fullEntry,
  loading,
  revealPassword,
  copiedField,
  onReveal,
  onCopy,
  onFill,
  onOpenUrl,
}: DetailProps) {
  const detail: EntryItem & Partial<EntryDetail> = fullEntry ?? entry;
  const password = detail.password ?? "";
  const hasPassword = password.length > 0;
  const strength = pwStrength(password);
  const detailUrl = detail.url ?? entry.url ?? "";
  const openableUrl = normalizeOpenableUrl(detailUrl);
  const entryKind = detail.kind ?? entry.kind ?? (hasPassword ? "login" : "unknown");
  const canOpenLoginUrl = entryKind === "login" && !!openableUrl && !!onOpenUrl;
  const [revealedCustomSecretFields, setRevealedCustomSecretFields] = useState<Record<string, boolean>>({});

  const allCustomFields = detail.customFields ?? [];
  const socialProvider = entry.socialProvider
    || allCustomFields.find((f) => f.label === "lp_social_provider")?.value
    || "";
  const socialLabel = allCustomFields.find((f) => f.label === "lp_social_label")?.value
    || SOCIAL_PROVIDER_LABEL[socialProvider.toLowerCase()]
    || (socialProvider ? socialProvider[0].toUpperCase() + socialProvider.slice(1) : "");
  const socialColor = SOCIAL_PROVIDER_COLOR[socialProvider.toLowerCase()] ?? "#444ce7";

  const nonHiddenCustomFields = allCustomFields.filter(
    (f) => !HIDE_CUSTOM_FIELD.test(f.label) && FIELD_HAS_VALUE(f.value),
  );

  const otpCustomFields = nonHiddenCustomFields.filter((f) => isOtpLikeFieldLabel(f.label));
  const visibleCustomFields = nonHiddenCustomFields.filter((f) => !isOtpLikeFieldLabel(f.label));
  const featuredTotps = buildFeaturedTotps({
    standardTotp: detail.totp,
    standardLabel: "one-time password",
    customFields: otpCustomFields,
  });

  const hasPasskey = !!allCustomFields.find(
    (f) => /^kpex_passkey_relying_party/i.test(f.label),
  );

  const hasAnyField =
    FIELD_HAS_VALUE(entry.username) ||
    hasPassword || loading ||
    FIELD_HAS_VALUE(detailUrl) ||
    visibleCustomFields.length > 0;

  useEffect(() => {
    setRevealedCustomSecretFields({});
  }, [entry.id]);

  return (
    <div className="min-h-full pb-5">

      {/* ── Header ── */}
      <div className="flex items-start gap-4 px-5 pt-5 pb-5">
        <div className="shrink-0 shadow-sm">
          <EntryAvatar entry={entry} sizeClassName="w-[52px] h-[52px]" textClassName="text-[15px]" />
        </div>
        <div className="min-w-0 flex-1 pt-0.5">
          <h2 className="text-[17px] font-bold text-gray-900 dark:text-gray-100 leading-snug truncate">{entry.title}</h2>
          {FIELD_HAS_VALUE(detailUrl) && (
            <p className="text-[12px] text-gray-400 dark:text-gray-500 truncate">
              {extractDomain(detailUrl) || detailUrl}
            </p>
          )}
        </div>
        <div className="ml-2 flex shrink-0 items-start gap-2 self-start">
          {canOpenLoginUrl && (
            <button
              onClick={onOpenUrl}
              type="button"
              aria-label="Open website"
              title="Open website"
              className="inline-flex h-9 w-9 items-center justify-center rounded-xl border border-gray-200 bg-white text-gray-700 shadow-sm transition-all hover:bg-gray-50 active:scale-95 dark:border-gray-700 dark:bg-gray-800 dark:text-gray-100 dark:hover:bg-gray-700"
            >
              <ExternalLink className="h-4 w-4" />
              <span className="sr-only">Open website</span>
            </button>
          )}
          <button
            onClick={onFill}
            type="button"
            aria-label="Autofill"
            title="Autofill"
            className="inline-flex h-9 w-9 items-center justify-center rounded-xl bg-brand-600 text-white shadow-sm transition-all hover:bg-brand-700 active:scale-95"
          >
            <LogIn className="h-4 w-4" />
            <span className="sr-only">Autofill</span>
          </button>
        </div>
      </div>

      {/* ── Social login banner ── */}
      {!!socialProvider && (
        <div className="mx-5 mb-4 rounded-xl overflow-hidden border border-gray-100 dark:border-gray-800">
          <div className="px-4 py-2 text-[10px] font-semibold uppercase tracking-wide" style={{ color: socialColor }}>
            Sign in with
          </div>
          <div className="flex items-center gap-3 px-4 pb-3">
            <div className="w-8 h-8 rounded-lg border border-gray-100 dark:border-gray-700 bg-white dark:bg-gray-800 flex items-center justify-content-center shrink-0 flex items-center justify-center">
              <span className="text-[13px] font-bold" style={{ color: socialColor }}>
                {socialLabel ? socialLabel[0].toUpperCase() : "?"}
              </span>
            </div>
            <div>
              <p className="text-[14px] font-semibold text-gray-800 dark:text-gray-100">{socialLabel}</p>
              {entry.username && (
                <p className="text-[12px] text-gray-400 dark:text-gray-500">{entry.username}</p>
              )}
            </div>
          </div>
        </div>
      )}

      {/* ── Featured TOTP (top, prominent) ── */}
      {featuredTotps.length > 0 && (
        <div className="mx-5 mb-4 space-y-3">
          {featuredTotps.map((t) => (
            <FeaturedTotpRow
              key={t.key}
              totp={t.totp}
              label={t.label}
              copiedField={copiedField}
              onCopy={onCopy}
            />
          ))}
        </div>
      )}

      {/* ── Passkey banner ── */}
      {hasPasskey && (
        <div className="mx-5 mb-4 rounded-xl bg-[#5c4ed4] p-4">
          <div className="flex items-center justify-between mb-2">
            <p className="text-[13px] font-bold text-white">Passkey available</p>
          </div>
          <p className="text-[12px] text-white/80 mb-3 leading-relaxed">
            You can use a passkey for this item. It&apos;s easier and more secure than a password.
          </p>
        </div>
      )}

      {/* ── Unified fields card ── */}
      {hasAnyField && (
        <div className="mx-5 mb-5 rounded-xl border border-gray-100 dark:border-gray-800 overflow-hidden divide-y divide-gray-100 dark:divide-gray-800">

          {/* Username */}
          {FIELD_HAS_VALUE(entry.username) && (
            <CredentialRow label="username" value={entry.username!}
              fieldKey="username" copiedField={copiedField} onCopy={onCopy} />
          )}

          {/* Password */}
          {(hasPassword || loading) && (
            <div className="group flex items-start px-4 py-3 hover:bg-gray-50 dark:hover:bg-gray-800/30 transition-colors">
              <div className="flex-1 min-w-0">
                <div className="flex items-center gap-2 mb-1">
                  <p className="text-[12px] font-medium text-brand-600 dark:text-brand-400">password</p>
                  {!loading && hasPassword && strength.label && (
                    <span className="text-[11px] font-semibold" style={{ color: strength.color }}>
                      {strength.label}
                    </span>
                  )}
                </div>
                {loading ? (
                  <div className="flex items-center gap-1.5">
                    <Loader2 className="w-3 h-3 text-gray-300 animate-spin" />
                    <span className="text-[13px] text-gray-300">Loading…</span>
                  </div>
                ) : (
                  <p className="text-[14px] text-gray-800 dark:text-gray-200 font-mono tracking-wider">
                    {revealPassword ? password : "••••••••••••"}
                  </p>
                )}
              </div>
              {!loading && hasPassword && (
                <div className="flex items-center gap-0.5 shrink-0 mt-1">
                  <button onClick={onReveal}
                    className="p-1.5 rounded-lg text-gray-300 opacity-70 group-hover:opacity-100 hover:text-gray-500 hover:bg-gray-100 dark:hover:bg-gray-800 transition-all"
                    title={revealPassword ? "Hide" : "Reveal"}>
                    {revealPassword ? <EyeOff className="w-4 h-4" /> : <Eye className="w-4 h-4" />}
                  </button>
                  <button onClick={() => onCopy(password, "password")}
                    className="p-1.5 rounded-lg text-gray-300 opacity-70 group-hover:opacity-100 hover:text-gray-500 hover:bg-gray-100 dark:hover:bg-gray-800 transition-all"
                    title="Copy password">
                    {copiedField === "password" ? <Check className="w-4 h-4 text-emerald-500" /> : <Copy className="w-4 h-4" />}
                  </button>
                </div>
              )}
            </div>
          )}

          {/* Standard TOTP attribute is rendered as a featured row above the card. */}

          {/* Website */}
          {FIELD_HAS_VALUE(detailUrl) && (
            <div className="group flex items-start px-4 py-3 hover:bg-gray-50 dark:hover:bg-gray-800/30 transition-colors">
              <div className="flex-1 min-w-0">
                <p className="text-[12px] font-medium text-brand-600 dark:text-brand-400 mb-1">website</p>
                {openableUrl ? (
                  <a href={openableUrl} target="_blank" rel="noreferrer"
                    className="text-[14px] text-gray-800 dark:text-gray-200 hover:text-brand-600 hover:underline truncate block">
                    {detailUrl}
                  </a>
                ) : (
                  <p className="text-[14px] text-gray-800 dark:text-gray-200 truncate">{detailUrl}</p>
                )}
              </div>
              {openableUrl && (
                <button onClick={onOpenUrl ?? (() => window.open(openableUrl, "_blank", "noopener,noreferrer"))}
                  className="p-1.5 mt-1 rounded-lg text-gray-300 opacity-70 group-hover:opacity-100 hover:text-gray-500 hover:bg-gray-100 dark:hover:bg-gray-800 transition-all shrink-0"
                  title="Open in new tab">
                  <ExternalLink className="w-4 h-4" />
                </button>
              )}
            </div>
          )}

          {/* Custom fields */}
          {visibleCustomFields.map((f, index) => {
            const fieldKey = `custom:${index}:${f.label}`;
            const secret = f.secret || isProtectedCustomFieldLabel(f.label);
            return (
              <CredentialRow
                key={fieldKey}
                label={f.label}
                value={f.value}
                fieldKey={fieldKey}
                copiedField={copiedField}
                secret={secret}
                revealed={revealedCustomSecretFields[fieldKey] === true}
                onReveal={() =>
                  setRevealedCustomSecretFields((current) => ({
                    ...current,
                    [fieldKey]: current[fieldKey] !== true,
                  }))
                }
                onCopy={onCopy}
              />
            );
          })}

        </div>
      )}

    </div>
  );
}

function DetailActionBar({
  showActions,
  onEdit,
  onDelete,
  editPending,
  deletePending,
}: {
  showActions: boolean;
  onEdit?: () => void;
  onDelete?: () => void;
  editPending: boolean;
  deletePending: boolean;
}) {
  return (
    <div className="px-3 py-2.5 border-t border-[#dbe7ff] dark:border-gray-800 bg-white dark:bg-gray-900 shrink-0">
      <div className="flex items-center justify-end gap-2 min-h-[34px]">
        {showActions && (
          <>
        <button
          type="button"
          onClick={onEdit}
          disabled={editPending || deletePending}
          className="inline-flex items-center gap-1.5 rounded-lg border border-gray-200 bg-white px-3 py-1.5 text-[12px] font-semibold text-gray-700 shadow-sm transition-colors hover:bg-gray-50 disabled:cursor-not-allowed disabled:opacity-60 dark:border-gray-700 dark:bg-gray-800 dark:text-gray-100 dark:hover:bg-gray-700"
        >
          {editPending ? (
            <Loader2 className="h-3.5 w-3.5 animate-spin" />
          ) : (
            <PencilLine className="h-3.5 w-3.5" />
          )}
          Edit
        </button>
        <button
          type="button"
          onClick={onDelete}
          disabled={editPending || deletePending}
          className="inline-flex items-center gap-1.5 rounded-lg border border-rose-200 bg-rose-50 px-3 py-1.5 text-[12px] font-semibold text-rose-700 shadow-sm transition-colors hover:bg-rose-100 disabled:cursor-not-allowed disabled:opacity-60 dark:border-rose-900/60 dark:bg-rose-950/40 dark:text-rose-300 dark:hover:bg-rose-950/60"
        >
          {deletePending ? (
            <Loader2 className="h-3.5 w-3.5 animate-spin" />
          ) : (
            <Trash2 className="h-3.5 w-3.5" />
          )}
          Delete
        </button>
          </>
        )}
      </div>
    </div>
  );
}

function DeleteConfirmationDialog({
  entryTitle,
  isDeleting,
  onCancel,
  onConfirm,
}: {
  entryTitle: string;
  isDeleting: boolean;
  onCancel: () => void;
  onConfirm: () => void;
}) {
  return (
    <div className="absolute inset-0 z-30 flex items-center justify-center bg-slate-950/28 px-6 backdrop-blur-[1px]">
      <div className="w-full max-w-[320px] rounded-3xl border border-gray-200 bg-white p-5 shadow-2xl dark:border-gray-700 dark:bg-gray-900">
        <div className="flex items-start gap-3">
          <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-2xl bg-rose-100 text-rose-600 dark:bg-rose-950/50 dark:text-rose-300">
            <AlertTriangle className="h-5 w-5" />
          </div>
          <div className="min-w-0">
            <h3 className="text-[15px] font-bold text-gray-900 dark:text-gray-100">
              Delete item?
            </h3>
            <p className="mt-1 text-[13px] leading-relaxed text-gray-500 dark:text-gray-400">
              <span className="font-semibold text-gray-700 dark:text-gray-200">
                {entryTitle}
              </span>
              {" "}will be moved to Trash in LumenPass Desktop.
            </p>
          </div>
        </div>

        <div className="mt-5 flex items-center justify-end gap-3">
          <button
            type="button"
            onClick={onCancel}
            disabled={isDeleting}
            className="rounded-xl border border-gray-200 bg-white px-4 py-2.5 text-[13px] font-semibold text-gray-600 transition-colors hover:bg-gray-50 disabled:cursor-not-allowed disabled:opacity-60 dark:border-gray-700 dark:bg-gray-800 dark:text-gray-200 dark:hover:bg-gray-700"
          >
            Cancel
          </button>
          <button
            type="button"
            onClick={onConfirm}
            disabled={isDeleting}
            className="inline-flex items-center gap-2 rounded-xl border border-rose-200 bg-rose-600 px-4 py-2.5 text-[13px] font-semibold text-white transition-colors hover:bg-rose-700 disabled:cursor-not-allowed disabled:opacity-60 dark:border-rose-800"
          >
            {isDeleting && <Loader2 className="h-4 w-4 animate-spin" />}
            {isDeleting ? "Deleting..." : "Delete"}
          </button>
        </div>
      </div>
    </div>
  );
}

function EntryAvatar({
  entry,
  sizeClassName,
  textClassName,
}: {
  entry: EntryItem;
  sizeClassName: string;
  textClassName: string;
}) {
  const [showFallback, setShowFallback] = useState(!entry.favicon);
  const avatar = pastelAvatar(entry.title);
  const abbr = initials(entry.title);
  const imgRef = useRef<HTMLImageElement | null>(null);

  useEffect(() => {
    setShowFallback(!entry.favicon);
  }, [entry.favicon]);

  const faviconSrc = entry.favicon ? googleFaviconUrlForDisplay(entry.favicon) : "";

  const validateFavicon = useCallback(() => {
    const img = imgRef.current;
    if (!img) return;
    // Many sites return Google's generic tiny "globe" favicon; it looks blurry at 40-52px.
    // If the decoded bitmap is too small, prefer our initials avatar fallback.
    const w = img.naturalWidth || 0;
    const h = img.naturalHeight || 0;
    if (w > 0 && h > 0 && (w < 48 || h < 48)) {
      setShowFallback(true);
    }
  }, []);

  return (
    <div
      className={`shrink-0 rounded-xl overflow-hidden flex items-center justify-center bg-white shadow-sm ring-1 ring-black/5 dark:bg-gray-800 dark:ring-white/10 ${sizeClassName}`}
    >
      {!showFallback && entry.favicon ? (
        <img
          ref={imgRef}
          src={faviconSrc}
          alt=""
          className="h-full w-full object-contain bg-white p-[3px] dark:bg-gray-900"
          decoding="async"
          onError={() => setShowFallback(true)}
          onLoad={validateFavicon}
        />
      ) : (
        <div
          className={`w-full h-full flex items-center justify-center font-bold ${textClassName}`}
          style={{ backgroundColor: avatar.bg, color: avatar.fg }}
        >
          {abbr}
        </div>
      )}
    </div>
  );
}

// ─── Featured TOTP row (top of detail panel, large + prominent) ───────────────

function FeaturedTotpRow({ totp, label = "one-time password", copiedField, onCopy }: {
  totp: string;
  label?: string;
  copiedField: string | null;
  onCopy: (value: string, field: string) => void;
}) {
  const isUri = totp.startsWith("otpauth://");
  const [code, setCode] = useState<string | null>(isUri ? null : totp);
  const [remaining, setRemaining] = useState(() => totpCountdown());

  useEffect(() => {
    if (!isUri) { setCode(totp); return; }
    let cancelled = false;
    const refresh = () => {
      computeTotp(totp).then((c) => { if (!cancelled) setCode(c); });
    };
    refresh();
    const id = setInterval(refresh, 1000);
    return () => { cancelled = true; clearInterval(id); };
  }, [totp, isUri]);

  useEffect(() => {
    const tick = () => setRemaining(totpCountdown());
    const id = setInterval(tick, 1000);
    return () => clearInterval(id);
  }, []);

  const display = code ?? "······";
  const formatted = display.length === 6
    ? `${display.slice(0, 3)} ${display.slice(3)}`
    : display;
  const copyValue = code ?? totp;

  const r = 14;
  const circumference = 2 * Math.PI * r;
  const dash = (remaining / 30) * circumference;
  const timerColor = remaining <= 5 ? "#ef4444" : remaining <= 10 ? "#f59e0b" : "#10b981";

  return (
    <div className="group relative rounded-2xl border border-emerald-200 bg-gradient-to-br from-emerald-50 via-white to-white px-5 py-4 shadow-sm dark:border-emerald-900/40 dark:from-emerald-950/40 dark:via-gray-900 dark:to-gray-900">
      <div className="flex items-center justify-between mb-2">
        <p className="text-[11px] font-bold uppercase tracking-[0.12em] text-emerald-600 dark:text-emerald-400">
          {label}
        </p>
        <button
          onClick={() => onCopy(copyValue, label)}
          className="inline-flex items-center gap-1.5 rounded-lg border border-emerald-200 bg-white px-2.5 py-1 text-[12px] font-semibold text-emerald-700 shadow-sm hover:bg-emerald-50 dark:border-emerald-800 dark:bg-gray-900 dark:text-emerald-300 dark:hover:bg-emerald-950/40"
          title="Copy OTP"
        >
          {copiedField === label ? (
            <>
              <Check className="w-3.5 h-3.5" />
              Copied
            </>
          ) : (
            <>
              <Copy className="w-3.5 h-3.5" />
              Copy
            </>
          )}
        </button>
      </div>

      <div className="flex items-center gap-4">
        <p
          className="flex-1 text-[28px] font-mono font-bold tracking-[0.22em] leading-none transition-colors"
          style={{ color: code ? timerColor : undefined }}
        >
          {formatted}
        </p>
        {code && (
          <div className="relative shrink-0 w-9 h-9">
            <svg width="36" height="36" viewBox="0 0 36 36" className="-rotate-90">
              <circle cx="18" cy="18" r={r} fill="none" stroke="#e5e7eb" strokeWidth="3" />
              <circle
                cx="18" cy="18" r={r}
                fill="none"
                stroke={timerColor}
                strokeWidth="3"
                strokeDasharray={`${dash} ${circumference}`}
                strokeLinecap="round"
              />
            </svg>
            <span
              className="absolute inset-0 flex items-center justify-center text-[11px] font-bold tabular-nums"
              style={{ color: timerColor }}
            >
              {remaining}
            </span>
          </div>
        )}
      </div>
    </div>
  );
}

// ─── Credential row (inside card) ─────────────────────────────────────────────

function CredentialRow({
  label, value, fieldKey, copiedField, onCopy, secret = false, revealed = false, onReveal,
}: {
  label: string;
  value: string;
  fieldKey: string;
  copiedField: string | null;
  onCopy: (value: string, field: string) => void;
  secret?: boolean;
  revealed?: boolean;
  onReveal?: () => void;
}) {
  const displayValue = secret && !revealed ? "••••••••••••" : value;

  return (
    <div className="group flex items-start px-4 py-3 hover:bg-gray-50 dark:hover:bg-gray-800/30 transition-colors">
      <div className="flex-1 min-w-0">
        <p className="text-[12px] font-medium text-brand-600 dark:text-brand-400 mb-1">{label}</p>
        <p className={`text-[14px] text-gray-800 dark:text-gray-200 truncate ${secret ? "font-mono tracking-wider" : ""}`}>
          {displayValue}
        </p>
      </div>
      {secret && onReveal && (
        <button
          onClick={onReveal}
          className="p-1.5 mt-1 rounded-lg text-gray-300 opacity-70 group-hover:opacity-100 hover:text-gray-500 dark:hover:text-gray-300 hover:bg-gray-100 dark:hover:bg-gray-800 transition-all shrink-0"
          title={revealed ? "Hide" : "Reveal"}
        >
          {revealed ? <EyeOff className="w-4 h-4" /> : <Eye className="w-4 h-4" />}
        </button>
      )}
      <button
        onClick={() => onCopy(value, fieldKey)}
        className="p-1.5 mt-1 rounded-lg text-gray-300 opacity-70 group-hover:opacity-100 hover:text-gray-500 dark:hover:text-gray-300 hover:bg-gray-100 dark:hover:bg-gray-800 transition-all shrink-0"
        title={`Copy ${label}`}
      >
        {copiedField === fieldKey
          ? <Check className="w-4 h-4 text-emerald-500" />
          : <Copy className="w-4 h-4" />}
      </button>
    </div>
  );
}

// ─── List empty state ──────────────────────────────────────────────────────────

function ListEmptyState({ title, subtitle }: { title: string; subtitle?: string }) {
  return (
    <div className="px-3 py-6 text-center">
      <p className="text-xs font-medium text-gray-400 dark:text-gray-500">{title}</p>
      {subtitle && <p className="text-[11px] text-gray-300 dark:text-gray-600 mt-1">{subtitle}</p>}
    </div>
  );
}
