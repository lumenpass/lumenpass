/**
 * Safari Extension build script.
 * Produces dist-safari/ – a standard WebExtension directory consumable by
 * `xcrun safari-web-extension-converter`.
 *
 * Run: node scripts/build-safari.mjs
 * (or via: npm run build:safari)
 */

import { build } from "vite";
import react from "@vitejs/plugin-react";
import { resolve, dirname } from "path";
import { fileURLToPath } from "url";
import {
  copyFileSync,
  mkdirSync,
  writeFileSync,
  readdirSync,
  readFileSync,
  rmSync,
} from "fs";

const __dirname = dirname(fileURLToPath(import.meta.url));
const projectRoot = resolve(__dirname, "..");
const outDir = resolve(projectRoot, "dist-safari");
const alias = { "@": resolve(projectRoot, "src") };
const pkg = JSON.parse(
  readFileSync(resolve(projectRoot, "package.json"), "utf8")
);

console.log("🔨 Building LumenPass Safari Extension…\n");

// ── 1. Popup (React SPA) ──────────────────────────────────────────────────────
// root = src/popup so index.html lands directly at dist-safari/popup/index.html.
// postcss-load-config traverses upward and finds postcss.config.js at project root.
console.log("📦 [1/4] Building popup…");
await build({
  configFile: false,
  root: resolve(projectRoot, "src/popup"),
  base: "./",
  plugins: [react()],
  resolve: { alias },
  build: {
    outDir: resolve(outDir, "popup"),
    emptyOutDir: true,
    rollupOptions: {
      output: {
        entryFileNames: "assets/[name].js",
        chunkFileNames: "assets/[name]-[hash].js",
        assetFileNames: "assets/[name][extname]",
      },
    },
  },
});
console.log("  ✓ Popup\n");

// ── 2. Background service worker (ES module) ──────────────────────────────────
console.log("📦 [2/4] Building background service worker…");
await build({
  configFile: false,
  root: projectRoot,
  publicDir: false,
  resolve: { alias },
  build: {
    outDir: resolve(outDir, "background"),
    emptyOutDir: true,
    lib: {
      entry: resolve(projectRoot, "src/background/service-worker.ts"),
      formats: ["es"],
      fileName: () => "service-worker.js",
    },
    rollupOptions: {
      output: { inlineDynamicImports: true },
    },
  },
});
console.log("  ✓ service-worker.js\n");

// ── 3. Content scripts (IIFE – works in both MAIN world and isolated world) ───
console.log("📦 [3/4] Building content scripts…");
rmSync(resolve(outDir, "content"), { recursive: true, force: true });
mkdirSync(resolve(outDir, "content"), { recursive: true });

const contentEntries = [
  // Isolated-world bootstrap: injects passkey-page.js into MAIN world via
  // <script src=ext-url> (bypasses strict page CSP).
  ["passkey-inject", resolve(projectRoot, "src/content/passkey-inject.ts")],
  // MAIN-world payload – loaded as a web_accessible_resource by passkey-inject.
  ["passkey-page", resolve(projectRoot, "src/content/passkey-page.ts")],
  // content-script runs in isolated world – bundles webextension-polyfill
  ["content-script", resolve(projectRoot, "src/content/content-script.ts")],
];

for (const [name, entry] of contentEntries) {
  await build({
    configFile: false,
    root: projectRoot,
    publicDir: false,
    resolve: { alias },
    build: {
      outDir: resolve(outDir, "content"),
      emptyOutDir: false,
      lib: {
        entry,
        name: "LumenPass",
        formats: ["iife"],
        fileName: () => `${name}.js`,
      },
      rollupOptions: {
        output: { inlineDynamicImports: true },
      },
    },
  });
  console.log(`  ✓ content/${name}.js`);
}
console.log();

// ── 4. Copy icons ─────────────────────────────────────────────────────────────
console.log("🖼  [4/4] Copying icons…");
const iconsOut = resolve(outDir, "icons");
mkdirSync(iconsOut, { recursive: true });
for (const file of readdirSync(resolve(projectRoot, "public/icons"))) {
  copyFileSync(resolve(projectRoot, "public/icons", file), resolve(iconsOut, file));
}
console.log("  ✓ Icons\n");

// ── 5. Write manifest.json with corrected paths ───────────────────────────────
const manifest = {
  manifest_version: 3,
  name: "LumenPass",
  version: pkg.version,
  description:
    "Autofill passwords from LumenPass Desktop – the secure, privacy-first password manager.",
  icons: {
    "16": "icons/icon16.png",
    "32": "icons/icon32.png",
    "48": "icons/icon48.png",
    "128": "icons/icon128.png",
  },
  action: {
    default_popup: "popup/index.html",
    default_icon: {
      "16": "icons/icon16.png",
      "32": "icons/icon32.png",
      "48": "icons/icon48.png",
      "128": "icons/icon128.png",
    },
    default_title: "LumenPass",
  },
  background: {
    service_worker: "background/service-worker.js",
  },
  content_scripts: [
    {
      matches: ["http://*/*", "https://*/*"],
      js: ["content/passkey-inject.js"],
      run_at: "document_start",
      all_frames: true,
    },
    {
      matches: ["http://*/*", "https://*/*"],
      js: ["content/content-script.js"],
      run_at: "document_end",
      all_frames: true,
    },
  ],
  permissions: ["storage", "activeTab", "scripting", "alarms", "tabs", "contextMenus"],
  host_permissions: ["http://*/*", "https://*/*", "http://127.0.0.1:19455/*"],
  web_accessible_resources: [
    {
      resources: ["icons/*", "content/passkey-page.js"],
      matches: ["http://*/*", "https://*/*"],
    },
  ],
};

writeFileSync(resolve(outDir, "manifest.json"), JSON.stringify(manifest, null, 2));
console.log("📝 manifest.json written\n");

console.log("✅ Safari extension built → dist-safari/");
console.log(
  "\nNext: npm run convert:safari   (generates the Xcode project in lumenpass-safari/)\n"
);
