# Turritopsis Dohrnii: The Undying Tide

A keyboard-only browser game: the immortal jellyfish dives through endless, ever darker ocean depths, collecting gene fragments, dodging Drift-corrupted predators, and regenerating as a polyp when it loses its last heart - for the highest score on a local top-10 scoreboard.

This repository holds the game's ***plain specs, not its code. The code (React 19 + TypeScript + Vite, drawn on one HTML5 canvas) is regenerated from them with [turri](https://github.com/turri-oss/turri). Learn ***plain at [plainlang.org/docs](https://plainlang.org/docs/).

## Layout

- `ocean.plain` → `depths.plain` → `predators.plain` → `regeneration.plain` → `animation.plain` - the modules, each built on the one before; `animation` is the top module and holds the whole game.
- `template/` - the shared stack, architecture, test reqs and concepts.
- `resources/color_pallete.yaml` - the colour palette.
- `test_scripts/` - the unit and conformance test runners.
- `config.turri.yaml` - how the project is built.

## Build and play

With turri in this folder, regenerate `animation.plain`, then release it; the game runs with `npm run dev` from the released folder.

## Controls

Swim: arrow keys or WASD · Sting: Space · Dash: Shift · Pause: P or Esc
