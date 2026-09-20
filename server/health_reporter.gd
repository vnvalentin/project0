extends RefCounted
class_name HealthReporter
## Slice 067: server-only runtime health-file writer. Turns a ServerHealth
## snapshot (the pure Slice 055 contract) into a small JSON file the container
## HEALTHCHECK reads. Server-only per CLAUDE.md's Shared Contracts rule — shared/
## and client/ MUST NEVER reference this class.
##
## It performs the only I/O the health path needs (resolve a path, write a file)
## and nothing else: snapshot validation stays in ServerHealth so this stays a
## thin, fail-closed adapter. A write failure is a returned error, never a crash.

const OUTCOME_OK: String = "ok"
const OUTCOME_ERROR: String = "error"

## Default location for dev/local runs; the container overrides this with an
## absolute path via PROJECT0_HEALTH_FILE so the healthcheck can find it.
const DEFAULT_HEALTH_FILE_PATH: String = "user://health.json"
const DEFAULT_OPS_SNAPSHOT_FILE_PATH: String = "user://ops_snapshot.json"


## Public seam. Resolves the health-file path from a raw configuration string
## (e.g. the PROJECT0_HEALTH_FILE environment value). Empty/whitespace yields the
## default; any non-empty value is used verbatim (trimmed) so an absolute
## container path is honored.
static func resolve_health_file_path(raw: String) -> String:
	var trimmed: String = raw.strip_edges()
	if trimmed.is_empty():
		return DEFAULT_HEALTH_FILE_PATH
	return trimmed


## Public seam. Writes a ServerHealth-validated snapshot to `path` as JSON.
## Returns { "outcome": OUTCOME_OK } or { "outcome": OUTCOME_ERROR, "detail": ... }
## when the file cannot be opened — fail-closed, never raising. The file is tiny
## and rewritten every refresh; the healthcheck tolerates a transient read via
## its retry/staleness window.
static func write_snapshot(path: String, snapshot: Dictionary) -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {"outcome": OUTCOME_ERROR, "detail": "cannot open %s: %d" % [path, FileAccess.get_open_error()]}
	file.store_string(JSON.stringify(snapshot))
	file.close()
	return {"outcome": OUTCOME_OK}


static func write_ops_snapshot(path: String, snapshot: Dictionary) -> Dictionary:
	var temporary_path: String = path + ".tmp"
	var file: FileAccess = FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		return {"outcome": OUTCOME_ERROR, "detail": "cannot open %s: %d" % [temporary_path, FileAccess.get_open_error()]}
	file.store_string(JSON.stringify(snapshot))
	file.flush()
	file.close()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var renamed: Error = DirAccess.rename_absolute(
		ProjectSettings.globalize_path(temporary_path),
		ProjectSettings.globalize_path(path)
	)
	if renamed != OK:
		return {"outcome": OUTCOME_ERROR, "detail": "cannot publish %s: %s" % [path, error_string(renamed)]}
	return {"outcome": OUTCOME_OK}
