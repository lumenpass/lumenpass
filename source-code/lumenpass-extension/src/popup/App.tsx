import React, { useState, useEffect, useCallback } from "react";
import browser from "webextension-polyfill";
import SearchView from "./views/SearchView";
import SettingsView from "./views/SettingsView";
import PasswordGeneratorPanel from "./views/PasswordGeneratorPanel";
import VaultUnlockView from "./views/VaultUnlockView";
import BrandExtensionIcon from "../components/BrandExtensionIcon";
import { Settings, KeyRound, RefreshCw } from "lucide-react";
import type { LucideIcon } from "lucide-react";
import type { ExtensionSettings } from "../lib/storage";
import type { ExtMessage, ExtResponse } from "../lib/utils";

type View = "search" | "settings";

function sendMessage<T>(msg: ExtMessage): Promise<ExtResponse<T>> {
  return browser.runtime.sendMessage(msg) as Promise<ExtResponse<T>>;
}

export default function App() {
  const [view, setView] = useState<View>("search");
  const [settings, setSettings] = useState<ExtensionSettings | null>(null);
  const [connected, setConnected] = useState<boolean | null>(null);
  const [vaultOpen, setVaultOpen] = useState<boolean | null>(null);
  const [currentUrl, setCurrentUrl] = useState("");
  const [query, setQuery] = useState("");
  const [isGeneratorOpen, setIsGeneratorOpen] = useState(false);
  const [darkMode, setDarkMode] = useState(
    window.matchMedia("(prefers-color-scheme: dark)").matches,
  );

  // Sync dark mode with system preference
  useEffect(() => {
    const mq = window.matchMedia("(prefers-color-scheme: dark)");
    const handler = (e: MediaQueryListEvent) => setDarkMode(e.matches);
    mq.addEventListener("change", handler);
    return () => mq.removeEventListener("change", handler);
  }, []);

  // Load settings + ping desktop on mount (with a fast retry on transient failure)
  useEffect(() => {
    let cancelled = false;
    (async () => {
      const [settingsRes, tabRes] = await Promise.allSettled([
        sendMessage<ExtensionSettings>({ type: "GET_SETTINGS" }),
        sendMessage<{ url: string }>({ type: "GET_CURRENT_TAB_URL" }),
      ]);

      if (!cancelled) {
        if (settingsRes.status === "fulfilled" && settingsRes.value.ok) {
          setSettings(settingsRes.value.data ?? null);
        }
        if (tabRes.status === "fulfilled" && tabRes.value.ok) {
          setCurrentUrl(tabRes.value.data?.url ?? "");
        }
      }

      // First ping — the background SW may still be cold-starting. Give it
      // a fast second attempt before showing "Desktop not running".
      let pingRes = await sendMessage<{ connected: boolean; vaultOpen?: boolean }>({ type: "PING" });
      if (!pingRes.ok && !cancelled) {
        // Wait a short beat (the SW reconnect loop starts at 1 s) and retry.
        await new Promise<void>((resolve) => setTimeout(resolve, 800));
        pingRes = await sendMessage<{ connected: boolean; vaultOpen?: boolean }>({ type: "PING" });
      }
      if (!cancelled) {
        if (pingRes.ok) {
          setConnected(true);
          setVaultOpen(pingRes.data?.vaultOpen ?? true);
        } else {
          setConnected(false);
          setVaultOpen(null);
        }
      }
    })();
    return () => { cancelled = true; };
  }, []);

  const handleSettingsSaved = useCallback((updated: ExtensionSettings) => {
    setSettings(updated);
  }, []);

  const handleReconnect = useCallback(async () => {
    setConnected(null);
    setVaultOpen(null);
    const res = await sendMessage<{ connected: boolean; vaultOpen?: boolean }>({ type: "PING" });
    setConnected(res.ok);
    setVaultOpen(res.ok ? (res.data?.vaultOpen ?? true) : null);
  }, []);

  const handleUnlocked = useCallback(() => {
    setConnected(true);
    setVaultOpen(true);
  }, []);

  useEffect(() => {
    if (view !== "search") {
      setIsGeneratorOpen(false);
    }
  }, [view]);

  // Poll desktop status while vault is locked or disconnected.
  // Use a shorter interval when disconnected so the UI recovers quickly
  // once the SW's reconnect loop succeeds.
  useEffect(() => {
    if (connected === null) return;
    if (connected === true && vaultOpen !== false) return;
    const intervalMs = connected === false ? 1500 : 3000;
    const id = window.setInterval(async () => {
      const res = await sendMessage<{ connected: boolean; vaultOpen?: boolean }>({ type: "PING" });
      if (res.ok) {
        setConnected(true);
        setVaultOpen(res.data?.vaultOpen ?? true);
      } else {
        setConnected(false);
        setVaultOpen(null);
      }
    }, intervalMs);
    return () => window.clearInterval(id);
  }, [connected, vaultOpen]);

  const isVaultLocked = connected === false || vaultOpen === false;

  return (
    <div className={darkMode ? "dark" : ""}>
      <div className="flex h-[580px] w-[660px] flex-col overflow-hidden bg-white text-gray-900 animate-fade-in dark:bg-gray-900 dark:text-gray-100">
        {/* Header */}
        <header className="flex items-center gap-3 border-b border-[#dbe7ff] bg-[#f3f7ff] px-4 py-2.5 shrink-0 dark:border-gray-800 dark:bg-gray-900">
          <div className="flex items-center gap-2.5 shrink-0">
            <BrandExtensionIcon className="h-8 w-8" />
            <div className="text-sm font-semibold tracking-tight text-gray-700 dark:text-gray-200">
              <span>{settings?.vaultName ?? "LumenPass"}</span>
            </div>
          </div>

          {view === "search" && !isVaultLocked && (
            <div className="min-w-0 flex-1 max-w-[360px]">
              <div className="flex items-center gap-2 rounded-xl border border-gray-200 bg-gray-50 px-3 py-2 transition-colors focus-within:border-brand-300 focus-within:bg-white dark:border-gray-700 dark:bg-gray-800/80 dark:focus-within:border-brand-500 dark:focus-within:bg-gray-900">
                <SearchViewHeaderIcon />
                <input
                  autoFocus
                  type="text"
                  value={query}
                  onChange={(e) => setQuery(e.target.value)}
                  placeholder="Search vault..."
                  className="min-w-0 flex-1 bg-transparent text-sm text-gray-900 outline-none placeholder:text-gray-400 dark:text-gray-100 dark:placeholder:text-gray-500"
                />
              </div>
            </div>
          )}

          {view !== "search" && <div className="flex-1" />}

          <div className="ml-auto flex items-center gap-2 shrink-0">
            {connected !== null && (
              <div
                className={`inline-flex items-center gap-2 rounded-full border px-3 py-1 text-xs font-semibold shadow-sm ${
                  connected
                    ? "border-emerald-200 bg-emerald-50 text-emerald-700 dark:border-emerald-900/60 dark:bg-emerald-950/40 dark:text-emerald-300"
                    : "border-rose-200 bg-rose-50 text-rose-700 dark:border-rose-900/60 dark:bg-rose-950/40 dark:text-rose-300"
                }`}
              >
                <span
                  className={`h-2 w-2 rounded-full ${
                    connected ? "bg-emerald-500" : "bg-rose-500"
                  }`}
                />
                <span>{connected ? "Connected" : "Disconnected"}</span>
              </div>
            )}

            <HeaderIconButton
              label="Reload extension"
              icon={RefreshCw}
              onClick={() => void browser.runtime.reload()}
            />

            {view === "search" && !isVaultLocked && (
              <HeaderIconButton
                label="Password generator"
                icon={KeyRound}
                active={isGeneratorOpen}
                onClick={() => setIsGeneratorOpen((open) => !open)}
              />
            )}

            <HeaderIconButton
              label={view === "settings" ? "Back to search" : "Settings"}
              icon={Settings}
              active={view === "settings"}
              onClick={() => {
                setIsGeneratorOpen(false);
                setView(view === "settings" ? "search" : "settings");
              }}
            />
          </div>
        </header>

        {/* Slim disconnected banner */}
        {connected === false && view === "search" && !isVaultLocked && (
          <div className="flex items-center gap-2 px-4 py-1.5 bg-amber-50 dark:bg-amber-950/30 border-b border-amber-100 dark:border-amber-900/50 shrink-0">
            <span className="text-xs text-amber-700 dark:text-amber-400">
              Desktop app not running.
            </span>
            <button
              onClick={handleReconnect}
              className="text-xs font-medium text-amber-800 dark:text-amber-300 underline"
            >
              Retry
            </button>
          </div>
        )}

        {/* Main content */}
        <main className="relative flex-1 min-h-0 overflow-hidden">
          {view === "search" && isVaultLocked ? (
            <VaultUnlockView
              connected={connected === true}
              sendMessage={sendMessage}
              onUnlocked={handleUnlocked}
              onReconnect={handleReconnect}
            />
          ) : view === "search" ? (
            <SearchView
              settings={settings}
              currentUrl={currentUrl}
              connected={connected === true}
              vaultOpen={vaultOpen !== false}
              query={query}
              sendMessage={sendMessage}
            />
          ) : (
            <SettingsView
              settings={settings}
              onSaved={handleSettingsSaved}
              sendMessage={sendMessage}
            />
          )}

          {view === "search" && isGeneratorOpen && !isVaultLocked && (
            <PasswordGeneratorPanel
              currentUrl={currentUrl}
              onClose={() => setIsGeneratorOpen(false)}
            />
          )}
        </main>
      </div>
    </div>
  );
}

