/**
 * Generates the shared LumenPass extension icons at 16, 32, 48, and 128 px.
 * Run: node scripts/generate-icons.mjs
 * Requires: sharp (npm i -D sharp)
 */

import sharp from "sharp";
import { mkdirSync } from "fs";
import { fileURLToPath } from "url";
import { dirname, join } from "path";

const __dirname = dirname(fileURLToPath(import.meta.url));
const iconsDir = join(__dirname, "../public/icons");
mkdirSync(iconsDir, { recursive: true });

const SIZES = [16, 32, 48, 128];

const COLORS = {
  outerStart: "#3B3E44",
  outerEnd: "#2D3035",
  ring: "#AFAFAF",
  red: "#CE2C26",
  key: "#D8D8D8",
};

const GREY_COLORS = {
  outerStart: "#45484F",
  outerEnd: "#36383D",
  ring: "#8A8C90",
  red: "#777B80",
  key: "#B8B9BC",
};

function makeSvg(size, muted = false) {
  const colors = muted ? GREY_COLORS : COLORS;
  const radius = Math.round(size * 0.21);
  const center = size / 2;
  const ringOuter = size * 0.33;
  const ringInner = size * 0.27;
  const keyHeadY = size * 0.405;
  const keyHeadRadius = size * 0.095;
  const keyStemX = center - size * 0.028;
  const keyStemY = size * 0.465;
  const keyStemWidth = size * 0.056;
  const keyStemHeight = size * 0.215;
  const toothX = center + size * 0.028;
  const toothWidth = size * 0.064;
  const toothHeight = size * 0.035;
  const gradientId = `outer-${size}-${muted ? "muted" : "active"}`;

  return `<svg xmlns="http://www.w3.org/2000/svg" width="${size}" height="${size}" viewBox="0 0 ${size} ${size}">
  <defs>
    <linearGradient id="${gradientId}" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="${colors.outerStart}"/>
      <stop offset="1" stop-color="${colors.outerEnd}"/>
    </linearGradient>
  </defs>
  <rect width="${size}" height="${size}" rx="${radius}" fill="url(#${gradientId})"/>
  <circle cx="${center}" cy="${center}" r="${ringOuter}" fill="${colors.ring}"/>
  <circle cx="${center}" cy="${center}" r="${ringInner}" fill="${colors.red}"/>
  <rect x="${keyStemX}" y="${keyStemY}" width="${keyStemWidth}" height="${keyStemHeight}" rx="${keyStemWidth / 2}" fill="${colors.key}"/>
  <rect x="${toothX}" y="${size * 0.55}" width="${toothWidth}" height="${toothHeight}" rx="${toothHeight / 2}" fill="${colors.key}"/>
  <rect x="${toothX}" y="${size * 0.625}" width="${toothWidth}" height="${toothHeight}" rx="${toothHeight / 2}" fill="${colors.key}"/>
  <circle cx="${center}" cy="${keyHeadY}" r="${keyHeadRadius}" fill="${colors.key}"/>
  <circle cx="${center}" cy="${keyHeadY}" r="${size * 0.040}" fill="${colors.red}"/>
</svg>`;
}

async function writeIcon(size, muted = false) {
  const svg = makeSvg(size, muted);
  const outputName = muted ? `icon${size}-grey.png` : `icon${size}.png`;
  await sharp(Buffer.from(svg, "utf-8"))
    .resize(size, size)
    .png()
    .toFile(join(iconsDir, outputName));
  console.log(`✓ ${outputName}`);
}

async function generate() {
  for (const size of SIZES) {
    await writeIcon(size);
  }
  await writeIcon(32, true);
  console.log("\nAll icons written to public/icons/");
}

generate().catch((err) => {
  console.error("Icon generation failed:", err.message);
  process.exit(1);
});
