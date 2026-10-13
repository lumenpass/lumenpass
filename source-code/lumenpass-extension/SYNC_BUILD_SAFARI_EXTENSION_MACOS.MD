# Sync & Build Safari Extension into macOS Desktop App

This guide describes how to ship the **LumenPass Safari Web Extension**
(developed under `lumenpass-extension/`) inside the **LumenPass macOS Desktop
app** (`apps/desktop/`) as a single bundled product.

The Safari extension lives as a target inside the desktop app's Xcode project
(`apps/desktop/macos/Runner.xcodeproj`). The `lumenpass-extension/` folder
remains the **single source of truth** for the extension's JS/HTML/CSS, and a
small sync step copies the built output into the Xcode target's `Resources/`
folder on every change.

---

## Repository layout

```
lumenpass/
├── lumenpass-extension/                       ← extension source (this folder)
│   ├── src/
│   ├── scripts/
│   │   ├── build-safari.mjs                   ← produces dist-safari/
│   │   └── sync-desktop.mjs                   ← (added below) copies into desktop target
│   └── dist-safari/                           ← build output (git-ignored)
└── apps/desktop/
    └── macos/
        ├── Runner.xcodeproj
        └── SafariExtension/                   ← Xcode Safari Web Extension target
            ├── SafariWebExtensionHandler.swift
            ├── Info.plist
            ├── SafariExtension.entitlements
            └── Resources/                     ← dist-safari/ is mirrored here
```

---

## One-time setup (Xcode)

Done once per machine / per checkout, not on every change.

1. Open `apps/desktop/macos/Runner.xcworkspace` in Xcode.
2. **File → New → Target → Safari Extension → Safari Web Extension**.
   - Language: **Swift**
   - Manifest: **V3**
   - Name: `SafariExtension`
3. Xcode generates `apps/desktop/macos/SafariExtension/` with a starter
   `Resources/` folder. **Delete the contents of `Resources/`** — it will be
   overwritten by the sync step.
4. Confirm the `Runner` target's *Copy Files (PlugIns)* build phase embeds
   `SafariExtension.appex` into `LumenPass.app/Contents/PlugIns/`. Xcode wires
   this automatically when the target is added.
5. Add the same App Group entitlement (`group.com.yourname.lumenpass`) to both
   `Runner` and `SafariExtension` targets so they can share state.
6. Match the Team ID and signing identity on both targets.

After this, `apps/desktop/macos/SafariExtension/Resources/` is the only folder
that needs to be kept in sync with `lumenpass-extension/dist-safari/`.

---

## The update loop

You no longer need `xcrun safari-web-extension-converter`. The converter is only
useful for creating a brand-new standalone Xcode project. Once the Safari target
exists inside the desktop app, you just **build → copy → rebuild the desktop
app**.

Pick one of three options below.

---

### Option A — Manual sync (simplest, good while iterating)

```bash
cd "/Users/trantuan/Works/Tran/LumenPass Workspaces/lumenpass/lumenpass-extension"
npm run build:safari

DEST="/Users/trantuan/Works/Tran/LumenPass Workspaces/lumenpass/apps/desktop/macos/SafariExtension/Resources"
rm -rf "$DEST"
mkdir -p "$DEST"
cp -R dist-safari/. "$DEST/"
```

Then build the desktop app (`flutter build macos` or directly in Xcode). The
`.appex` is rebuilt with the fresh extension code.

---

### Option B — Wire it into npm scripts (recommended)

Add a `sync:desktop` script in `package.json`:

```json
"scripts": {
  "build:safari": "npm run generate:icons && node scripts/build-safari.mjs",
  "sync:desktop": "node scripts/sync-desktop.mjs",
  "build:desktop-safari": "npm run build:safari && npm run sync:desktop"
}
```

Create `scripts/sync-desktop.mjs`:

