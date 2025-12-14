# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Star Wars open-galaxy space RPG built with **Godot 4 + GDScript**. Native-first 3D game with space/ground traversal, procedural generation inspired by No Man's Sky, and Star Wars lore from KOTOR, films, and Clone Wars.

**Current state:** Phase 4 complete - Full vertical slice with gameplay loop: Fly → Land → Explore POI → Collect Artifact → Return to Ship.

## Development Commands

```bash
# Open in Godot Editor
godot project.godot

# Run the game
godot --path . scenes/main.tscn

# Run determinism tests
godot --headless --script packages/core/tests/test_determinism.gd
godot --headless --script packages/procgen/tests/test_terrain.gd

# Run graphics validation tests (32-bit color compliance)
godot --headless --script packages/render/tests/test_graphics.gd
```

## Architecture

```
swar-sky/
├── project.godot
├── packages/
│   ├── core/               # Hash, PRNG, seed stack
│   ├── procgen/            # All generation code
│   │   ├── galaxy_generator.gd
│   │   ├── system_generator.gd
│   │   ├── planet_generator.gd
│   │   ├── terrain_generator.gd
│   │   ├── poi_generator.gd        # NEW: POI placement
│   │   └── poi_grammars/
│   │       └── jedi_ruins.gd       # NEW: Ruins structure generator
│   ├── render/
│   │   ├── terrain_mesh.gd
│   │   ├── tile_streamer.gd
│   │   ├── poi_renderer.gd         # 3D POI visualization
│   │   └── graphics_validator.gd   # 32-bit color validation (autoload)
│   ├── gameplay/
│   │   ├── character_controller.gd
│   │   ├── ship_controller.gd
│   │   ├── ship_landing.gd         # NEW: Landed ship on surface
│   │   └── objective_system.gd     # NEW: Mission objectives
│   └── ui/
│       └── exploration_hud.gd      # NEW: Compass and markers
├── scenes/
│   ├── main.tscn
│   ├── galaxy_map/
│   ├── system_view/        # 2D orbital view (M to toggle)
│   ├── system_space/       # 3D spaceflight
│   └── planet_surface/     # 3D exploration with POIs
└── docs/
```

## Game Flow (Vertical Slice)

```
Galaxy Map → System Space (3D) → Planet Surface
   ↑              ↑    ↓              ↓
   └──────────────┴────┴──────────────┘
                  ↕
            System View (2D)

On Planet:
  Land near Ship → Find POI → Collect Artifact → Return to Ship → Take Off
```

## Controls

**Galaxy Map:** Click=select, Enter/Right-click=enter system, Scroll=zoom, Shift+Arrows=sectors, ESC=back

**System Space (3D):** Mouse=steer, W/S=throttle, A/D=strafe, Shift=boost, Q/E=roll, T=target, F=land, M=2D view, ESC=back

**System View (2D):** Click=select, Right-click=land, Scroll=zoom, Space=orbits, M=3D flight, ESC=back

**Planet Surface:** WASD=move, Shift=run, Space=jump, E=interact, Mouse=look, Tab=cursor, F3=debug, ESC=back

**Global:** F1=tests, F2=debug info

## POI Types

| Type | Description | Artifact |
|------|-------------|----------|
| Jedi Ruins | Ancient temple remains | Holocron |
| Imperial Outpost | Abandoned checkpoint | Data Chip |
| Crashed Ship | Wreckage with salvage | Ship Log |
| Cave System | Natural formation | Crystal |
| Ancient Monument | Alien structure | Relic |
| Rebel Cache | Hidden supply stash | Supplies |

## Procedural Generation

**Seed chain:** `globalSeed → sectorSeed → systemSeed → planetSeed → poiSeed`

**POI generation:**
```gdscript
# Generate POIs for planet
var pois := POIGenerator.generate_planet_pois(planet_seed, planet_type, terrain_config)

# Jedi Ruins layout
var layout := JediRuinsGenerator.generate_ruins(poi_seed, size)
```

## Key Files (Phase 4)

| File | Purpose |
|------|---------|
| `packages/procgen/poi_generator.gd` | POI placement and types |
| `packages/procgen/poi_grammars/jedi_ruins.gd` | Ruins structure generator |
| `packages/render/poi_renderer.gd` | 3D POI mesh rendering |
| `packages/render/graphics_validator.gd` | Runtime 32-bit color validation |
| `packages/gameplay/objective_system.gd` | Mission tracking |
| `packages/gameplay/ship_landing.gd` | Landed ship on surface |
| `packages/ui/exploration_hud.gd` | Compass, markers, prompts |

## Code Style

- Static typing: `var x: int = 5`
- Classes: PascalCase, functions: snake_case
- Constants: SCREAMING_SNAKE_CASE
- Private: underscore prefix `_state`

## Phase Roadmap

- [x] **Phase 0:** Seed stack foundation
- [x] **Phase 1:** 2D galaxy drill-down
- [x] **Phase 2:** Planet surface generation (terrain, streaming, character)
- [x] **Phase 3:** Spaceflight (ship controller, 3D system view, transitions)
- [x] **Phase 4:** Vertical slice (POIs, objectives, exploration loop)

## Vertical Slice Success Criteria

- [x] Start in space, see planets
- [x] Fly to planet, initiate landing
- [x] Spawn on procedural terrain
- [x] Walk to procedurally-placed POI (Jedi Ruins, etc.)
- [x] Collect artifact from POI
- [x] Return to ship, take off
- [x] Same seed = exact same experience
