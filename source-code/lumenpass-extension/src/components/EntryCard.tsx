import React, { useState } from "react";
import { UserRound, KeyRound, Check, LogIn } from "lucide-react";
import { seedColour, initials, copyToClipboard } from "../lib/utils";
import type { EntryItem } from "../lib/api";

interface Props {
  entry: EntryItem;
  isSelected: boolean;
  onFill: (entry: EntryItem) => void;
  onCopyUsername: (username: string) => void;
  onCopyPassword: (id: string) => void;
}

export default function EntryCard({ entry, isSelected, onFill, onCopyUsername, onCopyPassword }: Props) {
  const [copiedUser, setCopiedUser] = useState(false);
  const [copiedPass, setCopiedPass] = useState(false);
  const [showFallbackIcon, setShowFallbackIcon] = useState(!entry.favicon);

  const colour = seedColour(entry.title);
  const abbr = initials(entry.title);

  const handleCopyUser = async (e: React.MouseEvent) => {
    e.stopPropagation();
    const ok = await copyToClipboard(entry.username);
    if (ok) {
      setCopiedUser(true);
      setTimeout(() => setCopiedUser(false), 1500);
      onCopyUsername(entry.username);
    }
  };

  const handleCopyPass = async (e: React.MouseEvent) => {
    e.stopPropagation();
    if (entry.password) {
      const ok = await copyToClipboard(entry.password);
      if (ok) {
        setCopiedPass(true);
        setTimeout(() => setCopiedPass(false), 1500);
      }
    } else {
      onCopyPassword(entry.id);
    }
  };

  return (
    <div
      className={`group flex items-center gap-3 px-4 py-3 cursor-pointer transition-colors border-b border-gray-100 dark:border-gray-800/60 last:border-0 ${
        isSelected
          ? "bg-brand-50 dark:bg-brand-900/20"
          : "hover:bg-gray-50 dark:hover:bg-gray-800/40"
      }`}
      onClick={() => onFill(entry)}
      role="button"
      tabIndex={0}
      onKeyDown={(e) => e.key === "Enter" && onFill(entry)}
    >
      {/* Favicon / avatar */}
      <div className="shrink-0">
        {!showFallbackIcon && entry.favicon ? (
          <img
            src={entry.favicon}
            alt=""
            className="w-8 h-8 rounded-lg object-contain bg-gray-100 dark:bg-gray-800"
            onError={() => {
              setShowFallbackIcon(true);
            }}
          />
        ) : (
          <div
            className="w-8 h-8 rounded-lg flex items-center justify-center text-white text-xs font-bold"
            style={{ backgroundColor: colour }}
          >
            {abbr}
          </div>
        )}
      </div>

      {/* Info */}
      <div className="flex-1 min-w-0">
        <p className="text-sm font-medium text-gray-900 dark:text-gray-100 truncate">{entry.title}</p>
        <p className="text-xs text-gray-500 dark:text-gray-400 truncate">{entry.username}</p>
      </div>

      {/* Actions (show on hover or selected) */}
      <div className={`flex items-center gap-1 transition-opacity ${isSelected ? "opacity-100" : "opacity-0 group-hover:opacity-100"}`}>
        <button
          onClick={handleCopyUser}
          title="Copy username"
          className="p-1.5 rounded-md text-gray-400 hover:text-gray-700 dark:hover:text-gray-200 hover:bg-gray-100 dark:hover:bg-gray-700 transition-colors"
        >
          {copiedUser ? <Check className="w-3.5 h-3.5 text-emerald-500" /> : <UserRound className="w-3.5 h-3.5" />}
        </button>
        <button
          onClick={handleCopyPass}
          title="Copy password"
          className="p-1.5 rounded-md text-gray-400 hover:text-gray-700 dark:hover:text-gray-200 hover:bg-gray-100 dark:hover:bg-gray-700 transition-colors"
        >
          {copiedPass ? <Check className="w-3.5 h-3.5 text-emerald-500" /> : <KeyRound className="w-3.5 h-3.5" />}
        </button>
        <button
          onClick={(e) => { e.stopPropagation(); onFill(entry); }}
          title="Autofill"
          className="flex items-center gap-1 px-2.5 py-1.5 rounded-md bg-brand-600 hover:bg-brand-700 text-white text-xs font-medium transition-colors"
        >
          <LogIn className="w-3.5 h-3.5" />
          Fill
        </button>
      </div>
    </div>
  );
}
