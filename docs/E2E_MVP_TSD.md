# E2E MVP Technical Spec (TSD)

## 1) Scope

This document specifies the technical implementation for the MVP “planet run” mission:

- Deterministic procgen: galaxy → system → planet → terrain tiles → POIs
- Tile streaming and surface exploration loop
- Objective system and HUD integration
- Test strategy: headless Godot + Playwright web E2E

Explicitly out of scope for MVP:
- Audio (SFX/music/VO). The runtime should not require audio nodes, bus configs, or user-gesture audio unlocks (web).

## 2) Current Code Map (by package)

- `packages/core`
  - `hash.gd`: deterministic hashing primitives (`hash_coords2`, `hash_combine`, `to_float`)
  - `prng.gd`: deterministic PRNG
  - `seed_stack.gd`: seed layering (autoload in full game)
- `packages/procgen`
  - `galaxy_generator.gd`, `system_generator.gd`, `planet_generator.gd`
  - `terrain_generator.gd`: tile generation + profiling + cached simplex lattice
  - `poi_generator.gd`: POI placement and artifact naming
  - tests: `packages/procgen/tests/*`
- `packages/render`
  - `tile_streamer.gd`: streams tiles around player
  - `terrain_mesh.gd`: builds meshes from `TerrainTileData`
  - `poi_renderer.gd`: POI markers + interaction triggers
- `packages/gameplay`
  - `objective_system.gd`: objective state machine
  - `character_controller.gd`: movement + terrain-following
  - `ship_landing.gd`: ship marker + board interaction
- `packages/ui`
  - `exploration_hud.gd`: markers, prompts, objective text, popup
- `scenes/*`
  - `scenes/main.tscn` + `scenes/main.gd`: view manager, also web `?e2e=1` hook
  - `scenes/planet_surface/*`: main MVP gameplay scene

## 3) End-to-End Flow (Signals + Data)

### 3.1 Navigation stack

- `scenes/main.gd` owns view state transitions and passes seed/type details to child scenes.
- On landing: instantiate `PlanetSurfaceScene` and call `planet_surface.initialize(seed, type, name, detail)`.

### 3.2 Planet surface initialization

`scenes/planet_surface/planet_surface.gd`:
- Calls `TileStreamer.initialize(seed, type, detail)`
  - sets `terrain_config.tile_world_size = tile_streamer.tile_size`
  - starts streaming around origin and/or player tile
- Spawns player and ship near a terrain-valid point
- Loads and wires “systems” via `load()` (avoids parse-time autoload deps):
  - `POIGenerator`, `POIRenderer`, `ShipLanding`, `ObjectiveSystem`, `ExplorationHUD`
- Generates POIs deterministically:
  - `pois = POIGenerator.generate_planet_pois(planet_seed, planet_type, terrain_config)`
- Sets mission objectives:
  - `objective_system.generate_planet_objectives(pois, ship_spawn_position)`

### 3.3 Interaction loop

Expected signal/data flow:
- Player moves → `CharacterController.position_changed(world_pos)`
- Planet surface listens and:
  - `tile_streamer.update_player_position(world_pos)` (already done inside controller)
  - `objective_system.update_player_position(world_pos)` (for ship return completion)
  - `poi_renderer.update_player_position(world_pos)` (enter POI zones; collect artifact)
- POI enter:
  - `poi_renderer.poi_entered(poi)` → `objective_system.on_poi_discovered(poi)`
- Artifact collected:
  - `poi_renderer.artifact_collected(poi, artifact_name)` → `objective_system.on_artifact_collected(poi, artifact_name)`
  - `objective_system.artifact_collected(...)` → HUD popup
- Ship boarding:
  - `ship_landing.board_requested` → planet surface emits `mission_completed(collected_artifacts)`

## 4) Procedural Generation Contracts

### 4.1 Seed derivation

Goals:
- No hidden ordering (no Dictionary iteration dependence)
- No autoload hard dependencies in procgen (tests must run in headless `SceneTree`)

Rules:
- Galaxy/system/planet/tile seeds must be derived via `Hash.hash_combine(parent_seed, [...])` with explicit salt tokens (ints/strings).
- Tile generation seed uses `["TILE", tile_x, tile_y, lod]` salt.

### 4.2 Terrain generation API

`TerrainGenerator.generate_tile(config, tile_coords, lod, resolution, enable_profile=false) -> TerrainTileData`

Implementation notes:
- Heightmap generated via cached per-octave simplex lattice evaluation (world-coordinate keyed).
- Seam correctness is enforced by deriving all lattice indices from world positions; adjacent tiles share the same boundary sample positions.
- Normal map computed from the heightmap after generation.
- Biome generation uses a cached “moisture” grid (one simplex field), avoiding per-point extra simplex calls.

## 5) Tile Streaming Architecture

