import type { VaultState } from "./connection-monitor";

export type SavePromptSuppressionReason = "desktop-disconnected" | "vault-locked";

export interface SavePromptGuardResult {
  allowed: boolean;
  reason?: SavePromptSuppressionReason;
}

export function shouldAllowSaveLoginOffers(state: VaultState): SavePromptGuardResult {
  if (!state.connected) {
    return { allowed: false, reason: "desktop-disconnected" };
  }

  if (!state.vaultOpen) {
    return { allowed: false, reason: "vault-locked" };
  }

  return { allowed: true };
}