function SearchViewHeaderIcon() {
  return (
    <svg
      className="h-4 w-4 shrink-0 text-gray-400 dark:text-gray-500"
      viewBox="0 0 20 20"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.8"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      <circle cx="8.5" cy="8.5" r="5.5" />
      <path d="M13 13l4 4" />
    </svg>
  );
}

type HeaderIconButtonProps = {
  label: string;
  icon: LucideIcon;
  active?: boolean;
  onClick: () => void;
};

function HeaderIconButton({ label, icon: Icon, active = false, onClick }: HeaderIconButtonProps) {
  return (
    <button
      onClick={onClick}
      aria-label={label}
      className={`group relative inline-flex h-8 w-8 items-center justify-center rounded-xl border transition-colors ${
        active
          ? "border-brand-200 bg-brand-50 text-brand-600 dark:border-brand-800 dark:bg-brand-900/40 dark:text-brand-400"
          : "border-gray-200 bg-gray-50 text-gray-400 hover:bg-gray-100 hover:text-gray-600 dark:border-gray-700 dark:bg-gray-800/80 dark:hover:bg-gray-800 dark:hover:text-gray-300"
      }`}
    >
      <Icon className="h-4 w-4" />
      <span className="pointer-events-none absolute right-0 top-full z-20 mt-2 whitespace-nowrap rounded-md bg-gray-900 px-2 py-1 text-[11px] font-medium text-white opacity-0 shadow-lg transition-opacity duration-150 group-hover:opacity-100 group-focus-visible:opacity-100 dark:bg-gray-100 dark:text-gray-900">
        {label}
      </span>
    </button>
  );
}
