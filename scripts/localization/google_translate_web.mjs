#!/usr/bin/env node

// Browser-only Google Translate adapter. It drives translate.google.com in a
// real Chrome page and never calls an undocumented translation endpoint.

import { createInterface } from "node:readline";
import { createRequire } from "node:module";
import { existsSync } from "node:fs";
import { resolve } from "node:path";

const repoRoot = resolve(import.meta.dirname, "../..");
const playwrightPath = resolve(repoRoot, "build/localization/browser/node_modules/playwright-core");
if (!existsSync(playwrightPath)) {
  process.stderr.write(
    "playwright-core is missing; run: npm install --prefix build/localization/browser playwright-core@1.55.1\n",
  );
  process.exit(2);
}

const require = createRequire(import.meta.url);
const { chromium } = require(playwrightPath);
const chromePath = process.env.GOOGLE_CHROME_PATH
  || "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";

if (!existsSync(chromePath)) {
  process.stderr.write(`Chrome not found at ${chromePath}\n`);
  process.exit(2);
}

const browser = await chromium.launch({
  headless: process.env.GOOGLE_TRANSLATE_VISIBLE !== "1",
  executablePath: chromePath,
  args: ["--no-first-run", "--disable-default-apps"],
});
const page = await browser.newPage({ locale: "en-US" });

function marker(index) {
  return `<ROW${String(index).padStart(4, "0")}>`;
}

async function translate(target, texts) {
  const payload = texts.map((text, index) => `${marker(index)} ${text}`).join("\n");
  const url = `https://translate.google.com/?sl=en&tl=${encodeURIComponent(target)}&text=${encodeURIComponent(payload)}&op=translate`;

  for (let attempt = 0; attempt < 4; attempt += 1) {
    await page.goto(url, { waitUntil: "domcontentloaded", timeout: 90_000 });
    try {
      const expected = texts.map((_, index) => marker(index));
      if (texts.length === 1) {
        // Google sometimes removes the only outer row marker entirely. A
        // single-row fallback is unambiguous, so read the whole translated
        // pane and let Python continue validating the inner protected tokens.
        await page.waitForFunction(
          () => [...document.querySelectorAll("span.ryNqvb")]
            .some((element) => Boolean((element.textContent || "").trim())),
          null,
          { timeout: 90_000 },
        );
        await page.waitForTimeout(1_500);
        const singleValues = await page.locator("span.ryNqvb").allTextContents();
        const single = singleValues.join("").replace(marker(0), "").replace(/^\s/, "").replace(/\n$/, "");
        if (!single) throw new Error("Google Translate returned an empty single-row result");
        return [single];
      }
      // Give the webpage its full allowance to produce the first translated
      // row. Once output starts rendering, missing row markers are normally a
      // deterministic Google rewrite rather than a slow network. Fail that
      // batch quickly so Python can bisect it instead of waiting 90 seconds at
      // every fallback depth.
      await page.waitForFunction(
        ({ expectedMarkers }) => {
          const values = [...document.querySelectorAll("span.ryNqvb")]
            .map((element) => element.textContent || "");
          return expectedMarkers.some((item) => values.some((value) => value.includes(item)));
        },
        { expectedMarkers: expected },
        { timeout: 90_000 },
      );
      await page.waitForFunction(
        ({ expectedMarkers }) => {
          const values = [...document.querySelectorAll("span.ryNqvb")]
            .map((element) => element.textContent || "");
          return expectedMarkers.every((item) => values.some((value) => value.includes(item)));
        },
        { expectedMarkers: expected },
        { timeout: 15_000 },
      );
      // A long source row may be rendered as several consecutive sentence
      // spans. Give the result pane a short quiet period after all row markers
      // appear so the trailing spans are present before extraction.
      await page.waitForTimeout(1_500);

      const values = await page.locator("span.ryNqvb").allTextContents();
      const results = Array(texts.length).fill("");
      let current = -1;
      for (const value of values) {
        const next = texts.findIndex((_, index) => value.includes(marker(index)));
        let fragment = value;
        if (next >= 0) {
          current = next;
          const prefix = marker(next);
          fragment = value.replace(prefix, "").replace(/^\s/, "");
        }
        if (current >= 0) results[current] += fragment;
      }
      for (let index = 0; index < results.length; index += 1) {
        if (!results[index]) throw new Error(`missing translated marker ${marker(index)}`);
        results[index] = results[index].replace(/\n$/, "");
      }
      return results;
    } catch (error) {
      const body = (await page.locator("body").innerText()).slice(0, 2_000);
      const blocked = /unusual traffic|captcha|sorry|too many requests/i.test(body);
      process.stderr.write(
        `google web attempt ${attempt + 1} failed${blocked ? " (blocked)" : ""}: ${error.message}\n`,
      );
      const partialResult = /Timeout 15000ms exceeded/.test(error.message);
      if (partialResult || attempt === 3) {
        throw new Error(blocked ? "Google Translate requested a CAPTCHA or rate-limited the browser" : error.message);
      }
      await page.waitForTimeout((attempt + 1) * 10_000);
    }
  }
  throw new Error("translation retry loop ended unexpectedly");
}

const input = createInterface({ input: process.stdin, crlfDelay: Infinity });
try {
  for await (const line of input) {
    if (!line.trim()) continue;
    const request = JSON.parse(line);
    try {
      const translations = await translate(request.target, request.texts);
      process.stdout.write(`${JSON.stringify({ id: request.id, translations })}\n`);
    } catch (error) {
      process.stdout.write(`${JSON.stringify({ id: request.id, error: error.message })}\n`);
    }
  }
} finally {
  await browser.close();
}
