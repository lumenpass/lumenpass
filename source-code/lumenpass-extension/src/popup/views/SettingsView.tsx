import React, { useState, useEffect, useRef } from "react";
import browser from "webextension-polyfill";
import { AlertCircle, CheckCircle2, Loader2 } from "lucide-react";
import type { ExtensionSettings } from "../../lib/storage";
import type { ExtMessage, ExtResponse } from "../../lib/utils";

interface Props {
  settings: ExtensionSettings | null;
  onSaved: (updated: ExtensionSettings) => void;
  sendMessage: <T>(msg: ExtMessage) => Promise<ExtResponse<T>>;
}

type SettingsToggleKey = "autofillEnabled" | "autoSubmit" | "autofillOnPageLoad";
type SettingsToggleState = Pick<ExtensionSettings, SettingsToggleKey>;
type ToastState = { type: "success" | "error"; message: string } | null;

function getExtensionVersion() {
  try {
    return browser.runtime.getManifest().version;
  } catch {
    return "unknown";
  }
}

export default function SettingsView({ settings, onSaved, sendMessage }: Props) {
  const [autofillEnabled, setAutofillEnabled] = useState(settings?.autofillEnabled ?? true);
  const [autoSubmit, setAutoSubmit] = useState(settings?.autoSubmit ?? false);
  const [autofillOnPageLoad, setAutofillOnPageLoad] = useState(settings?.autofillOnPageLoad ?? false);
  const [saving, setSaving] = useState(false);
  const [toast, setToast] = useState<ToastState>(null);
  const toastTimerRef = useRef<number | null>(null);
  const extensionVersion = getExtensionVersion();

  useEffect(() => {
    if (settings) {
      setAutofillEnabled(settings.autofillEnabled);
      setAutoSubmit(settings.autoSubmit);
      setAutofillOnPageLoad(settings.autofillOnPageLoad ?? false);
    }
  }, [settings]);

  useEffect(() => () => {
    if (toastTimerRef.current) window.clearTimeout(toastTimerRef.current);
  }, []);

  const showToast = (message: string, type: "success" | "error") => {
    setToast({ type, message });
    if (toastTimerRef.current) window.clearTimeout(toastTimerRef.current);
    toastTimerRef.current = window.setTimeout(() => setToast(null), 2200);
  };

  const applyToggleState = (state: SettingsToggleState) => {
    setAutofillEnabled(state.autofillEnabled);
    setAutoSubmit(state.autoSubmit);
    setAutofillOnPageLoad(state.autofillOnPageLoad);
  };

  const saveSettings = async (
    next: SettingsToggleState,
    previous: SettingsToggleState,
  ) => {
    setSaving(true);

    try {
      const res = await sendMessage<void>({
        type: "SAVE_SETTINGS",
        payload: next,
      });

      if (!res.ok) {
        throw new Error(res.error ?? "Could not save settings");
      }

      const baseSettings: ExtensionSettings = {
        autofillEnabled: true,
        autoSubmit: false,
        vaultName: "LumenPass",
        lastConnectedAt: null,
        autofillOnPageLoad: false,
        domainSetting: "default" as const,
        disabledAutofillDomains: [],
        ...settings,
      };
      const updated: ExtensionSettings = {
        ...baseSettings,
        ...next,
      };
      onSaved(updated);
      showToast("Settings saved", "success");
    } catch (error) {
      applyToggleState(previous);
      showToast(error instanceof Error ? error.message : "Could not save settings", "error");
    } finally {
      setSaving(false);
    }
  };

  const updateSetting = (
    key: SettingsToggleKey,
    value: boolean,
  ) => {
    const previous = {
      autofillEnabled,
      autoSubmit,
      autofillOnPageLoad,
    };
    const next = {
      autofillEnabled,
      autoSubmit,
      autofillOnPageLoad,
      [key]: value,
    };

    applyToggleState(next);

    void saveSettings(next, previous);
  };

  return (
    <div className="relative flex h-full flex-col gap-0 p-4">
      <h2 className="text-sm font-semibold text-gray-800 dark:text-gray-200 mb-4">Settings</h2>

      {/* Toggle: autofill */}
      <ToggleRow
        label="Autofill icons on login forms"
        description="Inject a LumenPass icon next to password fields"
        checked={autofillEnabled}
        onChange={(value) => updateSetting("autofillEnabled", value)}
        disabled={saving}
      />

      {/* Toggle: auto-submit */}
      <ToggleRow
        label="Auto-submit after fill"
        description="Automatically submit the form after filling credentials"
        checked={autoSubmit}
        onChange={(value) => updateSetting("autoSubmit", value)}
        disabled={saving}
      />

      {/* Toggle: autofill on page load */}
      <ToggleRow
        label="Autofill on page load"
        description="Shows matching items as soon as a page is detected, so you don't need to trigger autofill manually"
        checked={autofillOnPageLoad}
        onChange={(value) => updateSetting("autofillOnPageLoad", value)}
        disabled={saving}
      />

      {saving && (
        <div className="mt-5 flex items-center justify-center gap-2 text-xs font-medium text-gray-400 dark:text-gray-500">
          <Loader2 className="w-3.5 h-3.5 animate-spin" />
          Saving…
        </div>
      )}

      {/* Last connected */}
      {settings?.lastConnectedAt && (
        <p className="mt-4 text-xs text-center text-gray-400 dark:text-gray-600">
          Last connected: {new Date(settings.lastConnectedAt).toLocaleString()}
        </p>
      )}

      {/* Version */}
      <p className="mt-2 text-xs text-center text-gray-300 dark:text-gray-700">
        LumenPass Extension v{extensionVersion}
      </p>

      {toast && (
        <div
          role="status"
          className={`absolute bottom-4 left-1/2 z-20 flex -translate-x-1/2 items-center gap-2 whitespace-nowrap rounded-full px-3.5 py-1.5 text-xs font-medium shadow-lg ${
            toast.type === "success"
              ? "bg-gray-900/90 text-white dark:bg-gray-100 dark:text-gray-900"
              : "bg-red-600 text-white dark:bg-red-500 dark:text-white"
          }`}
        >
          {toast.type === "success" ? (
            <CheckCircle2 className="h-3.5 w-3.5" />
          ) : (
            <AlertCircle className="h-3.5 w-3.5" />
          )}
          {toast.message}
        </div>
      )}
    </div>
  );
}

function ToggleRow({
  label,
  description,
  checked,
  onChange,
  disabled = false,
}: {
  label: string;
  description: string;
  checked: boolean;
  onChange: (v: boolean) => void;
  disabled?: boolean;
}) {
  return (
    <label className={`flex items-start gap-3 py-3 border-b border-gray-100 dark:border-gray-800 last:border-0 ${disabled ? "cursor-not-allowed opacity-70" : "cursor-pointer"}`}>
      <div className="flex-1">
        <p className="text-sm font-medium text-gray-800 dark:text-gray-200">{label}</p>
        <p className="text-xs text-gray-400 dark:text-gray-500 mt-0.5">{description}</p>
      </div>
      {/* Toggle switch */}
      <button
        type="button"
        role="switch"
        aria-checked={checked}
        disabled={disabled}
        onClick={() => onChange(!checked)}
        className={`relative shrink-0 mt-0.5 w-9 h-5 rounded-full transition-colors ${
          checked ? "bg-brand-600" : "bg-gray-200 dark:bg-gray-700"
        }`}
      >
        <span
          className={`absolute top-0.5 left-0.5 w-4 h-4 rounded-full bg-white shadow transition-transform ${
            checked ? "translate-x-4" : "translate-x-0"
          }`}
        />
      </button>
    </label>
  );
}