```js
import { resolve, dirname } from "path";
import { fileURLToPath } from "url";
import { cpSync, rmSync, mkdirSync, existsSync } from "fs";

const __dirname = dirname(fileURLToPath(import.meta.url));
const projectRoot = resolve(__dirname, "..");
const src = resolve(projectRoot, "dist-safari");
const dest = resolve(
  projectRoot,
  "../apps/desktop/macos/SafariExtension/Resources"
);

if (!existsSync(src)) {
  console.error("dist-safari/ not found. Run `npm run build:safari` first.");
  process.exit(1);
}
if (!existsSync(resolve(dest, ".."))) {
  console.error(
    `Safari target missing at ${dest}. Add the Safari Web Extension target in Xcode first.`
  );
  process.exit(1);
}

rmSync(dest, { recursive: true, force: true });
mkdirSync(dest, { recursive: true });
cpSync(src, dest, { recursive: true });

console.log(`✅ Synced dist-safari → ${dest}`);
```

Now the entire update loop is one command:

```bash
npm run build:desktop-safari
```

---

### Option C — Automatic on every Xcode build (zero-touch)

For a fully hands-off workflow, add a *Run Script* build phase to the
`SafariExtension` target in Xcode, **before** *Copy Bundle Resources*:

```bash
set -e
EXT_DIR="${SRCROOT}/../../../lumenpass-extension"
cd "$EXT_DIR"
/usr/local/bin/npm --silent run build:safari
RES="${SRCROOT}/SafariExtension/Resources"
rm -rf "$RES"
mkdir -p "$RES"
cp -R dist-safari/. "$RES/"
```

Build phase configuration:

- **Input Files:** `${SRCROOT}/../../../lumenpass-extension/dist-safari`
- **Output Files:** `${SRCROOT}/SafariExtension/Resources`

Adjust the `npm` path if needed (e.g. `nvm` or `which npm` on CI). With this in
place, every Xcode build of `Runner` automatically rebuilds and re-syncs the
extension.

---

## Daily workflow (TL;DR)

1. Edit code in `lumenpass-extension/src/...`.
2. Run `npm run build:safari` (produces `dist-safari/`).
3. Copy `dist-safari/` → `apps/desktop/macos/SafariExtension/Resources/` using
   one of Options A / B / C above.
4. Build the desktop app — the new extension ships inside
   `LumenPass.app/Contents/PlugIns/SafariExtension.appex`.

---

## Safari MV3 caveats already handled by `build-safari.mjs`

`scripts/build-safari.mjs` already rewrites the manifest with Safari-correct
paths and drops Chrome-only fields. Keep these quirks in mind if you tweak the
manifest:

- Safari ignores `"type": "module"` on the background script. The build emits a
  bundled ES module file and omits `"type"` in the manifest.
- Safari does not honor `world: "MAIN"` in `content_scripts`. The build uses a
  `passkey-inject.ts` bootstrap that injects `passkey-page.js` via a
  `<script src=ext-url>` tag, then exposes `passkey-page.js` via
  `web_accessible_resources`.
- `host_permissions` such as `http://127.0.0.1:19455/*` work in Safari, but the
  user must grant them via **Safari → Settings → Extensions → LumenPass →
  Websites**. Document this in user-facing onboarding.

---

## Versioning and release hygiene

To prevent the desktop app and the extension from drifting:

- Drive the manifest `version` from a single source. Currently
  `scripts/build-safari.mjs` hard-codes `"1.0.0"`. Switch it to read from
  `package.json`:

  ```js
  import { readFileSync } from "fs";
  const pkg = JSON.parse(readFileSync(resolve(projectRoot, "package.json"), "utf8"));
  // ...
  version: pkg.version,
  ```

- Tag releases on the monorepo, not separately per package.
- In CI, always run `npm run build:desktop-safari` **before** `flutter build
  macos` so the `.appex` carries the matching JS bundle.

---

## Cleanup

Once the Xcode target inside `apps/desktop/macos/` is in place and verified, the
standalone `lumenpass-safari/` Xcode project produced by
`npm run convert:safari` becomes redundant. It can be deleted, or kept
temporarily as a reference for `Info.plist` / entitlement values.
