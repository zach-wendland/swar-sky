# E2E MVP Functional Spec (FSD)

## 1) Summary

Build a single, replayable “planet run” mission loop:

1. Navigate galaxy → select system → approach planet (space)
2. Land on planet surface
3. Discover a ruin POI
4. Retrieve a sealed holocron (artifact)
5. Return to ship to complete mission

The MVP is “quiet”: no audio, no combat, no voiced NPCs. The player experience leans on exploration, navigation, and deterministic procedural variety.

## 2) Player Fantasy / Lore Frame (MVP-safe)

You are a salvage pilot contracted by an archivist faction. You recover sealed information artifacts from ruins and return them intact. Holocrons are Force-locked; you cannot open them, only retrieve and extract.

Notes:
- Holocrons: Force-activated information devices used by Jedi/Sith.
- Datacrons: similar storage devices but not Force-locked (future optional loot).
- Kyber: Force-attuned energy-focusing crystals (future upgrade gating).

## 3) Goals

- End-to-end playable loop is stable and deterministic.
- World streaming does not hitch unacceptably during normal movement.
- Clear objective guidance (marker + distance) and simple interaction prompts.
- Planet runs are replayable with different seeds/planet types.
- Web export is supported (no audio/autoplay concerns).

## 4) Non-goals (MVP)

- No saving/loading across sessions.
- No inventory system beyond “artifact collected”.
- No crafting/upgrades, ship management, currency, or reputation.
- No procedural interior levels; POIs are surface markers and interaction triggers.
- No narrative branching, dialog trees, or cutscenes.

## 5) Core UX Loop

### 5.1 Galaxy → System → Space

- Player starts on Galaxy Map.
- Player selects a system; enters System View then System Space.
- In System Space:
  - Player targets a planet.
  - When close enough, UI prompts landing.
  - Landing transitions into Planet Surface with planet seed/type + detail.

### 5.2 Planet Surface Run

On entering Planet Surface:
- Terrain streams around player spawn point.
- A ship is placed at/near spawn as the extraction point.
- POIs are generated for the planet and rendered as markers/meshes.
- Objectives are generated from POIs:
  1) “Explore <POI Name>”
  2) “Retrieve <Artifact Name>”
  3) “Return to Ship”

Player actions:
- Move across terrain toward the objective marker.
- When entering POI area: objective completes and the artifact becomes collectible.
- Interact (key) to collect artifact.
- Return to ship; interact to board; mission completes.

## 6) Controls (MVP)

- Movement: WASD
- Run: Shift
- Jump: Space
- Interact: E
- Back/Exit: Esc (context-dependent)
- Debug: F3 (optional)

## 7) UI Requirements

Planet Surface HUD:
- Current objective title
- Distance to objective
- Screen-edge markers:
  - Objective marker
  - Ship marker
- Interaction prompt (“Press E to …”) when in range:
  - Enter POI
  - Collect artifact
  - Board ship
- Popup notification when artifact collected (name + POI origin)

System Space UI:
- Current target planet name + distance
- Landing prompt when landable

## 8) Gameplay Rules

- Exactly one “primary target POI” per run (MVP).
- Artifact exists only after POI “entered” OR is always present but collectible only after POI entry (implementation choice).
- Mission completion requires:
  - At least one artifact collected
  - Player within ship boarding distance

## 9) Procedural Content Requirements

Planet:
- Deterministic terrain per (planet_seed, planet_type, coords).
- Seam-correct tiles at LOD 0.

POIs:
- Deterministic POI placement based on planet seed/config.
- POI types: at minimum “ruins”.
- Each POI has:
  - world position (Vector3)
  - type id/name
  - artifact name (string)
  - artifact world position (Vector3) or derived location

## 10) Performance Requirements (MVP Targets)

Hard targets (streaming viability):
- Tile generation: ≤50ms/tile @ 33x33 (headless baseline)
- Tile streamer: main-thread frame budget safe (no “stop-the-world” bursts)

Interim targets (acceptable for MVP milestone):
- ≤150ms/tile in headless if generation is amortized (frame budget + queue) and movement remains responsive.

Web targets:
- Accept slightly higher budgets (2–3×), but avoid long main-thread stalls.

## 11) Determinism Requirements

- Given the same global seed + coordinates:
  - galaxy/system/planet structure matches across runs
  - terrain heights match at world positions and across tile seams
  - POI placements are stable
- No reliance on Dictionary iteration order or autoload-only globals in procgen.

## 12) Acceptance Criteria

- Start → land → retrieve artifact → return → mission completion works without manual intervention.
- Objective updates are correct and visible.
- Tile seam test passes; determinism tests pass.
- Playwright web E2E can load a web export and receive a valid `__SWAR_E2E_RESULT__`.

## 13) Known Risks / Edge Cases (Functional)

- Tile streaming stalls can strand the player (no terrain underfoot) or hitch heavily.
- POI generation may place POI in water or steep terrain; spawn/POI placement needs validity checks.
- Web: asset loading/wasm startup timeouts; avoid infinite waiting in E2E.

