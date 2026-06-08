import React, { useCallback, useEffect, useRef, useState } from "react";
import {
  Lock,
  Eye,
  EyeOff,
  Fingerprint,
  Delete,
  ArrowLeft,
  KeyRound,
} from "lucide-react";
import type { ExtMessage, ExtResponse } from "../../lib/utils";
import type { UnlockOptionsResponse, UnlockResultResponse } from "../../lib/api";

type Mode = "password" | "pin";

interface VaultUnlockViewProps {
  connected: boolean;
  onUnlocked: () => void;
  onReconnect: () => void;
  sendMessage: <T>(msg: ExtMessage) => Promise<ExtResponse<T>>;
}

export default function VaultUnlockView({
  connected,
  onUnlocked,
  onReconnect,
  sendMessage,
}: VaultUnlockViewProps) {
  const [options, setOptions] = useState<UnlockOptionsResponse | null>(null);
  const [optionsError, setOptionsError] = useState<string | null>(null);
  const [mode, setMode] = useState<Mode>("password");
  const [password, setPassword] = useState("");
  const [showPassword, setShowPassword] = useState(false);
  const [pin, setPin] = useState("");
  const [isUnlocking, setIsUnlocking] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [biometricPending, setBiometricPending] = useState(false);
  const passwordInputRef = useRef<HTMLInputElement | null>(null);

  // ── Load unlock options on mount / reconnect ──────────────────────────────
  const loadOptions = useCallback(async () => {
    const res = await sendMessage<UnlockOptionsResponse>({
      type: "GET_UNLOCK_OPTIONS",
    });
    if (res.ok && res.data) {
      setOptions(res.data);
      setOptionsError(null);
      if (res.data.locked === false) {
        onUnlocked();
      }
    } else {
      setOptionsError(res.error ?? "Cannot reach LumenPass Desktop");
    }
  }, [sendMessage, onUnlocked]);

  useEffect(() => {
    if (connected) loadOptions();
  }, [connected, loadOptions]);

  // Autofocus password input when in password mode
  useEffect(() => {
    if (mode === "password") {
      passwordInputRef.current?.focus();
    }
  }, [mode]);

  // ── Handlers ──────────────────────────────────────────────────────────────
  const handlePasswordUnlock = useCallback(async () => {
    if (!password || isUnlocking) return;
    setIsUnlocking(true);
    setError(null);
    const res = await sendMessage<UnlockResultResponse>({
      type: "UNLOCK_WITH_PASSWORD",
      payload: { password },
    });
    setIsUnlocking(false);
    if (res.ok && res.data?.ok) {
      onUnlocked();
    } else {
      setError(
        res.data?.error ?? res.error ?? "Incorrect password. Please try again.",
      );
      setPassword("");
      passwordInputRef.current?.focus();
    }
  }, [password, isUnlocking, sendMessage, onUnlocked]);

  const handleSubmitPin = useCallback(
    async (digits: string) => {
      if (digits.length !== 6 || isUnlocking) return;
      setIsUnlocking(true);
      setError(null);
      const res = await sendMessage<UnlockResultResponse>({
        type: "UNLOCK_WITH_PIN",
        payload: { pin: digits },
      });
      setIsUnlocking(false);
      if (res.ok && res.data?.ok) {
        onUnlocked();
      } else {
        setError(res.data?.error ?? res.error ?? "Incorrect PIN — try again.");
        setPin("");
      }
    },
    [isUnlocking, sendMessage, onUnlocked],
  );

  const handleBiometricUnlock = useCallback(async () => {
    if (biometricPending || isUnlocking) return;
    setBiometricPending(true);
    setError(null);
    const res = await sendMessage<UnlockResultResponse>({
      type: "UNLOCK_WITH_BIOMETRIC",
    });
    setBiometricPending(false);
    if (res.ok && res.data?.ok) {
      onUnlocked();
    } else {
      setError(
        res.data?.error ??
          res.error ??
          "Biometric unlock was cancelled. Try again or use your master password.",
      );
    }
  }, [biometricPending, isUnlocking, sendMessage, onUnlocked]);

  const addPinDigit = (digit: number) => {
    if (pin.length >= 6 || isUnlocking) return;
    const next = `${pin}${digit}`;
    setPin(next);
    setError(null);
    if (next.length === 6) {
      handleSubmitPin(next);
    }
  };

  const removePinDigit = () => {
    if (isUnlocking) return;
    setPin((prev) => prev.slice(0, -1));
    setError(null);
  };

  // ── Loading / disconnected states ─────────────────────────────────────────
  if (!connected) {
    return <LockedStatusCard variant="waiting" onRetry={onReconnect} />;
  }
  if (!options && !optionsError) {
    return <LockedStatusCard variant="loading" />;
  }
  if (optionsError) {
    return (
      <LockedStatusCard
        variant="error"
        message={optionsError}
        onRetry={loadOptions}
      />
    );
  }
  if (options && options.vaultReady === false) {
    return <LockedStatusCard variant="no-vault" />;
  }

  const hasPin = options?.hasPin === true;
  const hasBiometric =
    options?.hasBiometric === true && options?.biometricAvailable === true;
  const vaultName = options?.vaultName ?? "Vault";

  return (
    <div className="flex h-full flex-col items-center justify-center gap-5 bg-[#f3f7ff] px-6 py-6 dark:bg-gray-950">
      <div className="w-full max-w-[380px] rounded-2xl border border-[#dbe7ff] bg-white p-6 shadow-sm dark:border-gray-800 dark:bg-gray-900">
        {/* Header */}
        <div className="mb-5 flex flex-col items-center gap-3 text-center">
          <div
            className="flex h-14 w-14 items-center justify-center rounded-2xl shadow-[0_6px_24px_rgba(68,76,231,0.3)]"
            style={{
              background: "linear-gradient(135deg, #6370f5 0%, #3d4cdc 100%)",
            }}
          >
            <Lock className="h-6 w-6 text-white" strokeWidth={2} />
          </div>
          <div>
            <h2 className="text-[16px] font-bold text-gray-900 dark:text-gray-100">
              Unlock {vaultName}
            </h2>
            <p className="mt-1 text-[12px] text-gray-500 dark:text-gray-400">
              {mode === "password"
                ? "Enter your master password to continue."
                : "Enter your 6-digit PIN."}
            </p>
          </div>
        </div>

        {mode === "password" ? (
          <PasswordUnlockForm
            password={password}
            showPassword={showPassword}
            isUnlocking={isUnlocking}
            error={error}
            inputRef={passwordInputRef}
            onChange={(value) => {
              setPassword(value);
              setError(null);
            }}
            onToggleShow={() => setShowPassword((prev) => !prev)}
            onSubmit={handlePasswordUnlock}
          />
        ) : (
          <PinPad
            pin={pin}
            isUnlocking={isUnlocking}
            error={error}
            onAdd={addPinDigit}
            onRemove={removePinDigit}
            onBack={() => {
              setMode("password");
              setPin("");
              setError(null);
            }}
          />
        )}

        {/* Quick-unlock buttons row */}
        {mode === "password" && (hasPin || hasBiometric) && (
          <div className="mt-4 flex items-center justify-center gap-3">
            {hasPin && (
              <button
                onClick={() => {
                  setMode("pin");
                  setError(null);
                }}
                className="inline-flex items-center gap-1.5 rounded-lg border border-gray-200 bg-gray-50 px-3 py-2 text-[12px] font-medium text-gray-700 transition-colors hover:bg-gray-100 dark:border-gray-700 dark:bg-gray-800 dark:text-gray-200 dark:hover:bg-gray-700"
                title="Unlock with PIN"
              >
                <KeyRound className="h-3.5 w-3.5" />
                PIN code
              </button>
            )}
            {hasBiometric && (
              <button
                onClick={handleBiometricUnlock}
                disabled={biometricPending}
                className="inline-flex items-center gap-1.5 rounded-lg border border-brand-200 bg-brand-50 px-3 py-2 text-[12px] font-medium text-brand-700 transition-colors hover:bg-brand-100 disabled:opacity-60 dark:border-brand-800 dark:bg-brand-900/30 dark:text-brand-300 dark:hover:bg-brand-900/50"
                title="Unlock with biometrics"
              >
                <Fingerprint className="h-3.5 w-3.5" />
                {biometricPending ? "Waiting for desktop…" : "Biometrics"}
              </button>
            )}
          </div>
        )}
      </div>

      <p className="text-center text-[11px] leading-relaxed text-gray-400 dark:text-gray-500">
        Biometric prompts appear on the desktop app. Make sure LumenPass
        Desktop is visible.
      </p>
    </div>
  );
}

