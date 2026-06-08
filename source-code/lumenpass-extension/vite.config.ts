import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import { crx } from "@crxjs/vite-plugin";
import path from "path";
import { fileURLToPath } from "url";
import manifest from "./src/manifest.json";
import manifestFirefox from "./src/manifest.firefox.json";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const isFirefox = process.env["BROWSER"] === "firefox";

export default defineConfig({
  plugins: [
    react(),
    crx({ manifest: isFirefox ? (manifestFirefox as any) : (manifest as any) }),
  ],
  resolve: {
    alias: {
      "@": path.resolve(__dirname, "./src"),
    },
  },
  build: {
    outDir: isFirefox ? "dist-firefox" : "dist",
    emptyOutDir: true,
  },
  server: {
    port: 5173,
    hmr: {
      port: 5173,
    },
  },
});
