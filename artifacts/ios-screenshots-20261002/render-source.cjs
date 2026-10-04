const fs = require('node:fs');
const path = require('node:path');
const { Resvg } = require('/Users/yangyang/.codex/tools/pen-localization/node_modules/@resvg/resvg-js');
const root = process.cwd();
const source = path.join(root, 'artifacts/ios-screenshots-20261002/source');
const out = path.join(root, 'marketing/app-store/ios-screenshots-pen-2026-10-02/assets');
const fontDir = path.join(root, 'marketing/app-store/2026-09/fonts');
const fontFiles = fs.readdirSync(fontDir).filter(f => /\.ttf$/.test(f)).map(f => path.join(fontDir, f));
fontFiles.push(path.join(source, 'Poppins-SemiBold.ttf'));
for (let i = 1; i <= 7; i++) {
  const svg = fs.readFileSync(path.join(source, `ios-english-${i}.svg`), 'utf8')
    .replace(/xlink:href="(image-[^"]+)"/g, (_, name) => {
      const data = fs.readFileSync(path.join(source, name)).toString('base64');
      return `xlink:href="data:image/png;base64,${data}"`;
    });
  const options = {font: {fontFiles, loadSystemFonts: false}};
  const original = new Resvg(svg, options).render().asPng();
  fs.writeFileSync(path.join(source, `svg-original-${i}.png`), original);
  const background = svg.replace(/<text\b[\s\S]*?<\/text>/, '');
  fs.writeFileSync(path.join(out, `ios-background-${i}.png`), new Resvg(background, options).render().asPng());
}
console.log('Rendered seven backgrounds; only the first marketing text element was omitted.');
