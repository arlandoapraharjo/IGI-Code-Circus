# BiomeData + MapGenerator System — Agent Briefing

This document briefs an AI coding agent (or a human) picking up work on this
system without prior context. It covers what exists, why it's built this
way, and what's still open. Read this before making changes — several
design decisions here look "simple to improve" in isolation but exist to
solve a specific problem encountered earlier; the rationale is included so
you don't accidentally reintroduce a bug that was already fixed once.

## Project context

- Engine: Godot 4.7
- Genre: tower defense
- Assets: Kenney tower-defense-kit (tile/prop models), plus a third-party
  foliage shader repo (`FaRu85/Godot-Foliage`) used for bushes
- Files of interest:
  - `MapGenerator.gd` — attached to a `Node3D` in the main map scene.
    Generates the enemy path and populates the map with tiles/decorations
    every run.
  - `BiomeData.gd` — a `Resource` (`class_name BiomeData`) holding all
    per-biome asset references and environment settings. One `.tres`
    instance exists per biome (snow / desert / grass planned).
  - `Snow-Stage/Spawner.gd` — enemy spawner, receives the generated
    `enemy_path`. **Not yet reviewed/optimized in this pass** — see "Open
    items" below.
  - `foliage.gdshader` (from the Godot-Foliage repo) — the bush shader.
    Assigned as a material override, not baked into the mesh resource.

## Why biomes are data, not scenes

Early in this project each biome could have been its own duplicated map
scene + script. That was deliberately rejected: the path-generation
algorithm has nothing to do with biome, and duplicating it 3x means every
future fix has to be applied 3 times and will drift out of sync. Instead:

- **One scene, one script** (`MapGenerator.gd`) contains all generation
  logic and hardcodes nothing biome-specific.
- **`BiomeData.gd`** is the only place biome-specific data lives (tile
  models, decoration models, `Environment` resource, decoration density).
- At `_ready()`, `MapGenerator` picks a `BiomeData` (random from an
  assigned array, or forced via `forced_biome_index`) and populates its
  working vars from it via `_apply_biome()`.

**Do not reintroduce hardcoded `load("res://kenney_tower-defense-kit/...")`
paths into `MapGenerator.gd`.** If a new asset type is needed, add a field
to `BiomeData.gd` and wire it through `_apply_biome()`.

## BiomeData.gd — field reference

| Field | Type | Purpose |
|---|---|---|
| `tile_base` / `tile_straight` / `tile_corner` / `tile_spawn` / `tile_end` | `PackedScene` | Ground/path tile variants for this biome |
| `tree_model` / `tree_large_model` / `rock_model` / `bush_model` | `PackedScene` | Decoration props for this biome |
| `environment` | `Environment` | Swapped into the scene's `WorldEnvironment` node when this biome is active |
| `decoration_chance` | `float` (0–1) | Per-tile chance of spawning a decoration; lets biomes vary in density (e.g. desert sparser than grass) |

Each biome is a separate `.tres` file built in the Godot editor by creating
a `BiomeData` resource and dragging the correct assets into each slot —
there is no code path that constructs these programmatically.

## MapGenerator.gd — execution flow

```
_ready()
  → randomize()                      # seed RNG once, not per-generation
  → _apply_biome(_pick_biome())       # resolve working vars from BiomeData
  → _generate_path()                  # build enemy_path
  → _build_map()                      # place tiles + batch decorations
  → _setup_spawner()                  # hand enemy_path to Spawner
```

### Path generation — half-grid maze + quarter-checkpoint zigzag

This went through several iterations; the current approach exists to solve
three separate problems encountered along the way. Do not "simplify" it
without understanding why each piece is there:

1. **Problem 1 — freezing at larger map sizes.** The original path
   generator was a random DFS with a strict "no more than 1 adjacent
   visited neighbor" backtracking check. This is combinatorially explosive
   at scale (self-avoiding-walk-with-spacing is close to NP-hard) and
   could freeze the game for seconds at `MAP_SIZE` ≥ 20.
   - **Fix:** the path now walks a **half-resolution grid** (`HALF_STEP =
     2`, i.e. every step moves 2 real cells). Because any two visited
     half-grid cells are always ≥2 cells apart in real space, the spacing
     rule is satisfied *by construction* — no adjacency scanning, no
     backtracking on that rule at all.

