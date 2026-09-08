/**
 * Mirrors the freshly-built Safari extension (dist-safari/) into the
 * macOS desktop app's Safari Web Extension target Resources folder.
 *
 *   lumenpass-extension/dist-safari/
 *     ──>
 *   lumenpass/apps/desktop/macos/SafariExtension/Resources/
 *
 * Run via: npm run sync:desktop
 * Or as part of the full pipeline: npm run build:desktop-safari
 */

import { resolve, dirname } from "path";
import { fileURLToPath } from "url";
import { cpSync, rmSync, mkdirSync, existsSync, writeFileSync } from "fs";

const __dirname = dirname(fileURLToPath(import.meta.url));
const projectRoot = resolve(__dirname, "..");
const src = resolve(projectRoot, "dist-safari");
const desktopMacos = resolve(projectRoot, "../apps/desktop/macos");
const targetDir = resolve(desktopMacos, "SafariExtension");
const dest = resolve(targetDir, "Resources");

if (!existsSync(src)) {
  console.error(
    "❌ dist-safari/ not found.\n   Run `npm run build:safari` first (or `npm run build:desktop-safari`)."
  );
  process.exit(1);
}

if (!existsSync(targetDir)) {
  console.error(
    `❌ Safari target directory missing at:\n   ${targetDir}\n` +
      "   Make sure the SafariExtension folder exists in apps/desktop/macos/."
  );
  process.exit(1);
}

rmSync(dest, { recursive: true, force: true });
mkdirSync(dest, { recursive: true });
cpSync(src, dest, { recursive: true });

writeFileSync(
  resolve(dest, ".keep"),
  "This folder is populated by `npm run sync:desktop` from lumenpass-extension/dist-safari/.\nDo not commit the synced files. They are produced from lumenpass-extension/.\n"
);

console.log(`✅ Synced dist-safari → ${dest}`);
