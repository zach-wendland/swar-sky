const { test, expect } = require("@playwright/test");
const fs = require("fs");
const path = require("path");

test("web e2e produces results", async ({ page, baseURL }) => {
  const webRootEnv = process.env.SWAR_WEB_ROOT;
  if (!webRootEnv) test.skip(true, "SWAR_WEB_ROOT not set");

  const webRoot = path.resolve(webRootEnv);
  if (!fs.existsSync(webRoot)) test.skip(true, "SWAR_WEB_ROOT does not exist");

  const maxMs = Number(process.env.SWAR_E2E_TILE_MS_MAX || "5000");

  await page.goto(`${baseURL}/index.html?e2e=1`, { waitUntil: "load" });
  await page.waitForFunction(() => window.__SWAR_E2E_DONE__ === true, null, {
    timeout: 120_000,
  });

  const result = await page.evaluate(() => window.__SWAR_E2E_RESULT__);
  expect(result).toBeTruthy();
  expect(typeof result.per_tile_ms).toBe("number");
  expect(result.per_tile_ms).toBeLessThan(maxMs);
});

