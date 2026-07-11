# Biome Setup Guide

This directory contains `BiomeData.gd` (the resource class) and any `.tres`
biome resource files you create. Each `.tres` file represents one biome
(snow, desert, grass, etc.).

## How to create a new BiomeData resource

1. **In the Godot Editor**, right-click this `biomes/` folder in the
   FileSystem dock → **New Resource…**
2. Search for **BiomeData** and select it.
3. Name it descriptively, e.g. `biome_snow.tres`, `biome_desert.tres`.
4. In the **Inspector**, fill in every field:

### Tiles group
| Field | What to drag here |
|---|---|
| `tile_base` | The base ground tile for this biome (e.g. `snow-tile.glb`) |
| `tile_straight` | Straight path tile |
| `tile_corner` | Corner/curve path tile |
| `tile_spawn` | Spawn-point path tile |
| `tile_end` | End-point path tile |

### Decorations group
| Field | What to drag here |
|---|---|
| `tree_model` | Single tree model |
| `tree_large_model` | Large / double tree model |
| `rock_model` | Rock model |
| `bush_model` | Bush scene (e.g. `Bush2GLB3.tscn` — this carries the foliage shader) |

### Look & Feel group
| Field | What to set |
|---|---|
| `environment` | An `Environment` resource for this biome (sky, fog, lighting) |
| `decoration_chance` | 0.0–1.0 — fraction of non-path tiles that get a decoration. Snow ≈ 0.2, desert ≈ 0.1, grass ≈ 0.3 are reasonable starting points. |

5. **Assign the `.tres`** to the MapGenerator node:
   - Select the **Map** node in `map.tscn`.
   - In the Inspector, find the **Biomes** array export.
   - Add your `.tres` file(s) to the array.
   - Optionally set **Forced Biome Index** to test a specific biome
	 (0-indexed, -1 = random each run).

---

## Environment Audit Checklist (Item 2)

For each biome's `Environment` resource, verify the following settings in
the Inspector to avoid GPU-bound stutter:

- [ ] **SDFGI** → **Disabled** (very expensive, unnecessary for a TD game
      with procedural maps)
- [ ] **Volumetric Fog** → **Disabled** (or set density very low)
- [ ] **SSR (Screen-Space Reflections)** → **Disabled**
- [ ] **SSAO** → **Disabled** or quality set to Low
- [ ] **Glow** → If enabled, keep iterations ≤ 4 and strength modest
- [ ] **Directional Shadow Max Distance** → ≤ 30.0 (set on the
      `DirectionalLight3D` node, currently 20.0 — good)
- [ ] **Sky** → Use a simple `ProceduralSkyMaterial` or a low-res
      panorama, not a high-res HDR unless needed for reflections

---

## Known biome asset paths

### Snow (confirmed working)
```
Tiles:
  tile_base       = res://assets/Models/GLB format/snow/snow-tile.glb
  tile_straight   = res://assets/Models/GLB format/snow/snow-tile-straight.glb
  tile_corner     = res://assets/Models/GLB format/snow/snow-tile-corner-round.glb
  tile_spawn      = res://assets/Models/GLB format/snow/snow-tile-spawn-round.glb
  tile_end        = res://assets/Models/GLB format/snow/snow-tile-end-round.glb

Decorations:
  tree_model       = res://assets/Models/GLB format/snow/snow-tile-tree.glb
  tree_large_model = res://assets/Models/GLB format/snow/snow-tile-tree-double.glb
  rock_model       = res://assets/Models/GLB format/snow/snow-tile-rock.glb
  bush_model       = res://addons/Mesh/Bush2GLB3.tscn

Environment:
  environment      = res://addons/Shader/default_env.tres
```

### Desert / Grass
> **TODO:** These need to be filled in once you've identified the correct
> asset paths in the Kenney tower-defense-kit. Look for directories like
> `desert/` or `grass/` under `res://assets/Models/GLB format/`. Each
> biome needs its own `Environment` resource too.
