/**
 * Generates LumenPass PNG icons from an inline SVG at 16, 32, 48, 128 px.
 * Run: node scripts/generate-icons.mjs
 * Requires: sharp  (npm i -D sharp)
 */

import sharp from "sharp";
import { writeFileSync, mkdirSync } from "fs";
import { fileURLToPath } from "url";
import { dirname, join } from "path";

const __dirname = dirname(fileURLToPath(import.meta.url));
const iconsDir = join(__dirname, "../public/icons");
mkdirSync(iconsDir, { recursive: true });

const SIZES = [16, 32, 48, 128];

function makeSvg(size) {
  const r = Math.round(size * 0.14); // corner radius
  const iconColor = "#444ce7";

  return `<svg xmlns="http://www.w3.org/2000/svg" width="${size}" height="${size}" viewBox="0 0 ${size} ${size}">
  <rect width="${size}" height="${size}" rx="${r}" fill="${iconColor}"/>
  <g transform="translate(${size * 0.21} ${size * 0.2}) scale(${size / 24 * 0.58})">
    <path
      d="M7.5 10V7.75a4.5 4.5 0 1 1 9 0V10"
      fill="none"
      stroke="white"
      stroke-width="2.2"
      stroke-linecap="round"
      stroke-linejoin="round"
    />
    <rect
      x="5.5"
      y="10"
      width="13"
      height="9"
      rx="2.5"
      fill="none"
      stroke="white"
      stroke-width="2.2"
      stroke-linecap="round"
      stroke-linejoin="round"
    />
  </g>
</svg>`;
}

async function generate() {
  for (const size of SIZES) {
    const svg = makeSvg(size);
    const buf = Buffer.from(svg, "utf-8");
    const outPath = join(iconsDir, `icon${size}.png`);
    await sharp(buf).resize(size, size).png().toFile(outPath);
    console.log(`✓  icon${size}.png`);
  }

  // Grey variant for "disconnected" state
  async function makeGreyIcon(size) {
    const svg = makeSvg(size).replace(/#444ce7/g, "#9ca3af");
    const buf = Buffer.from(svg, "utf-8");
    await sharp(buf).resize(size, size).png().toFile(join(iconsDir, `icon${size}-grey.png`));
  }
  await makeGreyIcon(32);
  console.log("✓  icon32-grey.png");
  console.log("\nAll icons written to public/icons/");
}

generate().catch((err) => {
  console.error("Icon generation failed:", err.message);
  process.exit(1);
});
