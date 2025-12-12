# Repository Guidelines

## Project Structure & Module Organization
- **Engine:** Godot 4 with GDScript (native-first, web export available)
- Current artifacts: `PROCGEN_PLAN.md` (procgen principles) and `TECH_ROADMAP_META_PROMPT.xml` (architecture reference). The XML was written for Three.js but the design principles still apply.
- Layout: `packages/core`, `packages/render`, `packages/procgen`, `packages/gameplay`, `packages/ui`, and `tools/` for inspectors/visualizers. Co-locate tests with code (e.g., `packages/core/tests/`).
- Store shared docs/figures in `docs/` once created; avoid untracked scratch files in root.

## Build, Test, and Development Commands
- Open project: `godot project.godot`
- Run game: `godot --path . scenes/main.tscn`
- Run headless tests: `godot --headless --script packages/core/tests/test_determinism.gd`
- Export: Configure export presets in editor, then `godot --headless --export-release "preset" output_path`

## Coding Style & Naming Conventions
- GDScript with static typing everywhere: `var x: int = 5`, `func foo() -> int:`
- Class names: PascalCase (`class_name GalaxyGenerator`)
- Functions/variables: snake_case (`get_sector_seed`, `num_planets`)
- Constants: SCREAMING_SNAKE_CASE (`const SECTOR_SIZE: float = 1000.0`)
- Private members: prefix with underscore (`var _state: int`)
- Prefer pure static functions for generation (`output = f(seed, coords, archetypeIds)`)
- Keep deterministic seed derivation per layer (galaxy → system → planet → tile → poi) as documented in `PROCGEN_PLAN.md`.

## Testing Guidelines
- Unit tests in `tests/` subdirectory near source code
- Prefer deterministic fixtures seeded via explicit hashes
- Run tests headless for CI: `godot --headless --script path/to/test.gd`
- Aim for high coverage on core procgen systems
- Include performance assertions where practical (e.g., max gen time per tile)

## Commit & Pull Request Guidelines
- Use Conventional Commits with scope when possible (e.g., `feat(procgen): add tile interest maps`).
- PRs should include: summary, linked issue/task, test results, and screenshots or short clips for rendering/UI changes.
- Call out determinism-impacting changes and any new budgets (draw calls, memory) in the PR description.

## Security & Configuration Tips
- Keep secrets out of the repo; use Godot's `user://` directory for local config
- Do not commit large binaries; prefer glTF assets stored in versioned `assets/` with LFS if needed
- When adding tools, default to read-only operations against seeds/worlds; guard any file writes with prompts
