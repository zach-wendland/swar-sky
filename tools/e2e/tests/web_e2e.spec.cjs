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

test("web e2e mission completes", async ({ page, baseURL }) => {
  const webRootEnv = process.env.SWAR_WEB_ROOT;
  if (!webRootEnv) test.skip(true, "SWAR_WEB_ROOT not set");

  const webRoot = path.resolve(webRootEnv);
  if (!fs.existsSync(webRoot)) test.skip(true, "SWAR_WEB_ROOT does not exist");

  await page.goto(`${baseURL}/index.html?e2e=mission`, { waitUntil: "load" });
  await page.waitForFunction(() => window.__SWAR_E2E_DONE__ === true, null, {
    timeout: 180_000,
  });

  const result = await page.evaluate(() => window.__SWAR_E2E_RESULT__);
  expect(result).toBeTruthy();
  expect(result.mode).toBe("mission");
  expect(result.success).toBe(true);
  expect(result.error).toBe("");
  expect(result.steps).toBeTruthy();
  expect(result.steps.discovered).toBe(true);
  expect(result.steps.collected).toBe(true);
  expect(result.steps.boarded).toBe(true);
  expect(Array.isArray(result.artifacts)).toBe(true);
  expect(result.artifacts.length).toBeGreaterThan(0);
});