2. **Problem 2 — inconsistent path complexity across seeds.** A DFS that
   stops as soon as it reaches the target produces a path shaped by
   whatever the random shuffle order happened to be — sometimes winding,
   sometimes nearly a straight line, with no way to control which.
   - **Fix:** `_build_maze_spanning_tree()` runs a full randomized DFS
     ("recursive backtracker") over the **entire** half-grid region,
     building a spanning tree, before any path is extracted. A spanning
     tree always contains exactly one path between any two points in it,
     and that path's shape reflects the whole maze rather than a lucky
     early exit — much more consistent complexity seed-to-seed.

3. **Problem 3 — direct/boring paths when start and end are in similar
   rows ("parallel").** Even with a full maze, the tree-path between two
   nearby points can still end up fairly direct.
   - **Fix:** the route is forced through checkpoints at each **quarter**
     of the map's width (`_build_quarter_targets()`), alternating between
     the top and bottom of the map at each checkpoint. This forces a
     zigzag — a guaranteed direction change every quarter — regardless of
     where start/end land. Each leg between waypoints is built as an
     **independent** spanning tree over cells not already used by a
     previous leg (`blocked` dict passed into
     `_build_maze_spanning_tree()`), which prevents legs from retracing
     each other and creating an impossible 4-way junction (there's no
     tile for that).

Key functions: `_generate_path()` → `_build_quarter_targets()` →
`_route_through_waypoints()` → `_build_maze_spanning_tree()` /
`_extract_path()` → `_expand_half_path()` (converts 2-cell hops back into
single-cell-wide real tiles).

`MAX_ROUTE_RETRIES` exists because a checkpoint can occasionally box in
the target; on failure the whole route is re-rolled with a fresh zigzag.
If that still fails repeatedly, `_generate_path()` falls back to a single
unrestricted maze leg — this should be effectively unreachable in
practice but exists as a safety net.

### Map building — MultiMesh batching

`_build_map()` avoids instancing hundreds of individual scenes (the
original approach, which caused per-frame rendering lag past `MAP_SIZE` ≈
15–20). Base tiles, trees, large trees, rocks, and bushes are all batched
into `MultiMeshInstance3D` nodes instead — one draw call per prop type
rather than one node per placed instance. Path tiles (spawn/straight/
corner/end) are still individually instanced since there are few of them
and each needs a distinct type + rotation.

**Important nuance:** `MultiMeshInstance3D` only reads raw mesh geometry.
It does **not** inherit a node's transform/scale, and it does **not**
automatically carry a `MeshInstance3D`'s surface material override — both
must be extracted and reapplied explicitly. See `_extract_mesh_and_material()`.

### Bush handling specifics

- `_extract_mesh_and_material()` pulls the mesh **and** whichever material
  is actually driving the shader (checks `get_surface_override_material(0)`
  first, since the foliage `ShaderMaterial` is applied as a per-node
  override in `Bush2GLB3.tscn`, not baked into the mesh resource).
- **Wind/wiggle variation:** a single shared `ShaderMaterial` means every
  bush instance would sway identically (MultiMesh has no per-instance
  uniform override for regular `uniform` variables). Instead,
  `_make_bush_variant_nodes()` creates `BUSH_VARIANT_COUNT` (4) separate
  `MultiMeshInstance3D`s, each with its own `.duplicate()`d material with
  randomized `WindSpeed`/`WindStrength`/`WiggleSpeed`/etc. Bushes are
  randomly assigned to one of the 4 buckets at placement time. This is a
  deliberate trade-off (4 draw calls instead of 1, in exchange for visual
  variety) rather than true per-instance variation, which would require
  editing the shader to read `INSTANCE_CUSTOM` data — not yet done.
- **Scale:** randomized per-instance via `.scaled()` on the placement
  `Basis` (`BUSH_SCALE_MIN`/`MAX`), *not* by editing the source scene —
  editing the node's scale in `Bush2GLB3.tscn` would have no effect, since
  only the raw mesh resource is extracted, not the node's transform.
- **Performance:** bushes have shadow casting disabled
  (`BUSH_CAST_SHADOWS = false`) and a distance-based visibility fade
  (`BUSH_VISIBILITY_END` / `BUSH_VISIBILITY_FADE` via
  `visibility_range_end`) — alpha-blended, wind-animated foliage is
  expensive per-fragment, and this was identified as a likely contributor
  to enemy-side stutter after map generation.