`TileStreamer` responsibilities:
- Determine needed tile coords around player tile.
- Unload out-of-range tiles.
- Load tiles within per-frame budget (`_max_tiles_per_frame`) on an interval.

Performance constraints:
- Tile generation + mesh build currently occurs on the main thread.
- Frame budget is controlled by limiting tiles per update; but high `ms/tile` will still hitch.

Planned technical improvements (post-TSD acceptance):
- Reuse scratch buffers inside `TerrainGenerator` hot path to remove per-octave allocations.
- Optional: worker thread for data generation (tile height/biome) and main-thread mesh build.

## 6) Web Export / E2E Hook

`scenes/main.gd` web E2E mode:
- When `OS.has_feature("web")` and URL has `?e2e=1`:
  - Generates a small set of tiles and computes `per_tile_ms`
  - Publishes:
    - `window.__SWAR_E2E_RESULT__`
    - `window.__SWAR_E2E_DONE__ = true`

This is used by Playwright to assert that the build loads and that procgen executes.

## 7) Testing Strategy

### 7.1 Headless unit/integration tests (Godot)

- Determinism: `godot --headless --script packages/core/tests/test_determinism.gd`
- Terrain correctness/perf: `godot --headless --script packages/procgen/tests/test_terrain.gd`
- Tile/world mapping + seam exactness: `godot --headless --script packages/procgen/tests/test_tile_mapping.gd`

### 7.2 Browser E2E tests (Playwright)

Location: `tools/e2e/`

Assumptions:
- Godot Web export is built externally into a folder containing `index.html`.
- `SWAR_WEB_ROOT` points at that folder.

Run:
- `cd tools/e2e`
- `npm install`
- `npm run install-browsers`
- `$env:SWAR_WEB_ROOT = \"tools/e2e/.tmp/web\"; npm test`

Notes:
- Godot Web export requires export templates installed for your engine version (e.g. `4.5.1.stable`).

Test behavior:
- Loads `index.html?e2e=1`
- Waits for `window.__SWAR_E2E_DONE__`
- Asserts `per_tile_ms < SWAR_E2E_TILE_MS_MAX` (default 5000)

## 7.3 MCP Servers to Leverage (2025-12-12)

Canonical sources:
- Reference servers: `modelcontextprotocol/servers`
- Registry/discovery: `modelcontextprotocol/registry` (and the hosted registry UI)

Recommended MCP servers for this project:
- **Playwright**: `microsoft/playwright-mcp` (drive E2E on Web export; collect screenshots + timings aligned to `?e2e=1`).
- **Filesystem**: reference `Filesystem` server (safe, scoped file edits when used in other MCP-capable clients).
- **Git**: reference `Git` server (review diffs, blame, history; keep perf changes accountable).
- **Fetch**: reference `Fetch` server (bring in external docs/lore snippets into a controlled pipeline; reduce “random web paste” drift).
- **Memory**: reference `Memory` server (persist budgets/decisions: tile performance target, seam invariants, seed salts).
- **Inspector**: `modelcontextprotocol/inspector` (debug custom MCP integrations and tool schemas if/when we add a project-specific MCP server).
- Optional **Sentry**: `getsentry/sentry-mcp` (post-MVP: web error triage, crash clustering).
- Optional **Notion**: `makenotion/notion-mcp-server` (sync the spec outward if the team uses Notion).
- Optional **Linear**: `jerhadf/linear-mcp-server` (turn acceptance criteria into tracked issues, auto-update status from CI runs).

How this ties to the MVP docs:
- `docs/E2E_MVP_FSD.md` acceptance criteria becomes the source of truth for E2E checks.
- `docs/E2E_MVP_TSD.md` defines the stable test harness (`?e2e=1` + Playwright) and the perf budget contracts.

## 8) Performance Budgets & Instrumentation

Primary budget:
- Terrain tile generation ≤50ms/tile @ 33x33 headless baseline

Instrumentation:
- `TerrainProfile` in `packages/procgen/terrain_generator.gd` tracks:
  - total / heights / biomes / normals time
  - fbm/simplex time and `hash_calls`
  - per-layer timing

Required reporting:
- `packages/procgen/tests/test_terrain.gd` prints the profile report once per run.

## 9) Risks & Mitigations

- **Seam cracks**: any caching must remain world-coordinate keyed; tests enforce seam exactness.
- **World drift / determinism**: avoid float-accumulated stepping; always derive sample positions from `(offset + i*step)`.
- **Main-thread hitches**: cap tiles per frame; prefer async generation when stable.
- **Web startup timing**: Playwright uses long timeouts; E2E mode should fail fast on exceptions and always set `__SWAR_E2E_DONE__`.

## 10) Deliverables Checklist (MVP)

- Planet run loop works end-to-end
- Determinism + seam tests passing
- Tile streaming “playable enough” for MVP target platform
- Playwright E2E green against a web export
