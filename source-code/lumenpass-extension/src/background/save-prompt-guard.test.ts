import { describe, expect, it } from "vitest";
import { shouldAllowSaveLoginOffers } from "./save-prompt-guard";

/**
 * Save-login prompts are browser-agnostic background decisions. These tests
 * verify the guard used by Chrome, Firefox, Edge/Chromium, and Safari builds
 * before any capture, notification, toast, or prompt UI can be displayed.
 */
describe("shouldAllowSaveLoginOffers", () => {
  it("allows save offers only when the desktop is connected and the vault is unlocked", () => {
    expect(shouldAllowSaveLoginOffers({ connected: true, vaultOpen: true })).toEqual({ allowed: true });
  });

  it("suppresses all save offers when the desktop reports a locked vault", () => {
    expect(shouldAllowSaveLoginOffers({ connected: true, vaultOpen: false })).toEqual({
      allowed: false,
      reason: "vault-locked",
    });
  });

  it("suppresses all save offers when the desktop is disconnected", () => {
    expect(shouldAllowSaveLoginOffers({ connected: false, vaultOpen: false })).toEqual({
      allowed: false,
      reason: "desktop-disconnected",
    });
  });

  it("treats disconnected as suppressing even if stale state claims the vault was open", () => {
    expect(shouldAllowSaveLoginOffers({ connected: false, vaultOpen: true })).toEqual({
      allowed: false,
      reason: "desktop-disconnected",
    });
  });
});
