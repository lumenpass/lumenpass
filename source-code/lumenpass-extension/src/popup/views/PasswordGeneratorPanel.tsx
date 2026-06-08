import React, { useEffect, useRef, useState } from "react";
import browser from "webextension-polyfill";
import BrandExtensionIcon from "../../components/BrandExtensionIcon";
import {
  ArrowLeft,
  Check,
  ChevronDown,
  ChevronRight,
  Copy,
  History,
  RefreshCw,
  Trash2,
  X,
} from "lucide-react";
import {
  appendGeneratorHistory,
  getGeneratorPreferences,
  saveGeneratorPreferences,
  type GeneratorHistoryItem,
  type GeneratorType,
} from "../../lib/storage";
import type { ExtMessage, ExtResponse } from "../../lib/utils";
import {
  describeGeneratorType,
  generatePasswordFromConfig,
  getGeneratorConfig,
} from "../../lib/password-generator";

interface Props {
  currentUrl: string;
  onClose: () => void;
}

const TYPE_OPTIONS: Array<{ value: GeneratorType; label: string }> = [
  { value: "smart", label: "Smart Password" },
  { value: "memorable", label: "Memorable Password" },
  { value: "pin", label: "PIN Code" },
];

function sendMessage<T>(msg: ExtMessage): Promise<ExtResponse<T>> {
  return browser.runtime.sendMessage(msg) as Promise<ExtResponse<T>>;
}

