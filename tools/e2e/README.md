# SWAR-SKY Playwright E2E

This folder runs browser tests against a Godot Web export.

## Setup

Prerequisite (Godot export templates):
- Web export requires Godot export templates installed for your engine version.
- For Godot `4.5.1.stable`, templates must be under `C:\\Users\\<you>\\AppData\\Roaming\\Godot\\export_templates\\4.5.1.stable\\` and include `web_nothreads_release.zip`.

1. Install dependencies:
   - `cd tools/e2e`
   - `npm install`
   - `npm run install-browsers`

2. Build a Godot Web export into a local folder (example):
   - Copy `tools/e2e/export_presets.web.cfg` to `export_presets.cfg` in the repo root (it is gitignored).
   - Export to `tools/e2e/.tmp/web`
   - Ensure it contains `index.html`

## Run

- PowerShell:
  - `$env:SWAR_WEB_ROOT = \"tools/e2e/.tmp/web\"`
  - `npm test`

## What it tests

- Loads the exported build with `?e2e=1`
- Waits for `window.__SWAR_E2E_DONE__`
- Reads `window.__SWAR_E2E_RESULT__` and asserts basic sanity
