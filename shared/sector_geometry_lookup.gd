extends RefCounted
class_name SectorGeometryLookup
## Pure lookup tables for Slice 015's client-side sector geometry translation.
## No scene-tree, Node, or rendering dependency — unit-testable with plain
## Dictionary/String fixtures. Maps a validated blueprint's tile/structure
## `kind` string (already accepted by shared/sector_blueprint_schema.gd) to
## the presentation data a translator needs: procedural box dimensions for
## tiles, and a PackedScene resource path for structures. See
## docs/slices/015-sector-geometry-translation.md.
##
## These tables intentionally mirror SectorBlueprintSchema's supported kind
## sets exactly (enforced by a unit test) so the validator and the geometry
## lookup cannot silently drift apart.

## Per-grid-cell footprint shared by every tile kind (matches the existing
## FlatPlane per-unit convention in client/gameplay.tscn).
const _TILE_FOOTPRINT: float = 1.0
const _FLOOR_CORRIDOR_HEIGHT: float = 0.2
const _WALL_HEIGHT: float = 2.0

## Ticket 02: walls must read as taller than floor/corridor even as
## placeholder geometry. Slice 025 adds the organic ground kinds
## (path/plaza/gate/water/grass) as flat walkable slabs sharing the
## floor/corridor footprint; they render as distinct per-kind ground meshes so
## a future material pass can differentiate them.
const _TILE_DIMENSIONS: Dictionary = {
	"floor": Vector3(_TILE_FOOTPRINT, _FLOOR_CORRIDOR_HEIGHT, _TILE_FOOTPRINT),
	"corridor": Vector3(_TILE_FOOTPRINT, _FLOOR_CORRIDOR_HEIGHT, _TILE_FOOTPRINT),
	"wall": Vector3(_TILE_FOOTPRINT, _WALL_HEIGHT, _TILE_FOOTPRINT),
	"path": Vector3(_TILE_FOOTPRINT, _FLOOR_CORRIDOR_HEIGHT, _TILE_FOOTPRINT),
	"plaza": Vector3(_TILE_FOOTPRINT, _FLOOR_CORRIDOR_HEIGHT, _TILE_FOOTPRINT),
	"gate": Vector3(_TILE_FOOTPRINT, _FLOOR_CORRIDOR_HEIGHT, _TILE_FOOTPRINT),
	"water": Vector3(_TILE_FOOTPRINT, _FLOOR_CORRIDOR_HEIGHT, _TILE_FOOTPRINT),
	"grass": Vector3(_TILE_FOOTPRINT, _FLOOR_CORRIDOR_HEIGHT, _TILE_FOOTPRINT),
}

## Slice 024: which tile kinds are solid (get merged collision) versus visual
## ground (rendered as body-free MultiMesh instances). Walls block; floor and
## corridor are walkable ground whose collision is provided by the Gameplay
## FlatPlane, so they need no per-tile colliders.
const _SOLID_TILE_KINDS: Dictionary = {
	"wall": true,
}

const _STRUCTURE_SCENE_PATHS: Dictionary = {
	"house": "res://client/structures/house.tscn",
	"smithy": "res://client/structures/smithy.tscn",
	"armor_shop": "res://client/structures/armor_shop.tscn",
	"inn": "res://client/structures/inn.tscn",
	"church": "res://client/structures/church.tscn",
	"item_shop": "res://client/structures/item_shop.tscn",
	"tavern": "res://client/structures/tavern.tscn",
	"well": "res://client/structures/well.tscn",
	"npc_house": "res://client/structures/npc_house.tscn",
	"village_hall": "res://client/structures/village_hall.tscn",
}

## Slice 030: per-structure-kind collision footprint half-extent in grid cells,
## mirroring each prefab's BoxMesh width/depth (half = floor(size / 2)). Used by
## the server-side SectorCollisionMap to make buildings solid. Must stay in sync
## with the client/structures/<kind>.tscn sizes.
const _STRUCTURE_FOOTPRINTS: Dictionary = {
	"house": Vector2i(1, 1),
	"smithy": Vector2i(1, 1),
	"armor_shop": Vector2i(1, 1),
	"inn": Vector2i(2, 2),
	"church": Vector2i(2, 2),
	"item_shop": Vector2i(1, 1),
	"tavern": Vector2i(2, 2),
	"well": Vector2i(0, 0),
	"npc_house": Vector2i(1, 1),
	"village_hall": Vector2i(2, 3),
}


## Returns the box mesh/collision dimensions for a tile kind, or
## Vector3.ZERO when the kind is unsupported. A caller must treat
## Vector3.ZERO as an explicit failure marker (never a real tile size) and
## fail closed rather than instancing a degenerate box.
static func tile_dimensions(kind: String) -> Vector3:
	if not _TILE_DIMENSIONS.has(kind):
		return Vector3.ZERO
	return _TILE_DIMENSIONS[kind]


## Returns true when a tile kind is solid (gets merged wall collision), false
## for visual-only ground kinds and for unsupported kinds.
static func tile_is_solid(kind: String) -> bool:
	return _SOLID_TILE_KINDS.get(kind, false)


## Returns the PackedScene resource path for a structure kind, or an empty
## string when the kind is unsupported.
static func structure_scene_path(kind: String) -> String:
	if not _STRUCTURE_SCENE_PATHS.has(kind):
		return ""
	return _STRUCTURE_SCENE_PATHS[kind]


## Returns the collision footprint half-extent (in grid cells) for a structure
## kind, or Vector2i.ZERO for an unknown kind (blocks only the anchor cell).
static func structure_footprint(kind: String) -> Vector2i:
	return _STRUCTURE_FOOTPRINTS.get(kind, Vector2i.ZERO)


static func supported_tile_kinds() -> PackedStringArray:
	return PackedStringArray(_TILE_DIMENSIONS.keys())


static func supported_structure_kinds() -> PackedStringArray:
	return PackedStringArray(_STRUCTURE_SCENE_PATHS.keys())