export default function PasswordGeneratorPanel({ currentUrl: _currentUrl, onClose }: Props) {
  const [password, setPassword] = useState("");
  const [currentType, setCurrentType] = useState<GeneratorType>("smart");
  const [history, setHistory] = useState<GeneratorHistoryItem[]>([]);
  const [copied, setCopied] = useState(false);
  const [statusMessage, setStatusMessage] = useState<string | null>(null);
  const [isReady, setIsReady] = useState(false);
  const [passwordLength, setPasswordLength] = useState(25);
  const [includeLetters, setIncludeLetters] = useState(true);
  const [includeNumbers, setIncludeNumbers] = useState(true);
  const [includeSpecialChars, setIncludeSpecialChars] = useState(true);
  const [screen, setScreen] = useState<"generator" | "history">("generator");
  const copiedTimerRef = useRef<number | null>(null);
  const statusTimerRef = useRef<number | null>(null);

  useEffect(() => {
    let cancelled = false;

    const load = async () => {
      const prefs = await getGeneratorPreferences();
      if (cancelled) return;

      const initialType: GeneratorType = "smart";
      const initialConfig = getGeneratorConfig(initialType);
      applyPresetState(initialType, initialConfig);
      setHistory(prefs.history);

      const initialPassword = generatePasswordFromConfig(initialConfig);
      const next = await appendGeneratorHistory({
        password: initialPassword,
        type: initialType,
        createdAt: Date.now(),
      });
      if (cancelled) return;

      setPassword(initialPassword);
      setCurrentType(initialType);
      setHistory(next.history);
      setIsReady(true);
    };

    void load();

    return () => {
      cancelled = true;
      if (copiedTimerRef.current) window.clearTimeout(copiedTimerRef.current);
      if (statusTimerRef.current) window.clearTimeout(statusTimerRef.current);
    };
  }, []);

  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === "Escape") onClose();
    };
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, [onClose]);

  const setToast = (message: string) => {
    setStatusMessage(message);
    if (statusTimerRef.current) window.clearTimeout(statusTimerRef.current);
    statusTimerRef.current = window.setTimeout(() => setStatusMessage(null), 2200);
  };

  const persistPreferences = async (type: GeneratorType) => {
    await saveGeneratorPreferences({
      defaultType: type,
    });
  };

  const storeGeneratedPassword = async (nextPassword: string, type: GeneratorType) => {
    const next = await appendGeneratorHistory({
      password: nextPassword,
      type,
      createdAt: Date.now(),
    });
    setHistory(next.history);
  };

  const applyPresetState = (type: GeneratorType, config = getGeneratorConfig(type)) => {
    setCurrentType(type);
    setPasswordLength(config.length);
    setIncludeLetters(config.includeLowercase || config.includeUppercase);
    setIncludeNumbers(config.includeNumbers);
    setIncludeSpecialChars(config.includeSymbols);
  };

  const buildConfig = () => ({
    length: passwordLength,
    includeUppercase: includeLetters,
    includeLowercase: includeLetters,
    includeNumbers,
    includeSymbols: includeSpecialChars,
  });

  const regeneratePassword = async (type: GeneratorType) => {
    const nextPassword = generatePasswordFromConfig(buildConfig());
    setCurrentType(type);
    setPassword(nextPassword);
    await persistPreferences(type);
    await storeGeneratedPassword(nextPassword, type);
  };

  const handleTypeChange = async (event: React.ChangeEvent<HTMLSelectElement>) => {
    const nextType = event.target.value as GeneratorType;
    const nextConfig = getGeneratorConfig(nextType);
    applyPresetState(nextType, nextConfig);
    const nextPassword = generatePasswordFromConfig(nextConfig);
    setPassword(nextPassword);
    await persistPreferences(nextType);
  };

  const markCopied = () => {
    setCopied(true);
    if (copiedTimerRef.current) window.clearTimeout(copiedTimerRef.current);
    copiedTimerRef.current = window.setTimeout(() => setCopied(false), 1600);
  };

  const handleCopy = async (value: string) => {
    try {
      await navigator.clipboard.writeText(value);
      markCopied();
      setToast("Password copied");
    } catch {
      setToast("Copy failed");
    }
  };

  const handleUsePassword = async () => {
    if (!password || !isReady) return;

    const [copyResult, tabResult] = await Promise.allSettled([
      navigator.clipboard.writeText(password),
      browser.tabs.query({ active: true, currentWindow: true }),
    ]);

    if (copyResult.status === "fulfilled") {
      markCopied();
    }

    const tabId = tabResult.status === "fulfilled" ? tabResult.value[0]?.id : undefined;
    if (tabId === undefined) {
      setToast(copyResult.status === "fulfilled" ? "Password copied" : "No active tab found");
      return;
    }

    try {
      const response = await sendMessage({
        type: "AUTOFILL_GENERATED_PASSWORD",
        payload: { tabId, password },
      });

      if (!response.ok) {
        setToast(copyResult.status === "fulfilled" ? "Password copied, autofill failed" : "Autofill failed");
        return;
      }

      setToast(copyResult.status === "fulfilled" ? "Password copied and autofilled" : "Password autofilled");
      window.setTimeout(onClose, 500);
    } catch {
      setToast(copyResult.status === "fulfilled" ? "Password copied, autofill failed" : "Autofill failed");
    }
  };

  const handleRestoreHistory = async (item: GeneratorHistoryItem) => {
    setPassword(item.password);
    applyPresetState(item.type);
    await persistPreferences(item.type);
  };

  const handleClearHistory = async () => {
    setHistory([]);
    await saveGeneratorPreferences({ history: [] });
    setToast("History cleared");
  };

  const description = describeGeneratorType(currentType);

  const handleLengthChange = async (event: React.ChangeEvent<HTMLInputElement>) => {
    const nextLength = Number(event.target.value);
    setPasswordLength(nextLength);
    const nextPassword = generatePasswordFromConfig({
      ...buildConfig(),
      length: nextLength,
    });
    setPassword(nextPassword);
    await persistPreferences(currentType);
  };

  const handleCharacterToggle = async (
    key: "letters" | "numbers" | "special",
    checked: boolean,
  ) => {
    const next = {
      letters: includeLetters,
      numbers: includeNumbers,
      special: includeSpecialChars,
      [key]: checked,
    };

    if (!next.letters && !next.numbers && !next.special) {
      setToast("Choose at least one character set");
      return;
    }

    if (key === "letters") setIncludeLetters(checked);
    if (key === "numbers") setIncludeNumbers(checked);
    if (key === "special") setIncludeSpecialChars(checked);

    const nextPassword = generatePasswordFromConfig({
      length: passwordLength,
      includeUppercase: next.letters,
      includeLowercase: next.letters,
      includeNumbers: next.numbers,
      includeSymbols: next.special,
    });
    setPassword(nextPassword);
    await persistPreferences(currentType);
  };

  return (
    <div className="absolute inset-0 z-20 flex">
      <button
        type="button"
        aria-label="Close password generator"
        onClick={onClose}
        className="flex-1 bg-slate-950/18 backdrop-blur-[1px] animate-generator-overlay-in"
      />

      <aside className="relative flex h-full w-[418px] max-w-full flex-col border-l border-[#dbe7ff] bg-white shadow-[0_24px_80px_rgba(15,23,42,0.24)] animate-generator-panel-in dark:border-gray-800 dark:bg-gray-900">
        <div className="flex items-start justify-between bg-[#eef4ff] px-5 py-3">
          <div className="flex items-center gap-2.5">
            <BrandExtensionIcon className="h-8 w-8" />
            <p className="text-[18px] font-bold text-gray-900 dark:text-gray-100">
              Password Generator
            </p>
          </div>
          <button
            type="button"
            onClick={onClose}
            className="inline-flex h-10 w-10 items-center justify-center rounded-2xl text-brand-500 transition-colors hover:bg-brand-50 dark:text-brand-400 dark:hover:bg-brand-950/40"
            aria-label="Close password generator"
          >
            <X className="h-5 w-5" strokeWidth={2.4} />
          </button>
        </div>

        <div className="flex-1 overflow-y-auto px-5 pb-5">
          {screen === "generator" ? (
            <>
              <div className="pt-3">
                <div className="flex items-center justify-between gap-4">
                  <label htmlFor="generator-type" className="text-[15px] font-medium text-gray-500 dark:text-gray-400">
                    Type
                  </label>
                  <div className="relative">
                    <select
                      id="generator-type"
                      value={currentType}
                      onChange={(event) => void handleTypeChange(event)}
                      className="appearance-none rounded-[20px] border border-brand-400 bg-white py-2.5 pl-4 pr-11 text-[14px] font-medium text-gray-800 shadow-sm outline-none transition-colors focus:border-brand-500 dark:border-brand-500 dark:bg-gray-800 dark:text-gray-100"
                    >
                      {TYPE_OPTIONS.map((option) => (
                        <option key={option.value} value={option.value}>
                          {option.label}
                        </option>
                      ))}
                    </select>
                    <ChevronDown className="pointer-events-none absolute right-4 top-1/2 h-5 w-5 -translate-y-1/2 text-gray-500" />
                  </div>
                </div>
              </div>

              <div className="mt-3 rounded-[14px] border border-gray-200 bg-white px-4 py-2.5 shadow-[0_6px_20px_rgba(15,23,42,0.06)] dark:border-gray-700 dark:bg-gray-800/80">
                <div className="flex items-start gap-3">
                  <div className="min-w-0 flex-1 py-0.5 text-[14px] font-medium tracking-[0.01em] text-gray-800 dark:text-gray-100">
                    {password ? <PasswordValue password={password} /> : <span className="text-gray-400">Generating...</span>}
                  </div>
                  <div className="flex shrink-0 items-center gap-1">
                    <button
                      type="button"
                      onClick={() => void handleCopy(password)}
                      disabled={!isReady}
                      className="inline-flex h-9 w-9 items-center justify-center rounded-lg text-gray-500 transition-colors hover:bg-gray-100 hover:text-gray-700 disabled:cursor-wait disabled:opacity-60 dark:text-gray-400 dark:hover:bg-gray-700/70 dark:hover:text-gray-200"
                      aria-label="Copy password"
                    >
                      {copied ? <Check className="h-4 w-4 text-emerald-500" /> : <Copy className="h-4 w-4" />}
                    </button>
                    <button
                      type="button"
                      onClick={() => void regeneratePassword(currentType)}
                      disabled={!isReady}
                      className="inline-flex h-9 w-9 items-center justify-center rounded-lg text-gray-500 transition-colors hover:bg-gray-100 hover:text-gray-700 disabled:cursor-wait disabled:opacity-60 dark:text-gray-400 dark:hover:bg-gray-700/70 dark:hover:text-gray-200"
                      aria-label="Generate another password"
                    >
                      <RefreshCw className="h-4 w-4" />
                    </button>
                  </div>
                </div>
                <button
                  type="button"
                  onClick={() => void handleUsePassword()}
                  disabled={!isReady}
                  className="mt-3 inline-flex w-full items-center justify-center rounded-xl bg-brand-500 px-4 py-2.5 text-[14px] font-semibold text-white shadow-sm transition-colors hover:bg-brand-600 disabled:cursor-wait disabled:opacity-60 dark:bg-brand-500 dark:hover:bg-brand-400"
                >
                  Generate password
                </button>
              </div>

              <div className="mt-3 rounded-[20px] border border-gray-200 px-4 py-3.5 dark:border-gray-800">
                <div className="flex items-center justify-between text-[12px]">
                  <span className="text-[14px] font-medium text-gray-500 dark:text-gray-400">Password length</span>
                  <span className="text-[14px] font-semibold text-gray-700 dark:text-gray-200">{passwordLength}</span>
                </div>
                <div className="mt-2.5 px-1 py-1.5">
                  <input
                    type="range"
                    min="8"
                    max="64"
                    step="1"
                    value={passwordLength}
                    onChange={(event) => void handleLengthChange(event)}
                    className="generator-slider h-2 w-full cursor-pointer appearance-none rounded-full bg-gray-200 dark:bg-gray-700"
                  />
                </div>
                <div className="mt-1.5 flex items-center justify-between text-[11px] text-gray-400 dark:text-gray-500">
                  <span>8</span>
                  <span>64</span>
                </div>
              </div>

              <div className="mt-3 rounded-[20px] border border-gray-200 px-4 py-2.5 dark:border-gray-800">
                <ToggleRow
                  label="Include letters"
                  checked={includeLetters}
                  onChange={(checked) => void handleCharacterToggle("letters", checked)}
                />
                <ToggleRow
                  label="Include numbers"
                  checked={includeNumbers}
                  onChange={(checked) => void handleCharacterToggle("numbers", checked)}
                />
                <ToggleRow
                  label="Include special chars"
                  checked={includeSpecialChars}
                  onChange={(checked) => void handleCharacterToggle("special", checked)}
                  withBorder={false}
                />
              </div>

              <div className="mt-4 border-t border-gray-200 pt-3 dark:border-gray-800">
                <p className="text-[12px] leading-6 text-gray-700 dark:text-gray-300">
                  {description}
                </p>
              </div>

              <div className="mt-4 border-t border-gray-200 pt-3 dark:border-gray-800">
                <button
                  type="button"
                  onClick={() => setScreen("history")}
                  className="flex w-full items-center gap-3 text-left"
                >
                  <History className="h-6 w-6 text-gray-500 dark:text-gray-400" />
                  <span className="flex-1 text-[16px] font-medium text-gray-500 dark:text-gray-300">
                    Password Generator History
                  </span>
                  <ChevronRight className="h-5 w-5 text-gray-400" />
                </button>
              </div>
            </>
          ) : (
            <>
              <div className="pt-3">
                <button
                  type="button"
                  onClick={() => setScreen("generator")}
                  className="inline-flex items-center gap-2 rounded-xl px-1 py-1 text-[14px] font-medium text-gray-600 transition-colors hover:bg-gray-100 hover:text-gray-900 dark:text-gray-300 dark:hover:bg-gray-800 dark:hover:text-gray-100"
                >
                  <ArrowLeft className="h-4 w-4" />
                  Back
                </button>
              </div>

              <div className="mt-3 flex items-center gap-3">
                <History className="h-6 w-6 text-gray-500 dark:text-gray-400" />
                <span className="flex-1 text-[16px] font-semibold text-gray-800 dark:text-gray-100">
                  Password Generator History
                </span>
                <button
                  type="button"
                  onClick={() => void handleClearHistory()}
                  disabled={history.length === 0}
                  className="inline-flex items-center gap-1.5 rounded-xl px-2.5 py-1.5 text-[12px] font-medium text-gray-500 transition-colors hover:bg-gray-100 hover:text-gray-800 disabled:cursor-not-allowed disabled:opacity-40 dark:text-gray-400 dark:hover:bg-gray-800 dark:hover:text-gray-100"
                >
                  <Trash2 className="h-3.5 w-3.5" />
                  Clear
                </button>
              </div>

              <div className="mt-4 space-y-3">
                {history.length === 0 ? (
                  <div className="rounded-2xl border border-dashed border-gray-200 px-4 py-4 text-[13px] text-gray-400 dark:border-gray-700 dark:text-gray-500">
                    No generated passwords yet.
                  </div>
                ) : (
                  history.map((item) => (
                    <div
                      key={`${item.createdAt}-${item.password}`}
                      className="flex items-center gap-2 rounded-2xl border border-gray-200 bg-white px-3 py-3 shadow-sm dark:border-gray-700 dark:bg-gray-800/70"
                    >
                      <button
                        type="button"
                        onClick={() => {
                          void handleRestoreHistory(item);
                          setScreen("generator");
                        }}
                        className="min-w-0 flex-1 text-left"
                      >
                        <p className="truncate font-mono text-[13px] text-gray-800 dark:text-gray-100">
                          {item.password}
                        </p>
                        <p className="mt-1 text-[11px] text-gray-400 dark:text-gray-500">
                          {labelForType(item.type)} • {formatHistoryTime(item.createdAt)}
                        </p>
                      </button>
                      <button
                        type="button"
                        onClick={() => void handleCopy(item.password)}
                        className="inline-flex h-9 w-9 items-center justify-center rounded-xl text-gray-400 transition-colors hover:bg-gray-100 hover:text-gray-700 dark:hover:bg-gray-700/70 dark:hover:text-gray-200"
                        aria-label="Copy password from history"
                      >
                        <Copy className="h-4 w-4" />
                      </button>
                    </div>
                  ))
                )}
              </div>
            </>
          )}
        </div>

        {statusMessage && (
          <div className="pointer-events-none absolute bottom-16 left-1/2 z-30 -translate-x-1/2 rounded-full border border-gray-900/10 bg-gray-900 px-4 py-2 text-[12px] font-medium text-white shadow-[0_12px_30px_rgba(15,23,42,0.28)]">
            {statusMessage}
          </div>
        )}
      </aside>
    </div>
  );
}