// ─── Sub-components ──────────────────────────────────────────────────────────

interface PasswordUnlockFormProps {
  password: string;
  showPassword: boolean;
  isUnlocking: boolean;
  error: string | null;
  inputRef: React.MutableRefObject<HTMLInputElement | null>;
  onChange: (value: string) => void;
  onToggleShow: () => void;
  onSubmit: () => void;
}

function PasswordUnlockForm({
  password,
  showPassword,
  isUnlocking,
  error,
  inputRef,
  onChange,
  onToggleShow,
  onSubmit,
}: PasswordUnlockFormProps) {
  return (
    <form
      onSubmit={(event) => {
        event.preventDefault();
        onSubmit();
      }}
      className="flex flex-col gap-3"
    >
      <label className="block text-[11px] font-semibold uppercase tracking-wide text-gray-400 dark:text-gray-500">
        Master password
      </label>
      <div className="flex items-center gap-2 rounded-xl border border-gray-200 bg-gray-50 px-3 py-2.5 focus-within:border-brand-300 focus-within:bg-white dark:border-gray-700 dark:bg-gray-800/80 dark:focus-within:border-brand-500 dark:focus-within:bg-gray-900">
        <Lock className="h-4 w-4 text-gray-400 dark:text-gray-500" />
        <input
          ref={inputRef}
          type={showPassword ? "text" : "password"}
          value={password}
          onChange={(event) => onChange(event.target.value)}
          placeholder="Your master password"
          autoComplete="current-password"
          disabled={isUnlocking}
          className="min-w-0 flex-1 bg-transparent text-[14px] text-gray-900 outline-none placeholder:text-gray-400 disabled:opacity-60 dark:text-gray-100 dark:placeholder:text-gray-500"
        />
        <button
          type="button"
          onClick={onToggleShow}
          className="text-gray-400 transition-colors hover:text-gray-600 dark:text-gray-500 dark:hover:text-gray-300"
          tabIndex={-1}
          aria-label={showPassword ? "Hide password" : "Show password"}
        >
          {showPassword ? (
            <EyeOff className="h-4 w-4" />
          ) : (
            <Eye className="h-4 w-4" />
          )}
        </button>
      </div>
      {error && (
        <div className="rounded-lg bg-rose-50 px-3 py-2 text-[12px] font-medium text-rose-700 dark:bg-rose-950/30 dark:text-rose-300">
          {error}
        </div>
      )}
      <button
        type="submit"
        disabled={!password || isUnlocking}
        className="inline-flex h-11 items-center justify-center gap-2 rounded-xl bg-brand-600 text-[14px] font-semibold text-white shadow-sm transition-colors hover:bg-brand-700 disabled:cursor-not-allowed disabled:opacity-60"
        style={{
          background: isUnlocking
            ? "#6370f5"
            : "linear-gradient(135deg, #6370f5 0%, #3d4cdc 100%)",
        }}
      >
        {isUnlocking ? (
          <>
            <Spinner />
            Unlocking…
          </>
        ) : (
          "Unlock"
        )}
      </button>
    </form>
  );
}

