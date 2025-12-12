const fs = require("fs");
const path = require("path");
const { defineConfig } = require("@playwright/test");

const webRootEnv = process.env.SWAR_WEB_ROOT;
const webRoot = webRootEnv ? path.resolve(webRootEnv) : null;
const hasWebRoot = !!(webRoot && fs.existsSync(webRoot));

module.exports = defineConfig({
  testDir: "./tests",
  timeout: 120_000,
  retries: process.env.CI ? 1 : 0,
  use: {
    baseURL: "http://127.0.0.1:4173",
  },
  webServer: hasWebRoot
    ? {
        command: `node server.cjs "${webRoot}" 4173`,
        port: 4173,
        reuseExistingServer: !process.env.CI,
        timeout: 120_000,
      }
    : undefined,
});