function PasswordValue({ password }: { password: string }) {
  return (
    <div className="flex flex-wrap items-center gap-x-[0.02em] gap-y-1">
      {password.split("").map((char, index) => (
        <span key={`${char}-${index}`} className={characterColor(char)}>
          {char}
        </span>
      ))}
    </div>
  );
}

function characterColor(char: string): string {
  if (/[0-9]/.test(char)) return "text-brand-500";
  if (/[^A-Za-z0-9]/.test(char)) return "text-orange-500";
  return "text-gray-800 dark:text-gray-100";
}

function labelForType(type: GeneratorType): string {
  return TYPE_OPTIONS.find((option) => option.value === type)?.label ?? "Password";
}

function formatHistoryTime(timestamp: number): string {
  return new Intl.DateTimeFormat(undefined, {
    hour: "numeric",
    minute: "2-digit",
    month: "short",
    day: "numeric",
  }).format(timestamp);
}

function ToggleRow({
  label,
  checked,
  onChange,
  withBorder = true,
}: {
  label: string;
  checked: boolean;
  onChange: (checked: boolean) => void;
  withBorder?: boolean;
}) {
  return (
    <div className={`flex items-center justify-between py-2.5 ${withBorder ? "border-b border-gray-200 dark:border-gray-800" : ""}`}>
      <span className="text-[14px] font-medium text-gray-700 dark:text-gray-200">
        {label}
      </span>
      <label className="relative inline-flex cursor-pointer items-center">
        <input
          type="checkbox"
          checked={checked}
          onChange={(event) => onChange(event.target.checked)}
          className="peer sr-only"
        />
        <span className="h-7 w-[44px] rounded-full bg-gray-200 transition-colors after:absolute after:left-[3px] after:top-[3px] after:h-5 after:w-5 after:rounded-full after:bg-white after:shadow-sm after:transition-transform after:content-[''] peer-checked:bg-brand-500 peer-checked:after:translate-x-[16px] dark:bg-gray-700" />
      </label>
    </div>
  );
}
