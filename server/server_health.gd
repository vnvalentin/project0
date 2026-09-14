extends RefCounted
class_name ServerHealth
## Slice 055: pure, versioned server health and tick contract. Server-only per
## CLAUDE.md's Shared Contracts rule — shared/ and client/ MUST NEVER reference
## this class. It reads no clock, file, socket, or global state: every input is
## supplied by the caller so the contract is deterministic and unit-testable.
##
## Scope: this is the CONTRACT SEAM ONLY (mirroring Slice 038's engine-only
## SqliteStore). It resolves a bounded simulation tick rate and builds a
## bounded, fail-closed health snapshot. It does NOT set the engine tick, write
## a health file, or open any endpoint — those are later container/operator
## slices per docs/slices/055-server-fixed-tick-and-health-contract.md.

const SNAPSHOT_SCHEMA_VERSION: int = 1

const OUTCOME_OK: String = "ok"
const OUTCOME_INVALID: String = "invalid"

const STATUS_STARTING: String = "starting"
const STATUS_HEALTHY: String = "healthy"
const STATUS_DEGRADED: String = "degraded"
const STATUS_STOPPING: String = "stopping"

## CLAUDE.md's Runtime Ownership requires a bounded 20-30 Hz authoritative tick.
const MIN_TICK_RATE: int = 20
const MAX_TICK_RATE: int = 30
const DEFAULT_TICK_RATE: int = 30

const VALID_STATUSES: Array[String] = [
	STATUS_STARTING,
	STATUS_HEALTHY,
	STATUS_DEGRADED,
	STATUS_STOPPING,
]


## Public seam. Resolves the authoritative simulation tick rate from a raw
## configuration string (e.g. an environment variable value). Empty or
## non-integer input yields DEFAULT_TICK_RATE; any parsed integer is clamped
## into the bounded [MIN_TICK_RATE, MAX_TICK_RATE] range so the running server
## can never be driven at an out-of-contract cadence.
static func resolve_tick_rate(raw: String) -> int:
	var trimmed: String = raw.strip_edges()
	if trimmed.is_empty() or not trimmed.is_valid_int():
		return DEFAULT_TICK_RATE
	return clampi(trimmed.to_int(), MIN_TICK_RATE, MAX_TICK_RATE)


## Public seam. Builds a bounded, versioned health snapshot from explicit
## inputs. Returns { "outcome": OUTCOME_OK, "snapshot": Dictionary } on success,
## or { "outcome": OUTCOME_INVALID, "detail": String } (no snapshot) when any
## field is out of contract — fail-closed, no partial snapshot.
##
## Expected inputs: status (a VALID_STATUSES value), tick_rate (int in
## [MIN_TICK_RATE, MAX_TICK_RATE]), uptime_seconds (finite float >= 0),
## server_tick (int >= 0), connected_peers (int in [0, max_peers]), max_peers
## (int > 0), app_schema_version (int > 0), timestamp (int >= 0, supplied by the
## caller — never read from a clock here).
static func build_snapshot(inputs: Dictionary) -> Dictionary:
	var status: Variant = inputs.get("status")
	if not (status is String) or not VALID_STATUSES.has(status):
		return _reject("status must be one of %s." % [VALID_STATUSES])

	var tick_rate: Variant = inputs.get("tick_rate")
	if not (tick_rate is int) or (tick_rate as int) < MIN_TICK_RATE or (tick_rate as int) > MAX_TICK_RATE:
		return _reject("tick_rate must be an int in [%d, %d]." % [MIN_TICK_RATE, MAX_TICK_RATE])

	var uptime_seconds: Variant = inputs.get("uptime_seconds")
	if not (uptime_seconds is float) or not is_finite(uptime_seconds) or (uptime_seconds as float) < 0.0:
		return _reject("uptime_seconds must be a finite float >= 0.")

	var server_tick: Variant = inputs.get("server_tick")
	if not (server_tick is int) or (server_tick as int) < 0:
		return _reject("server_tick must be an int >= 0.")

	var max_peers: Variant = inputs.get("max_peers")
	if not (max_peers is int) or (max_peers as int) <= 0:
		return _reject("max_peers must be an int > 0.")

	var connected_peers: Variant = inputs.get("connected_peers")
	if not (connected_peers is int) or (connected_peers as int) < 0 or (connected_peers as int) > (max_peers as int):
		return _reject("connected_peers must be an int in [0, max_peers].")

	var app_schema_version: Variant = inputs.get("app_schema_version")
	if not (app_schema_version is int) or (app_schema_version as int) <= 0:
		return _reject("app_schema_version must be an int > 0.")

	var timestamp: Variant = inputs.get("timestamp")
	if not (timestamp is int) or (timestamp as int) < 0:
		return _reject("timestamp must be an int >= 0.")

	return {
		"outcome": OUTCOME_OK,
		"snapshot": {
			"snapshot_schema_version": SNAPSHOT_SCHEMA_VERSION,
			"status": status,
			"tick_rate": tick_rate,
			"uptime_seconds": uptime_seconds,
			"server_tick": server_tick,
			"connected_peers": connected_peers,
			"max_peers": max_peers,
			"app_schema_version": app_schema_version,
			"timestamp": timestamp,
		},
	}


static func _reject(detail: String) -> Dictionary:
	return {"outcome": OUTCOME_INVALID, "detail": detail}
