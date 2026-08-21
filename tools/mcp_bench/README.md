# mcp_bench — which Godot MCP server, measured

Dev tooling. **Never wired into `check.sh`**: the repo's rule is that the MCP is an
accelerator for interactive work, never a dependency of the build, and a benchmark that
gated the build would make it one.

```bash
cd tools/mcp_bench && npm install
node bench.mjs                          # both servers
node bench.mjs --only=coding-solo       # one
node bench.mjs --only=coding-solo --repeat=2   # instrument self-check
```

Exits non-zero if a server that ran the scene-authoring steps produced the wrong scene.
Every run happens in a temp copy of `fixture/`, so the repo tree stays clean.

There are **no `.gd` files here on purpose**. `tools/` is a `LintCore.SOURCE_ROOTS` root and
`check.sh`'s parse gate scans every `*.gd` under it, so a fixture script would drag benchmark
scaffolding under the template's own gates.

## Results (2026-08-21, Godot 4.7.1, Node 22.22.2, M-series Mac)

| step | coding-solo 0.1.1 | satelliteoflove 4.1.0 |
|---|---|---|
| connect (session start) | 803 ms | 653 ms |
| cheap read (version) | **21 ms** | **7 ms** |
| project_info | 26 ms | 7 ms |
| scene_tree | no such tool | 7 ms |
| editor_state | no such tool | 7 ms |
| create_scene | **834 ms** | no such tool |
| add_node | **250 ms** | no such tool |
| save_scene | 251 ms | no such tool |

The architecture is the whole story, and it is visible in the shape of the numbers.
`@coding-solo/godot-mcp` spawns a **headless Godot per operation** — verified in its
`build/index.js` (`--headless --path X --script godot_operations.gd`), not taken from its
README, which does not say so. `@satelliteoflove/godot-mcp` holds a WebSocket bridge into a
running editor, so a call is a message: **flat 7 ms for everything that crosses the bridge**,
which is what a persistent connection predicts and a spawn-per-op design cannot reach.

**They are not competitors.** coding-solo *scaffolds* (create a scene, add nodes, load a
sprite, export a MeshLibrary). satelliteoflove *observes and drives* (live scene tree,
runtime state digests, input injection, deterministic `freeze`/`step`/`step_until`, profiler,
screenshots, tilemap/gridmap editing) and **cannot create a scene or add a node at all**. The
right question is not which wins but which job you are doing.

## Two things that would have made the table lie

**A 0 ms result that never left the process.** The first battery timed
`godot_project addon_status` as the cheap read and got a 0 ms median — an apparently
spectacular win. Control: kill the editor entirely and call it again. It still answered in
3.9 ms (`connected: false`), so it is served locally by the Node process and never reaches
Godot. The battery now uses `get_info`, which returns the live editor's Godot version and
project path and errors outright when the editor is gone.

**Timing an error path.** A wrong tool or action name returns an MCP error in ~3 ms, which
in a latency table is indistinguishable from a blazing-fast success. `timedCall` records
`isError` and the summary excludes failures, so a mis-mapped step shows as a gap rather than
as a win.

## Bugs and caveats found

- **coding-solo takes two different path conventions across its own tools.** `create_scene`
  accepts `res://bench.tscn` (its GDScript normalizes the prefix), but `add_node` and
  `save_scene` do a naive `join(projectPath, scenePath)` in `index.js` (~line 1307), so the
  same `res://` argument becomes `<project>/res:/bench.tscn` and they report the scene as
  missing. Pass bare paths (`bench.tscn`) — those work for all three.
- **satelliteoflove reports an addon version mismatch on Godot 4.7.1.** `addon_status`
  returns `addon_version: "unknown", versions_match: false` and the server logs
  `Handshake failed (addon may be outdated)`, with addon and server both at 4.1.0. Every
  tool tried still worked. Treat it as an untested-on-4.7 signal, not a blocker.
- **The addon is not free to install, which is why this repo does not commit it.**
  `plugin.gd` forces an `MCPGameBridge` autoload via `ProjectSettings.save()`, and that save
  strips every comment from `project.godot` (restoring them by hand does not survive the next
  build that loads the plugin). The autoload then either ships (+1MB) or errors three times on
  every packed boot. See `docs/DECISIONS.md`; the on-demand install recipe is in CLAUDE.md.
- The bridge runs **headless** — `Godot --headless --editor --path <proj>` brings up port
  6550 with no visible editor window. The README's "open the Godot project" is not literally
  required.

## Speedups: what was measured, and what turned out not to exist

- **Drop the npx wrapper — worth 430 ms per session.** `npx -y @coding-solo/godot-mcp`
  costs **494 ms** to connect; invoking the resolved binary directly costs **64 ms** (medians
  of 3). `npx` also leaves a second `npm exec` process alive alongside the server. The
  committed `.mcp.json` still uses `npx` because a direct path is either machine-specific or
  an npx cache path that can be garbage-collected — portability was chosen over 430 ms, once
  per session.
- **Batching is the only per-call lever.** 250–835 ms per operation is the process spawn;
  nothing outside the server can remove it. Fewer, larger operations is the whole technique.
- **A warm `.godot` import cache does nothing — it does not exist.** The plan assumed the
  first operation paid for project import. Measured: `create_scene` costs 830/835/833/837 ms
  on four consecutive calls in the same project, and `.godot` is never created at all by
  these headless script runs. `create_scene` is simply ~3.3× more expensive than `add_node`;
  there is no cold-start to warm up.
- **Pinning the version buys determinism, not speed.** `0.1.1` is both installed and latest,
  so there is currently nothing to pin away from.

## Re-running this

The satelliteoflove side needs an editor bridge up first:

```bash
npx -y @satelliteoflove/godot-mcp --install-addon <proj>
# add to <proj>/project.godot:
#   [editor_plugins]
#   enabled=PackedStringArray("res://addons/godot_mcp/plugin.cfg")
/Applications/Godot.app/Contents/MacOS/Godot --headless --path <proj> --import
/Applications/Godot.app/Contents/MacOS/Godot --headless --editor --path <proj> &
```

Numbers move with machine and Godot version. The claims worth re-deriving are the *ratios*
and the architecture, not the absolute milliseconds.
