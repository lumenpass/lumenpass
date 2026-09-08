/** Extension version helper for the popup UI.
 *
 *  `version` is read at runtime from the WebExtension manifest, so it always
 *  matches the value in `src/manifest.json` (and the mirrored
 *  `src/manifest.firefox.json` / Safari build).
 */

import browser from "webextension-polyfill";

export function getExtensionVersion(): string {
  try {
    const manifest = browser.runtime.getManifest() as { version?: string };
    return manifest.version ?? "0.0.0";
  } catch {
    return "0.0.0";
  }
}

/** Human-readable label used in the Settings footer and the detail panel:
 *  e.g. "Version 1.0.7". */
export function formatVersionLabel(): string {
  return `Version ${getExtensionVersion()}`;
}