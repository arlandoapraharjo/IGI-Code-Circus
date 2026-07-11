extends Resource
class_name BiomeData

## One of these should be created per biome (e.g. biome_snow.tres,
## biome_desert.tres, biome_grass.tres). Fill in the fields in the
## Inspector — drag the correct model/scene for that biome's asset kit
## into each slot. The map generator reads whichever BiomeData is active
## at runtime; it never hardcodes a specific biome's paths itself.

@export_group("Tiles")
@export var tile_base: PackedScene
@export var tile_straight: PackedScene
@export var tile_corner: PackedScene
@export var tile_spawn: PackedScene
@export var tile_end: PackedScene

@export_group("Decorations")
@export var tree_model: PackedScene
@export var tree_large_model: PackedScene
@export var rock_model: PackedScene
@export var bush_model: PackedScene

@export_group("Look & Feel")
## Assign a different Environment resource per biome (sky, fog, ambient
## light, tonemap, etc.) — this is what actually makes each biome feel
## distinct beyond just the models.
@export var environment: Environment
@export var has_heat_distortion: bool = false
## Optional: some biomes may want denser/sparser decoration than others.
@export_range(0.0, 1.0) var decoration_chance: float = 0.2
## Hotbar color theme for this biome. Assign a HotbarTheme .tres resource.
@export var hotbar_theme: HotbarTheme
