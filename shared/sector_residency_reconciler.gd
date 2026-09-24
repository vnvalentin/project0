extends RefCounted
class_name SectorResidencyReconciler
## Experiment #1085: pure-logic bounded sector residency owner. Given an
## active signed sector coordinate and the current runtime-resident set, this
## reconciler produces the desired/retained/pending/scheduled-eviction sets
## for the public seam:
##   active-sector transition -> desired residency reconciliation ->
##   existing-Canon load or pending-generation state ->
##   asynchronous runtime/client unload completion -> durable Canon observation.
##
## No DB handle, no async, no mutation of Canon. Desired is always the active
## sector plus its 8 Chebyshev-radius-1 neighbors (exactly 9 coordinates).
## Scheduled eviction is every resident sector at Chebyshev distance >= 2 from
## the active sector. Completed eviction removes only runtime/client
## residency; any Canon identity/revision passed in is echoed back unchanged,
## never mutated, proving eviction cannot touch Canon.
##
## Builds on top of, and does not change, the existing placement/identity
## contract (shared/sector_identity.gd, server/sector_boundary_detector.gd).

const EVICTION_CHEBYSHEV_DISTANCE: int = 2


## Produces the residency reconciliation bundle for one active-sector
## transition. `resident_coordinates` is the current runtime-resident set.
## `canon_snapshot` is an already-observed Canon identity/revision Dictionary
## (at minimum `sector_id` and `revision`-shaped keys); it is read, never
## written. Pure and idempotent: replaying the same inputs returns an
## equivalent bundle. `movement_blocked` is always false — residency
## reconciliation must never gate movement on the nine desired sectors
## materializing.
func reconcile(active: Vector2i, resident_coordinates: Array, canon_snapshot: Dictionary) -> Dictionary:
	var desired: Array[Vector2i] = _desired_set(active)
	var resident_set: Dictionary = _to_lookup(resident_coordinates)

	var retained: Array[Vector2i] = []
	var pending: Array[Vector2i] = []
	for coordinate: Vector2i in desired:
		if resident_set.has(coordinate):
			retained.append(coordinate)
		else:
			pending.append(coordinate)

	var desired_set: Dictionary = _to_lookup(desired)
	var scheduled_eviction: Array[Vector2i] = []
	for coordinate: Vector2i in resident_coordinates:
		if not desired_set.has(coordinate):
			scheduled_eviction.append(coordinate)

	var canon_identity: Variant = canon_snapshot.get("sector_id")
	var canon_revision: Variant = canon_snapshot.get("revision")

	return {
		"active": active,
		"desired": desired,
		"retained": retained,
		"pending": pending,
		"scheduled_eviction": scheduled_eviction,
		"completed_eviction": [],
		"movement_blocked": false,
		"canon_identity_before": canon_identity,
		"canon_revision_before": canon_revision,
		"canon_identity_after": canon_identity,
		"canon_revision_after": canon_revision,
	}


## Completes asynchronous runtime/client unload for one evicted coordinate,
## relative to the sector that is active when the completion lands. Removes the
## coordinate from the runtime-resident set passed in only when it is still
## outside the desired radius of `active` (Chebyshev distance >= 2); the
## returned `canon_identity`/`canon_revision` are the same values handed in,
## echoed back unchanged. Idempotent: replaying a stale completion for a sector
## already absent from `resident_coordinates` reports it as completed again
## without error. A stale completion racing a fresh retention loses — a sector
## that has moved back within Chebyshev distance 1 of `active` is newly retained
## and is never removed, even though it is still resident.
func complete_eviction(evicted: Vector2i, active: Vector2i, resident_coordinates: Array, canon_snapshot: Dictionary) -> Dictionary:
	var completed_eviction: Array[Vector2i] = []
	var resident_after: Array[Vector2i] = []

	if _chebyshev_distance(evicted, active) <= 1:
		# The sector is newly retained (the player moved back in range before
		# this stale completion arrived) — retention wins, nothing is evicted.
		for coordinate: Vector2i in resident_coordinates:
			resident_after.append(coordinate)
	else:
		completed_eviction.append(evicted)
		for coordinate: Vector2i in resident_coordinates:
			if coordinate != evicted:
				resident_after.append(coordinate)

	return {
		"completed_eviction": completed_eviction,
		"resident_after": resident_after,
		"canon_identity": canon_snapshot.get("sector_id"),
		"canon_revision": canon_snapshot.get("revision"),
	}


func _desired_set(active: Vector2i) -> Array[Vector2i]:
	var desired: Array[Vector2i] = []
	for offset_x: int in range(-1, 2):
		for offset_z: int in range(-1, 2):
			desired.append(active + Vector2i(offset_x, offset_z))
	return desired


func _chebyshev_distance(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


func _to_lookup(coordinates: Array) -> Dictionary:
	var lookup: Dictionary = {}
	for coordinate: Variant in coordinates:
		lookup[coordinate] = true
	return lookup
