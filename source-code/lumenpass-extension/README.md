# LumenPass Browser Extension

A production-ready Manifest V3 browser extension for Chrome and Firefox that connects to the **LumenPass Desktop** app (Windows) for password autofill — just like 1Password 8.

## Tech Stack

- **TypeScript** + **React 18** + **TailwindCSS** (popup UI)
- **Vite** + **@crxjs/vite-plugin** (MV3 bundling)
- **webextension-polyfill** (Chrome/Firefox compatibility)
- **sharp** (icon generation)

---

## Quick Start

### 1. Install dependencies

```bash
npm install
```

### 2. Generate icons

```bash
npm run generate:icons
```

This writes `public/icons/icon{16,32,48,128}.png` + `icon32-grey.png`.

### 3. Development

```bash
npm run dev
```

Load `dist/` as an unpacked extension in Chrome (see below).

### 4. Production build

```bash
# Chrome / Edge
npm run build

# Firefox
npm run build:firefox

# Edge package (.zip for Edge Add-ons submission)
npm run build:edge
```

Output folders:
- **Chrome:** `dist/`
- **Edge:** `dist/` + `lumenpass-edge-extension-v<version>.zip`
- **Firefox:** `dist-firefox/`

---

## Installing in Chrome

1. Go to `chrome://extensions`
2. Enable **Developer mode** (top-right toggle)
3. Click **Load unpacked** → select the `dist/` folder
4. The LumenPass icon appears in your toolbar

## Installing in Edge

1. Go to `edge://extensions`
2. Enable **Developer mode**
3. Click **Load unpacked** → select the `dist/` folder
4. The LumenPass icon appears in your toolbar

## Publishing to Edge Add-ons

1. Run `npm run build:edge`
2. Upload `lumenpass-edge-extension-v<version>.zip` to the Microsoft Edge Add-ons dashboard
3. Reuse the same screenshots/copy as Chrome, but replace any "Chrome extension" wording in the store listing
4. In review notes, mention that the extension connects only to the local desktop service at `http://127.0.0.1:19455`

## Installing in Firefox

1. Go to `about:debugging#/runtime/this-firefox`
2. Click **Load Temporary Add-on…**
3. Select `dist-firefox/manifest.json`

For permanent install, sign and distribute via [addons.mozilla.org](https://addons.mozilla.org).

---

## Connecting to LumenPass Desktop

1. Open **LumenPass Desktop** on Windows
2. Go to **Settings → Browser Extension**
3. Copy the **Secret Token**
4. Click the LumenPass extension icon in your browser
5. Click the ⚙️ gear icon → paste your token → **Save & Connect**

A green "Connected to LumenPass Desktop" banner confirms the connection.

---

## How it works

```
Browser Extension
  │
  ├── Popup (React UI)          ← search, fill, settings
  ├── Content Script            ← injects autofill icon on password fields
  └── Background Service Worker ← proxies all API calls to desktop app
          │
          └── HTTP → http://127.0.0.1:19455  (LumenPass Desktop local server)
```

### Desktop API endpoints used

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/ping` | Health check and vault state (`vaultOpen`) |
| `POST` | `/auth` | Authenticate with secret token |
| `GET` | `/search?query=&url=` | Search entries |
| `GET` | `/entry/:id` | Get full entry (with password) |

### Vault state detection for save-login offers

The background service worker owns vault-state decisions through `ConnectionMonitor`. It polls `GET /ping` on startup, install, alarms, tab activation, and window focus; the desktop response is normalized to `{ connected, vaultOpen }`.

Save-login and social-login offers are guarded by `shouldAllowSaveLoginOffers` before capture storage, prompt preparation, prompt delivery, and retry delivery. A save offer is displayed only when `connected === true` and `vaultOpen === true`. If the desktop is disconnected or the vault is locked, pending captures are silently cleared and no content-script prompt, toast, notification, or related save UI is shown.

---

## Features

- **Smart form detection** — detects login forms and injects a floating LumenPass icon next to password fields
- **Instant search** — debounced search with keyboard navigation (↑↓ Enter)
- **One-click autofill** — fills username + password (+ TOTP if available)
- **Dark/light mode** — follows system preference
- **Connection status** — live indicator with reconnect button
- **Firefox + Chrome + Edge** — cross-browser via webextension-polyfill

---

## Project Structure

```
src/
├── background/
│   └── service-worker.ts     Service worker: routes messages, health checks
├── content/
│   └── content-script.ts     Form detection, autofill icon, inline popup
├── lib/
│   ├── api.ts                Desktop API client
│   ├── storage.ts            Extension storage helpers
│   └── utils.ts              Shared utilities, types, debounce
├── popup/
│   ├── App.tsx               Root component (router between views)
│   ├── index.html            Popup HTML entry point
│   ├── popup.tsx             React entry point
│   ├── popup.css             Tailwind base styles
│   └── views/
│       ├── SearchView.tsx    Main search + fill UI
│       └── SettingsView.tsx  Token + preferences
├── components/
│   ├── ConnectionBanner.tsx  Status bar component
│   └── EntryCard.tsx         Single login entry row
└── manifest.json             Chrome MV3 manifest
    manifest.firefox.json     Firefox-specific manifest
scripts/
└── generate-icons.mjs        PNG icon generator (uses sharp)
public/
└── icons/                    Generated PNG icons (gitignored until built)
```

---

## Security Notes

- The secret token is stored in `browser.storage.local`
- All traffic is local-only (`127.0.0.1:19455`) — nothing leaves your machine
- Passwords are fetched on-demand (not cached) and never written to storage
