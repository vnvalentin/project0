extends RefCounted
class_name WorldScale
## Imperial world-scale measurement contract (Slice 035). The single, versioned
## source of truth for how in-engine world units map to real-world Imperial
## distances: 1 world unit = 1 yard. Pure data + stateless conversion helpers,
## like the other shared value contracts (shared/combat_contracts.gd,
## shared/sector_geometry_lookup.gd) — no scene tree, no network I/O, no
## authority. Both client and server read it identically. See
## docs/adr/0003-imperial-world-scale.md and
## docs/slices/036-world-scale-measurement-contract.md.
##
## Base gameplay magnitudes (move speed, monster radii) are expressed directly
## in world units and stay literal — because 1 unit = 1 yard, routing them
## through this contract would be an identity no-op. This module is for callers
## that genuinely cross units (HUD distance readouts, Sector-span math).

## Bumped whenever a scale constant below changes, so scale-derived telemetry
## and persisted records can be stamped with the scale they were produced under.
const SCALE_VERSION: int = 1

## The Imperial unit one world unit represents. Distances read in feet/yards up
## close and miles at the region tier.
const UNIT_LABEL: String = "yard"
const FEET_PER_YARD: float = 3.0
const YARDS_PER_MILE: float = 1760.0

## The fine walkable blueprint Tile is one world unit (1 yard) square.
const TILE_EDGE_UNITS: float = 1.0

## The nominal Sector (region) span: a quarter mile = 440 units. Tunable data —
## raising it (toward 1 mile = 1760) is a scale change, so bump SCALE_VERSION
## when it moves. A Sector is a region container; this span is not a mandate to
## tile every yard (see ADR 0003).
const SECTOR_EDGE_UNITS: float = 440.0


## Converts a distance in world units (yards) to feet.
static func units_to_feet(units: float) -> float:
	return units * FEET_PER_YARD


## Converts a distance in world units (yards) to miles.
static func units_to_miles(units: float) -> float:
	return units / YARDS_PER_MILE


## Converts a distance in miles to world units (yards).
static func miles_to_units(miles: float) -> float:
	return miles * YARDS_PER_MILE
