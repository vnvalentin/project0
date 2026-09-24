extends GutTest
## Public-seam tests for Experiment #1085's bounded sector residency
## reconciler. Pure logic: given an active signed sector coordinate and the
## current runtime-resident set, it must produce desired/retained/pending/
## scheduled-eviction/completed-eviction sets without ever touching Canon.
## Desired = active sector + its 8 Chebyshev-radius-1 neighbors (exactly 9).
## Scheduled eviction = every resident sector at Chebyshev distance >= 2.

const ReconcilerScript: Script = preload("res://shared/sector_residency_reconciler.gd")

const CANON_SNAPSHOT: Dictionary = {
	"sector_id": "sector-0-0",
	"revision": 3,
}


func test_desired_set_is_active_plus_exactly_eight_neighbors() -> void:
	var reconciler: SectorResidencyReconciler = ReconcilerScript.new()
	var result: Dictionary = reconciler.reconcile(Vector2i.ZERO, [], CANON_SNAPSHOT)

	assert_eq(result["active"], Vector2i.ZERO)
	assert_eq((result["desired"] as Array).size(), 9, "active sector plus its 8 Chebyshev-radius-1 neighbors")
	for offset_x: int in range(-1, 2):
		for offset_z: int in range(-1, 2):
			assert_true(
				(result["desired"] as Array).has(Vector2i(offset_x, offset_z)),
				"desired must include neighbor (%d, %d)" % [offset_x, offset_z]
			)
	assert_false(result["movement_blocked"], "residency reconciliation must never block movement")


func test_new_desired_sectors_with_no_prior_residency_are_pending() -> void:
	var reconciler: SectorResidencyReconciler = ReconcilerScript.new()
	var result: Dictionary = reconciler.reconcile(Vector2i.ZERO, [], CANON_SNAPSHOT)

	assert_eq((result["pending"] as Array).size(), 9, "every desired sector starts pending with no prior residency")
	assert_true((result["retained"] as Array).is_empty())
	assert_true((result["scheduled_eviction"] as Array).is_empty())
	assert_true((result["completed_eviction"] as Array).is_empty())


func test_resident_sectors_inside_desired_radius_are_retained_not_pending() -> void:
	var reconciler: SectorResidencyReconciler = ReconcilerScript.new()
	var resident: Array[Vector2i] = [Vector2i.ZERO, Vector2i(1, 0), Vector2i(-1, -1)]
	var result: Dictionary = reconciler.reconcile(Vector2i.ZERO, resident, CANON_SNAPSHOT)

	assert_eq((result["retained"] as Array).size(), 3)
	for coordinate: Vector2i in resident:
		assert_true((result["retained"] as Array).has(coordinate))
		assert_false((result["pending"] as Array).has(coordinate))
	assert_eq((result["pending"] as Array).size(), 6, "the remaining six desired sectors are still pending")


func test_resident_sectors_at_chebyshev_distance_two_or_more_are_scheduled_for_eviction() -> void:
	var reconciler: SectorResidencyReconciler = ReconcilerScript.new()
	var resident: Array[Vector2i] = [Vector2i(2, 0), Vector2i(0, -2), Vector2i(5, 5)]
	var result: Dictionary = reconciler.reconcile(Vector2i.ZERO, resident, CANON_SNAPSHOT)

	assert_eq((result["scheduled_eviction"] as Array).size(), 3)
	for coordinate: Vector2i in resident:
		assert_true((result["scheduled_eviction"] as Array).has(coordinate))
		assert_false((result["retained"] as Array).has(coordinate))


func test_active_sector_transition_retains_overlap_and_schedules_the_rest() -> void:
	var reconciler: SectorResidencyReconciler = ReconcilerScript.new()
	# Resident set is the full 3x3 block around the origin (a completed prior
	# reconciliation). The active sector then moves one step east.
	var resident: Array[Vector2i] = []
	for offset_x: int in range(-1, 2):
		for offset_z: int in range(-1, 2):
			resident.append(Vector2i(offset_x, offset_z))

	var result: Dictionary = reconciler.reconcile(Vector2i(1, 0), resident, CANON_SNAPSHOT)

	# The new desired 3x3 block is centered on (1,0): x in [0,2], z in [-1,1].
	assert_eq((result["desired"] as Array).size(), 9)
	assert_eq((result["retained"] as Array).size(), 6, "the six sectors shared by both 3x3 blocks are retained")
	assert_eq((result["pending"] as Array).size(), 3, "the three newly desired sectors (x=2 column) are pending")
	assert_eq((result["scheduled_eviction"] as Array).size(), 3, "the three sectors that fell out of range (x=-1 column) are scheduled")
	for coordinate: Vector2i in [Vector2i(-1, -1), Vector2i(-1, 0), Vector2i(-1, 1)]:
		assert_true((result["scheduled_eviction"] as Array).has(coordinate))
	for coordinate: Vector2i in [Vector2i(2, -1), Vector2i(2, 0), Vector2i(2, 1)]:
		assert_true((result["pending"] as Array).has(coordinate))


