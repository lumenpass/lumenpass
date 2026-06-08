import React from "react";
import { AlertCircle, CheckCircle2, Loader2, RefreshCw } from "lucide-react";

interface Props {
  connected: boolean | null;
  hasToken: boolean;
  onReconnect: () => void;
  onOpenSettings: () => void;
}

export default function ConnectionBanner({ connected, hasToken, onReconnect, onOpenSettings }: Props) {
  if (!hasToken) {
    return (
      <div className="px-4 py-2.5 bg-amber-50 dark:bg-amber-950/30 border-b border-amber-100 dark:border-amber-900/40 flex items-center gap-2.5">
        <AlertCircle className="w-3.5 h-3.5 text-amber-500 shrink-0" />
        <span className="text-xs text-amber-700 dark:text-amber-400 flex-1">
          No token set.{" "}
          <button
            onClick={onOpenSettings}
            className="underline font-medium hover:text-amber-900 dark:hover:text-amber-200"
          >
            Configure now
          </button>
        </span>
      </div>
    );
  }

  if (connected === null) {
    return (
      <div className="px-4 py-2 bg-gray-50 dark:bg-gray-800/50 border-b border-gray-100 dark:border-gray-800 flex items-center gap-2">
        <Loader2 className="w-3.5 h-3.5 text-gray-400 animate-spin" />
        <span className="text-xs text-gray-500 dark:text-gray-400">Connecting…</span>
      </div>
    );
  }

  if (!connected) {
    return (
      <div className="px-4 py-2 bg-red-50 dark:bg-red-950/30 border-b border-red-100 dark:border-red-900/40 flex items-center gap-2.5">
        <div className="w-2 h-2 rounded-full bg-red-400 shrink-0" />
        <span className="text-xs text-red-600 dark:text-red-400 flex-1">Desktop app not running</span>
        <button
          onClick={onReconnect}
          className="flex items-center gap-1 text-xs text-red-500 dark:text-red-400 hover:text-red-700 dark:hover:text-red-200 font-medium"
        >
          <RefreshCw className="w-3 h-3" />
          Retry
        </button>
      </div>
    );
  }

  return (
    <div className="px-4 py-2 bg-emerald-50 dark:bg-emerald-950/20 border-b border-emerald-100 dark:border-emerald-900/30 flex items-center gap-2">
      <CheckCircle2 className="w-3.5 h-3.5 text-emerald-500 shrink-0" />
      <span className="text-xs text-emerald-700 dark:text-emerald-400">Connected to LumenPass Desktop</span>
    </div>
  );
}
