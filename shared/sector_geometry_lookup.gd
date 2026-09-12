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
## placeholder geometry.
const _TILE_DIMENSIONS: Dictionary = {
	"floor": Vector3(_TILE_FOOTPRINT, _FLOOR_CORRIDOR_HEIGHT, _TILE_FOOTPRINT),
	"corridor": Vector3(_TILE_FOOTPRINT, _FLOOR_CORRIDOR_HEIGHT, _TILE_FOOTPRINT),
	"wall": Vector3(_TILE_FOOTPRINT, _WALL_HEIGHT, _TILE_FOOTPRINT),
}

const _STRUCTURE_SCENE_PATHS: Dictionary = {
	"house": "res://client/structures/house.tscn",
	"smithy": "res://client/structures/smithy.tscn",
	"armor_shop": "res://client/structures/armor_shop.tscn",
	"inn": "res://client/structures/inn.tscn",
}


## Returns the box mesh/collision dimensions for a tile kind, or
## Vector3.ZERO when the kind is unsupported. A caller must treat
## Vector3.ZERO as an explicit failure marker (never a real tile size) and
## fail closed rather than instancing a degenerate box.
static func tile_dimensions(kind: String) -> Vector3:
	if not _TILE_DIMENSIONS.has(kind):
		return Vector3.ZERO
	return _TILE_DIMENSIONS[kind]


## Returns the PackedScene resource path for a structure kind, or an empty
## string when the kind is unsupported.
static func structure_scene_path(kind: String) -> String:
	if not _STRUCTURE_SCENE_PATHS.has(kind):
		return ""
	return _STRUCTURE_SCENE_PATHS[kind]


static func supported_tile_kinds() -> PackedStringArray:
	return PackedStringArray(_TILE_DIMENSIONS.keys())


static func supported_structure_kinds() -> PackedStringArray:
	return PackedStringArray(_STRUCTURE_SCENE_PATHS.keys())