## foliage.gdshader — uniform reference

| Uniform | Purpose |
|---|---|
| `Alpha` | **The leaf texture goes here.** Red channel is the primary cutout mask; green channel also contributes, blended against a distance-based value — do not confuse this with the texture's visible RGB color, which is unused. |
| `WiggleNoise` | A *separate* grayscale noise texture for the wiggle effect. Defaults to black (no-op) — do not assign a leaf texture here by mistake. |
| `TopColor` / `BottomColor` / `FresnelColor` | Actual foliage coloring — fully independent of the texture. |
| `WindScale` / `WindSpeed` / `WindStrength` / `WindDensity` | Wind sway parameters — these are what get randomized per bush variant. |
| `WiggleFrequency` / `WiggleStrength` / `WiggleSpeed` / `WiggleScale` | Secondary high-frequency wiggle motion, separate from the wind sway. |
| `MeshScale` | **Not an object size control** — it's the camera-facing billboard orientation offset. Do not use this to shrink/grow bushes; use the placement transform's scale instead. |
| `DistanceScale` / `DistanceStart` / `DistanceScaleRange` | Shrinks (not culls) foliage with camera distance. Actual culling is handled separately via `visibility_range_end` in the script, not by this shader. |
| `FaceRoationVariation` | Reads `UV2.x` to randomly rotate each leaf quad — requires the mesh to have a UV2 channel set up per the original repo's mesh requirements (quads only, UV1 fully filled 0–1, UV2.x carrying per-face rotation seed). |

## Known performance work already done

- Path generation bounded to avoid freezes at large `MAP_SIZE` (see above).
- `enemy_path.has()`/`.find()` linear scans replaced with an O(1)
  `path_lookup` dictionary built once per generation.
- Individual scene instancing for tiles/decorations replaced with
  `MultiMeshInstance3D` batching.
- Bush shadow casting disabled + distance visibility fade added.

## Open items — not yet done, flagged for follow-up

1. **`Spawner.gd` has not been reviewed.** Enemy-side stuttering after map
   generation was reported; foliage/environment optimizations above were
   applied as the most likely causes, but the enemy movement/spawning
   script itself has not been audited. Specifically check for:
   - Movement logic running in `_process` instead of `_physics_process`
     (makes movement directly sensitive to GPU frame-time variance).
   - Any per-frame linear scan over `enemy_path` (the same class of bug
     that was fixed in `MapGenerator.gd` — watch for a repeat here).
   - Enemy instancing/freeing per spawn without pooling, which can cause
     allocation-related hitches during waves.
2. **Environment resources (per-biome) have not been audited** for
   expensive features (SDFGI, volumetric fog, SSR, oversized directional
   shadow distance). Recommended to check manually in the editor.
3. **Physics interpolation** has been recommended but not implemented —
   consider enabling it project-wide or per-enemy-node to smooth visual
   stutter independent of its root cause.
4. **True per-instance bush wind variation** (via `INSTANCE_CUSTOM` +
   shader edit) was discussed as a future upgrade over the current
   4-variant-bucket approach, but not implemented.
5. Only the **snow** biome's assets are confirmed/working end-to-end.
   Desert/grass `BiomeData.tres` instances still need to be created with
   their actual asset paths (not known to this agent — must be filled in
   via the editor, not assumed from Kenney's typical folder naming).

## Constants quick-reference (`MapGenerator.gd`)

| Constant | Value | Purpose |
|---|---|---|
| `MAP_SIZE` | 20 | Grid dimensions (square) |
| `TILE_SIZE` | 1.0 | World-space size per tile |
| `HALF_STEP` | 2 | Path walk step size (half-resolution grid) |
| `MAX_ROUTE_RETRIES` | 10 | Zigzag re-roll attempts before falling back |
| `BUSH_VARIANT_COUNT` | 4 | Number of randomized wind-material buckets |
| `BUSH_SCALE_MIN` / `MAX` | 0.5 / 0.75 | Random per-bush scale range |
| `BUSH_CAST_SHADOWS` | false | Shadow casting toggle for bushes |
| `BUSH_VISIBILITY_END` | 35.0 | Distance bushes fully disappear |
| `BUSH_VISIBILITY_FADE` | 6.0 | Fade-out distance before full disappearance |
