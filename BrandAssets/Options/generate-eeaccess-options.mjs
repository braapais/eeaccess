import { writeFileSync } from "node:fs";

const colors = {
  deepNavy: "#001A24",
  pine: "#0C241C",
  teal: "#0F3324",
  mint: "#22C55E",
  white: "#FFFFFF",
  paleMint: "#9AF2BF",
};

const eeMonogram = (x, y, scale, left = colors.white, right = colors.mint) => `
  <g transform="translate(${x} ${y}) scale(${scale})">
    <rect x="0" y="0" width="78" height="242" rx="20" fill="${left}"/>
    <rect x="0" y="0" width="190" height="56" rx="28" fill="${left}"/>
    <rect x="0" y="93" width="158" height="56" rx="28" fill="${left}"/>
    <rect x="0" y="186" width="190" height="56" rx="28" fill="${left}"/>
    <rect x="226" y="0" width="78" height="242" rx="20" fill="${right}"/>
    <rect x="226" y="0" width="172" height="56" rx="28" fill="${right}"/>
    <rect x="226" y="93" width="142" height="56" rx="28" fill="${right}"/>
    <rect x="226" y="186" width="172" height="56" rx="28" fill="${right}"/>
  </g>`;

const barcode = (x, y, h, color = colors.white, opacity = 1) => {
  const widths = [20, 10, 32, 14, 42, 12, 24, 46, 16, 30];
  let cursor = x;
  return `<g opacity="${opacity}">${widths
    .map((w, i) => {
      const rect = `<rect x="${cursor}" y="${y}" width="${w}" height="${h}" rx="${Math.min(10, w / 2)}" fill="${color}"/>`;
      cursor += w + (i % 2 === 0 ? 20 : 14);
      return rect;
    })
    .join("")}</g>`;
};

const qrDots = (color = colors.white) => `
  <g fill="${color}">
    <rect x="646" y="638" width="62" height="62" rx="14"/>
    <rect x="732" y="638" width="34" height="34" rx="10"/>
    <rect x="646" y="724" width="34" height="34" rx="10"/>
    <rect x="724" y="716" width="62" height="62" rx="14"/>
  </g>`;

const defs = `
  <defs>
    <filter id="softGlow" x="-25%" y="-25%" width="150%" height="150%" color-interpolation-filters="sRGB">
      <feDropShadow dx="0" dy="0" stdDeviation="14" flood-color="${colors.mint}" flood-opacity="0.52"/>
    </filter>
    <filter id="lift" x="-20%" y="-20%" width="140%" height="140%" color-interpolation-filters="sRGB">
      <feDropShadow dx="0" dy="22" stdDeviation="24" flood-color="#000000" flood-opacity="0.34"/>
    </filter>
  </defs>`;

const iconFrame = (inner) => `<svg width="1024" height="1024" viewBox="0 0 1024 1024" fill="none" xmlns="http://www.w3.org/2000/svg">
  ${defs}
  <rect width="1024" height="1024" fill="${colors.deepNavy}"/>
  <rect x="82" y="82" width="860" height="860" rx="178" fill="${colors.deepNavy}" stroke="${colors.paleMint}" stroke-width="24" filter="url(#softGlow)"/>
  <path d="M106 720C250 720 276 632 410 676C558 724 640 826 918 764" stroke="${colors.paleMint}" stroke-width="26" stroke-linecap="round" opacity="0.95"/>
  <path d="M118 310C248 250 302 172 416 202C532 233 590 132 714 188C805 229 816 301 924 326" stroke="${colors.mint}" stroke-width="18" stroke-linecap="round" opacity="0.62"/>
  ${inner}
</svg>`;

const option1 = iconFrame(`
  <g filter="url(#lift)" transform="rotate(-4 512 512)">
    <rect x="238" y="276" width="548" height="470" rx="84" fill="${colors.white}"/>
    <rect x="274" y="312" width="476" height="398" rx="58" fill="${colors.teal}"/>
    ${eeMonogram(336, 374, 1.05)}
    ${barcode(344, 650, 54, colors.paleMint, 1)}
  </g>`);

const option2 = iconFrame(`
  <g filter="url(#lift)">
    <rect x="232" y="214" width="560" height="596" rx="112" fill="${colors.pine}" stroke="${colors.paleMint}" stroke-width="18"/>
    <rect x="288" y="270" width="448" height="484" rx="72" fill="${colors.deepNavy}"/>
    ${eeMonogram(334, 354, 1.03)}
    ${qrDots(colors.mint)}
    <circle cx="706" cy="316" r="28" fill="${colors.paleMint}"/>
  </g>`);

const option3 = iconFrame(`
  <g filter="url(#lift)">
    <rect x="296" y="250" width="460" height="510" rx="92" fill="${colors.white}" transform="rotate(7 526 505)"/>
    <rect x="238" y="290" width="484" height="456" rx="84" fill="${colors.pine}" transform="rotate(-6 480 518)"/>
    <rect x="274" y="326" width="412" height="380" rx="58" fill="${colors.teal}" transform="rotate(-6 480 518)"/>
    ${eeMonogram(336, 402, 1.02)}
    ${barcode(344, 676, 48, colors.paleMint, 0.95)}
  </g>`);

const option4 = iconFrame(`
  <g filter="url(#lift)">
    <rect x="230" y="244" width="564" height="536" rx="110" fill="${colors.teal}"/>
    <path d="M284 648H742" stroke="${colors.paleMint}" stroke-width="30" stroke-linecap="round"/>
    <path d="M690 584L762 648L690 712" stroke="${colors.paleMint}" stroke-width="30" stroke-linecap="round" stroke-linejoin="round"/>
    ${eeMonogram(318, 332, 1.12)}
    ${barcode(344, 702, 42, colors.white, 0.9)}
  </g>`);

const logoLockup = (name, iconSvg, accentLabel) => {
  const symbol = iconSvg
    .replace('<svg width="1024" height="1024" viewBox="0 0 1024 1024" fill="none" xmlns="http://www.w3.org/2000/svg">', '<g transform="translate(64 64) scale(0.36)">')
    .replace("</svg>", "</g>");
  return `<svg width="1600" height="520" viewBox="0 0 1600 520" fill="none" xmlns="http://www.w3.org/2000/svg">
  <rect width="1600" height="520" fill="${colors.deepNavy}"/>
  ${symbol}
  <text x="528" y="238" fill="${colors.white}" font-family="Helvetica, Arial, sans-serif" font-size="126" font-weight="700">EEAccess</text>
  <text x="536" y="316" fill="${colors.paleMint}" font-family="Helvetica, Arial, sans-serif" font-size="34" font-weight="700">ELBAEVERYWHERE</text>
  <text x="536" y="382" fill="${colors.mint}" font-family="Helvetica, Arial, sans-serif" font-size="30" font-weight="700">${accentLabel}</text>
</svg>`;
};

const options = [
  ["option-1-card-pass", option1, "DIGITAL CARD ACCESS"],
  ["option-2-watch-qr", option2, "WATCH-READY WALLET"],
  ["option-3-stacked-wallet", option3, "CARDS ON YOUR WRIST"],
  ["option-4-scan-access", option4, "SCAN. ENTER. GO."],
];

for (const [name, icon, label] of options) {
  writeFileSync(new URL(`${name}-icon.svg`, import.meta.url), icon);
  writeFileSync(new URL(`${name}-logo.svg`, import.meta.url), logoLockup(name, icon, label));
}
