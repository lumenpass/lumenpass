/**
 * LumenPass Passkey Interceptor – Isolated-World Bootstrap (Safari / Firefox).
 *
 * Safari's Manifest V3 content scripts run only in the isolated world
 * (no `world: "MAIN"` support). An inline `<script textContent=…>` injection
 * is blocked on strict-CSP pages (accounts.google.com, github.com, …).
 *
 * Workaround: inject `content/passkey-page.js` via `<script src=ext-url>`.
 * Scripts loaded from the extension origin bypass the page CSP in all
 * major browsers, and the file ships as a `web_accessible_resource`.
 *
 * In Chrome this file is NOT used: the manifest registers
 * `content/passkey-page.js` directly as a `world: "MAIN"` content script.
 */

const LP = "LUMENPASS_PK";

let pagePatchReady = false;
let pageInjectionAttempts = 0;
const MAX_PAGE_INJECTION_ATTEMPTS = 6;

window.addEventListener("message", (evt: MessageEvent) => {
  if (evt.source !== window || !evt.data?.[LP] || evt.data.type !== "PASSKEY_PATCH_READY") return;
  pagePatchReady = true;
});

type RuntimeLike = { getURL: (path: string) => string };

function extensionRuntime(): RuntimeLike | null {
  const g = globalThis as unknown as {
    browser?: { runtime?: RuntimeLike };
    chrome?: { runtime?: RuntimeLike & { id?: string } };
  };
  if (g.browser?.runtime?.getURL) return g.browser.runtime;
  if (g.chrome?.runtime?.getURL && typeof g.chrome.runtime.id === "string") return g.chrome.runtime;
  return null;
}

function injectPatchIntoPage(): void {
  if (pagePatchReady) return;
  const runtime = extensionRuntime();
  if (!runtime) {
    console.warn("[LumenPass Passkey] no extension runtime available; cannot inject page patch");
    return;
  }

  const script = document.createElement("script");
  script.src = runtime.getURL("content/passkey-page.js");
  script.async = false;
  script.onload = () => script.remove();
  script.onerror = () => {
    console.warn("[LumenPass Passkey] failed to load passkey-page.js from extension URL");
    script.remove();
  };
  (document.documentElement || document.head || document.body).appendChild(script);
}

function ensurePagePatchInjected(): void {
  if (pagePatchReady) return;
  if (pageInjectionAttempts >= MAX_PAGE_INJECTION_ATTEMPTS) return;

  pageInjectionAttempts += 1;
  injectPatchIntoPage();
  if (pagePatchReady) return;

  const retryDelayMs =
    pageInjectionAttempts <= 2 ? 60
      : pageInjectionAttempts <= 4 ? 180
        : 420;

  window.setTimeout(ensurePagePatchInjected, retryDelayMs);
}

ensurePagePatchInjected();
if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", () => {
    ensurePagePatchInjected();
  }, { once: true });
} else {
  window.setTimeout(ensurePagePatchInjected, 0);
}
window.addEventListener("load", () => {
  ensurePagePatchInjected();
}, { once: true });