interface PinPadProps {
  pin: string;
  isUnlocking: boolean;
  error: string | null;
  onAdd: (digit: number) => void;
  onRemove: () => void;
  onBack: () => void;
}

function PinPad({
  pin,
  isUnlocking,
  error,
  onAdd,
  onRemove,
  onBack,
}: PinPadProps) {
  const digits = [1, 2, 3, 4, 5, 6, 7, 8, 9];

  return (
    <div className="flex flex-col items-center gap-4">
      {/* Back link */}
      <button
        onClick={onBack}
        className="self-start inline-flex items-center gap-1 text-[12px] font-medium text-gray-500 transition-colors hover:text-gray-800 dark:text-gray-400 dark:hover:text-gray-200"
        disabled={isUnlocking}
      >
        <ArrowLeft className="h-3.5 w-3.5" />
        Use master password
      </button>

      {/* 6-dot indicator */}
      <div className="flex items-center gap-2.5">
        {Array.from({ length: 6 }).map((_, index) => {
          const filled = index < pin.length;
          return (
            <span
              key={index}
              className={`h-3 w-3 rounded-full border transition-all ${
                filled
                  ? "border-brand-500 bg-brand-500 scale-110"
                  : "border-gray-300 bg-transparent dark:border-gray-600"
              }`}
            />
          );
        })}
      </div>

      {error && (
        <div className="rounded-lg bg-rose-50 px-3 py-2 text-[12px] font-medium text-rose-700 dark:bg-rose-950/30 dark:text-rose-300">
          {error}
        </div>
      )}

      {/* Numeric pad */}
      <div className="grid grid-cols-3 gap-2.5">
        {digits.map((digit) => (
          <PinKey
            key={digit}
            onClick={() => onAdd(digit)}
            disabled={isUnlocking}
          >
            {digit}
          </PinKey>
        ))}
        <div />
        <PinKey onClick={() => onAdd(0)} disabled={isUnlocking}>
          0
        </PinKey>
        <PinKey onClick={onRemove} disabled={isUnlocking || pin.length === 0}>
          <Delete className="h-4 w-4" />
        </PinKey>
      </div>
      {isUnlocking && (
        <div className="flex items-center gap-2 text-[12px] text-gray-500 dark:text-gray-400">
          <Spinner />
          Unlocking…
        </div>
      )}
    </div>
  );
}