func test_duplicate_reconciliation_with_same_active_sector_is_idempotent() -> void:
	var reconciler: SectorResidencyReconciler = ReconcilerScript.new()
	var resident: Array[Vector2i] = [Vector2i.ZERO, Vector2i(1, 0)]
	var first: Dictionary = reconciler.reconcile(Vector2i.ZERO, resident, CANON_SNAPSHOT)
	var second: Dictionary = reconciler.reconcile(Vector2i.ZERO, resident, CANON_SNAPSHOT)

	assert_eq(first["desired"], second["desired"])
	assert_eq(first["retained"], second["retained"])
	assert_eq(first["pending"], second["pending"])
	assert_eq(first["scheduled_eviction"], second["scheduled_eviction"])
	assert_false(second["movement_blocked"])


func test_duplicate_unload_completion_is_idempotent_and_removes_only_runtime_residency() -> void:
	var reconciler: SectorResidencyReconciler = ReconcilerScript.new()
	var active: Vector2i = Vector2i.ZERO
	var evicted_coordinate: Vector2i = Vector2i(5, 5)

	var first_completion: Dictionary = reconciler.complete_eviction(evicted_coordinate, active, [evicted_coordinate], CANON_SNAPSHOT)
	assert_eq((first_completion["completed_eviction"] as Array), [evicted_coordinate])
	assert_true((first_completion["resident_after"] as Array).is_empty())
	assert_eq(first_completion["canon_identity"], CANON_SNAPSHOT["sector_id"], "eviction must not touch Canon identity")
	assert_eq(first_completion["canon_revision"], CANON_SNAPSHOT["revision"], "eviction must not touch Canon revision")

	# Replaying stale/duplicate completion for an already-evicted sector must
	# not error, double-count, or mutate an empty resident set further.
	var second_completion: Dictionary = reconciler.complete_eviction(evicted_coordinate, active, [], CANON_SNAPSHOT)
	assert_eq((second_completion["completed_eviction"] as Array), [evicted_coordinate])
	assert_true((second_completion["resident_after"] as Array).is_empty())
	assert_eq(second_completion["canon_identity"], CANON_SNAPSHOT["sector_id"])
	assert_eq(second_completion["canon_revision"], CANON_SNAPSHOT["revision"])


func test_duplicate_unload_completion_never_removes_a_newly_retained_sector() -> void:
	var reconciler: SectorResidencyReconciler = ReconcilerScript.new()
	# sector (5,5) was scheduled for eviction, then the player moved back so
	# the active sector is now (5,5) itself, before the stale completion for it
	# arrives. It is within the desired radius again and must not be removed.
	var active: Vector2i = Vector2i(5, 5)
	var resident_now: Array[Vector2i] = [Vector2i.ZERO, Vector2i(5, 5)]
	var completion: Dictionary = reconciler.complete_eviction(Vector2i(5, 5), active, resident_now, CANON_SNAPSHOT)

	assert_true(
		(completion["resident_after"] as Array).has(Vector2i(5, 5)),
		"a stale eviction completion must not remove a sector that is resident again"
	)
	assert_true((completion["completed_eviction"] as Array).is_empty(), "no eviction actually completed for a re-retained sector")


func test_movement_is_never_blocked_before_all_nine_desired_sectors_materialize() -> void:
	var reconciler: SectorResidencyReconciler = ReconcilerScript.new()
	var result: Dictionary = reconciler.reconcile(Vector2i.ZERO, [], CANON_SNAPSHOT)

	assert_eq((result["pending"] as Array).size(), 9, "none of the nine coordinates have materialized yet")
	assert_false(result["movement_blocked"], "movement must not wait on the nine desired sectors materializing")


func test_reconciliation_never_mutates_canon_identity_or_revision() -> void:
	var reconciler: SectorResidencyReconciler = ReconcilerScript.new()
	var result: Dictionary = reconciler.reconcile(Vector2i.ZERO, [Vector2i(9, 9)], CANON_SNAPSHOT)

	assert_eq(result["canon_identity_before"], CANON_SNAPSHOT["sector_id"])
	assert_eq(result["canon_revision_before"], CANON_SNAPSHOT["revision"])
	assert_eq(result["canon_identity_after"], CANON_SNAPSHOT["sector_id"])
	assert_eq(result["canon_revision_after"], CANON_SNAPSHOT["revision"])
