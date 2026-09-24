extends GutTest
## Experiment #1085: Canon-backed integration proof that bounded sector
## residency eviction never touches Canon. A real SQLite-backed
## CanonRepository canonicalizes a sector; SectorResidencyReconciler then
## schedules and completes its eviction from runtime residency once the
## active sector moves far enough away. Canon identity and revision (and the
## stored blueprint itself) must be value-for-value identical before and
## after, proving eviction only removes runtime/client residency.

const SqliteStoreScript: Script = preload("res://server/sqlite_store.gd")
const CanonRepositoryScript: Script = preload("res://server/canon_repository.gd")
const ReconcilerScript: Script = preload("res://shared/sector_residency_reconciler.gd")
const FixturesScript: Script = preload("res://scripts/sector_blueprint_fixtures.gd")
const TRACE_DIRECTORY: String = "res://logs/experiments"

var _relative_path: String = ""
var _store: SqliteStore = null
var _canon: CanonRepository = null
var _reconciler: SectorResidencyReconciler = null


func before_each() -> void:
	_relative_path = "test_sector_residency_canon_preservation_%d_%d.db" % [Time.get_ticks_usec(), randi()]
	_store = SqliteStoreScript.new()
	_store.open(_relative_path)
	_canon = CanonRepositoryScript.new(_store)
	_canon.ensure_schema()
	_reconciler = ReconcilerScript.new()


func after_each() -> void:
	if _store != null and _store.is_open():
		_store.close()
	for suffix: String in ["", "-wal", "-shm", "-journal"]:
		var path: String = ProjectSettings.globalize_path("user://%s%s" % [_relative_path, suffix])
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _canon_snapshot(sector_id: String) -> Dictionary:
	var loaded: Dictionary = _canon.get_canonical_sector(sector_id)
	assert_eq(loaded["outcome"], CanonRepositoryScript.OUTCOME_OK, "Canon must already exist for '%s'" % sector_id)
	return {
		"sector_id": loaded["sector"]["sector_id"],
		"revision": loaded["sector"]["schema_version"],
		"blueprint_sha1": JSON.stringify(loaded["sector"]["blueprint"]).sha1_text(),
		"created_at": loaded["sector"]["created_at"],
	}


func test_eviction_leaves_canon_value_for_value_unchanged() -> void:
	var blueprint: Dictionary = JSON.parse_string(FixturesScript.VALID_WITH_STRUCTURE)
	var canonicalize_result: Dictionary = _canon.canonicalize_blueprint(blueprint)
	assert_eq(canonicalize_result["outcome"], CanonRepositoryScript.OUTCOME_OK)
	var sector_id: String = blueprint["sector_id"]

	var before: Dictionary = _canon_snapshot(sector_id)

	# The active sector starts at the canonical sector, then moves far enough
	# away (Chebyshev distance >= 2) that it is scheduled for eviction.
	var resident: Array[Vector2i] = [Vector2i.ZERO]
	var reconciliation: Dictionary = _reconciler.reconcile(Vector2i(5, 5), resident, before)
	assert_true(
		(reconciliation["scheduled_eviction"] as Array).has(Vector2i.ZERO),
		"the far-away resident sector must be scheduled for eviction"
	)

	# Runtime/client unload completes asynchronously; duplicate completion
	# must be idempotent and must not touch Canon.
	var completion_one: Dictionary = _reconciler.complete_eviction(Vector2i.ZERO, Vector2i(5, 5), resident, before)
	var completion_two: Dictionary = _reconciler.complete_eviction(Vector2i.ZERO, Vector2i(5, 5), completion_one["resident_after"], before)
	assert_eq((completion_one["completed_eviction"] as Array), [Vector2i.ZERO])
	assert_true((completion_one["resident_after"] as Array).is_empty())
	assert_true((completion_two["resident_after"] as Array).is_empty())

	var after: Dictionary = _canon_snapshot(sector_id)

	assert_eq(after["sector_id"], before["sector_id"], "Canon identity is unchanged by eviction")
	assert_eq(after["revision"], before["revision"], "Canon revision is unchanged by eviction")
	assert_eq(after["blueprint_sha1"], before["blueprint_sha1"], "the stored blueprint is byte-for-byte unchanged")
	assert_eq(after["created_at"], before["created_at"], "Canon row identity (created_at) is unchanged")

	var timestamp_ms: int = int(Time.get_unix_time_from_system() * 1000.0)
	var evidence: Dictionary = {
		"experiment_id": 1085,
		"timestamp_ms": timestamp_ms,
		"sector_id": sector_id,
		"canon_identity_before": before["sector_id"],
		"canon_identity_after": after["sector_id"],
		"canon_revision_before": before["revision"],
		"canon_revision_after": after["revision"],
		"canon_blueprint_sha1_before": before["blueprint_sha1"],
		"canon_blueprint_sha1_after": after["blueprint_sha1"],
		"desired": (reconciliation["desired"] as Array).map(func(c: Vector2i) -> String: return "%d,%d" % [c.x, c.y]),
		"scheduled_eviction": (reconciliation["scheduled_eviction"] as Array).map(func(c: Vector2i) -> String: return "%d,%d" % [c.x, c.y]),
		"completed_eviction": (completion_one["completed_eviction"] as Array).map(func(c: Vector2i) -> String: return "%d,%d" % [c.x, c.y]),
		"duplicate_completion_idempotent": completion_one["completed_eviction"] == completion_two["completed_eviction"],
		"canon_untouched": after == before,
		"status": "PASS" if after == before else "MISMATCH",
	}
	var trace_path: String = "%s/exp_1085_sector_residency_canon_preservation_%d.json" % [TRACE_DIRECTORY, timestamp_ms]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TRACE_DIRECTORY))
	var trace_file: FileAccess = FileAccess.open(trace_path, FileAccess.WRITE)
	assert_not_null(trace_file, "the residency evidence artifact can be opened")
	trace_file.store_string(JSON.stringify(evidence, "\t"))
	trace_file.close()