function PinKey({
  children,
  onClick,
  disabled,
}: {
  children: React.ReactNode;
  onClick: () => void;
  disabled?: boolean;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      disabled={disabled}
      className="inline-flex h-12 w-14 items-center justify-center rounded-xl border border-gray-200 bg-white text-[18px] font-semibold text-gray-800 transition-colors hover:bg-gray-50 disabled:cursor-not-allowed disabled:opacity-40 dark:border-gray-700 dark:bg-gray-900 dark:text-gray-100 dark:hover:bg-gray-800"
    >
      {children}
    </button>
  );
}

function Spinner() {
  return (
    <span
      className="inline-block h-3.5 w-3.5 animate-spin rounded-full border-2 border-white/40 border-t-white"
      aria-hidden
    />
  );
}

// ─── Shared status card (connection / no-vault / loading) ────────────────────

interface LockedStatusCardProps {
  variant: "waiting" | "loading" | "error" | "no-vault";
  message?: string;
  onRetry?: () => void;
}

function LockedStatusCard({ variant, message, onRetry }: LockedStatusCardProps) {
  const copy = (() => {
    switch (variant) {
      case "waiting":
        return {
          title: "Desktop Not Running",
          subtitle:
            "Open LumenPass Desktop to connect and unlock your vault from the extension.",
          indicatorLabel: "Waiting for desktop…",
          indicatorColor: "bg-amber-400",
        };
      case "loading":
        return {
          title: "Checking vault…",
          subtitle:
            "Loading your unlock options from LumenPass Desktop.",
          indicatorLabel: "Please wait",
          indicatorColor: "bg-brand-400",
        };
      case "error":
        return {
          title: "Connection problem",
          subtitle:
            message ??
            "Could not reach LumenPass Desktop. Make sure the app is running.",
          indicatorLabel: "Connection error",
          indicatorColor: "bg-rose-500",
        };
      case "no-vault":
      default:
        return {
          title: "No vault selected",
          subtitle:
            "Open a vault in LumenPass Desktop. After that, you can unlock it inline from this popup.",
          indicatorLabel: "Waiting for vault",
          indicatorColor: "bg-amber-400",
        };
    }
  })();

  return (
    <div className="flex h-full flex-col items-center justify-center gap-6 bg-[#f3f7ff] px-10 text-center dark:bg-gray-950">
      <div
        className="flex h-[72px] w-[72px] items-center justify-center rounded-[22px] shadow-[0_8px_32px_rgba(68,76,231,0.3)]"
        style={{ background: "linear-gradient(135deg, #6370f5 0%, #3d4cdc 100%)" }}
      >
        <Lock className="h-9 w-9 text-white" strokeWidth={2} />
      </div>
      <div className="space-y-2.5">
        <h2 className="text-[18px] font-bold text-gray-900 dark:text-gray-100">
          {copy.title}
        </h2>
        <p className="mx-auto max-w-[280px] text-[13px] leading-relaxed text-gray-500 dark:text-gray-400">
          {copy.subtitle}
        </p>
      </div>
      <div className="flex items-center gap-2 rounded-full border border-gray-100 bg-white px-3.5 py-2 shadow-sm dark:border-gray-700 dark:bg-gray-800">
        <span
          className={`h-1.5 w-1.5 rounded-full ${copy.indicatorColor} animate-pulse`}
        />
        <span className="text-[11px] font-medium tracking-wide text-gray-400 dark:text-gray-500">
          {copy.indicatorLabel}
        </span>
      </div>
      {variant !== "loading" && onRetry && (
        <button
          onClick={onRetry}
          className="rounded-lg border border-gray-200 bg-white px-4 py-2 text-[12px] font-semibold text-gray-700 transition-colors hover:bg-gray-50 dark:border-gray-700 dark:bg-gray-900 dark:text-gray-200 dark:hover:bg-gray-800"
        >
          Try again
        </button>
      )}
    </div>
  );
}
