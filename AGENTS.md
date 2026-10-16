# AGENTS.md - Turritopsis Dohrnii: The Undying Tide

A keyboard-only browser game, written in ***plain and regenerated with turri. The `.plain` files are the source of truth: every change is a spec change, then a regeneration. Never edit `plain_modules/` or `dist/`.

## Modules

- The requires chain is `ocean` → `depths` → `predators` → `bestiary` → `upgrades` → `arena` → `regeneration` → `jellyfish-figure` → `creature-figures` → `effects` → `presentation` → `upgrade-visuals` → `scenery`; `scenery` is the top module and holds the whole game.
- `template/undying-tide-base.plain` holds the shared stack (stdlib React + Vite), architecture and test reqs; `template/undying-tide-concepts.plain` the shared concepts; `template/undying-tide-creatures.plain` the predator kinds, the polyp and the upgrades, imported from `predators` up; `template/undying-tide-presentation.plain` the reqs every animation module shares.
- Put a change in the module that owns the behaviour - swimming in `ocean`, levels, pulses and the run end by pulses in `depths`, the comb jelly, hearts, sting, dash and polyp in `predators`, the other predator kinds in `bestiary`, the upgrade choice and the upgrades in `upgrades`, keeping the HUD clear and waves pushing predators in `arena`, score and scoreboard in `regeneration`, the jellyfish's animation in `jellyfish-figure`, the other figures' animations in `creature-figures`, event effects and page motes in `effects`, fonts, the control legend, layout, the title footer and the goal in `presentation`, the look of upgrades in `upgrade-visuals`, and scenery and wave streaks in `scenery`.
- A concept that several modules share goes in a template, not in `exported_concepts`. A module's `requires` lists its parent, and also `regeneration` when it needs `:RegenerationScreen:`; longer lists fail validation.
- New, cross-cutting presentation (fonts, colours on pages, layout) goes in `presentation.plain`, so only it and the modules above it regenerate.
- The simulation stays deterministic and apart from rendering: animations never change the simulation state, a collision circle or a timing.
- Every colour comes from `resources/color_pallete.yaml`.

## Conformance tests

- Off (`conformance-tests: false`). Write them only when the person asks.

## Releasing

- Release the `scenery` module (the top module), then start it from `dist/scenery` with activate, installing in the same command - a separate `npm install` before activate has left `vite` missing:
  - command: `npm install --no-audit --no-fund && npm run dev -- --port 5173 --strictPort`
  - url: `http://localhost:5173`

## Publishing to GitHub Pages

- The live game is https://turri-oss.github.io/turritopsis-undying-tide/, served from the `gh-pages` branch of `turri-oss/turritopsis-undying-tide`, which holds only the built files.
- Publish only when the person asks, after a release:
  1. In `dist/scenery`: `BASE_PATH=/turritopsis-undying-tide/ npm run build`.
  2. Copy `dist/scenery/dist/` into a fresh folder in the system temp directory, add an empty `.nojekyll`, and delete `dist/scenery/dist/` again.
  3. There, `git init -b gh-pages`, commit everything, add `git@github.com:turri-oss/turritopsis-undying-tide.git` as `origin`, and `git push -f origin gh-pages`.
  4. Check `gh api repos/turri-oss/turritopsis-undying-tide/pages/builds/latest` reports `built`.

## Git

- `main` holds the specs only - `*.plain`, `template/`, `resources/`, `test_scripts/`, `config.turri.yaml`, `README.md`, `AGENTS.md`. Generated output is gitignored.
- Commit and push only when the person asks; they often want to try a change before it is committed.
- Commit messages follow [Conventional Commits 1.0.0](https://www.conventionalcommits.org/en/v1.0.0/): `<type>[optional scope]: <description>`, with an optional body and footers.
  - Types: `feat` for a new behaviour, `fix` for a bug, `docs` for README.md or AGENTS.md, `style`, `refactor`, `test`, `build`, `ci`, `chore`.
  - The scope is the module the change is in - `feat(predators): slower sting ring`, `fix(presentation): readable pause menu`.
  - The description is imperative and lower case, with no full stop.
  - A breaking change - one that changes a saved scoreboard, a URL or the state snapshot - adds `!` after the type or scope and a `BREAKING CHANGE:` footer.
  - The `gh-pages` publish commit is `chore(pages): publish <what changed>`.
