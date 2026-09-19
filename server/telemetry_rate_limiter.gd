extends RefCounted
class_name TelemetryRateLimiter
## Slice 161 (telemetry map #282, decision #284): the server-side per-peer
## rate-limiting contract for client-originated telemetry batches. A token
## bucket per `peer_id`: an over-budget batch is silently dropped (the peer
## is NEVER disconnected over telemetry) and counted, never itself turned
## into a telemetry event (that would be a telemetry-about-telemetry
## feedback loop).
##
## Pure and side-effect free: no RPC, no networking, no reading the engine
## clock itself. Callers supply `now_unix` so this class stays deterministic
## and testable. Wiring this into the actual
## `receive_client_telemetry_batch_on_server` RPC entry point is a follow-up
## slice.

## Bucket size: the burst of events a peer may submit in one go.
const CAPACITY: float = 50.0
## Steady-state replenishment rate, in events per second.
const REFILL_PER_SECOND: float = 10.0

## peer_id -> {"tokens": float, "last_refill_unix": float}
var _buckets: Dictionary = {}
## peer_id -> int, how many batches this peer has had rejected.
var _rate_limited_counts: Dictionary = {}


## Attempts to admit one batch of `event_count` events from `peer_id` at
## `now_unix`. Returns true and deducts `event_count` tokens if the bucket has
## enough budget; returns false (deducting nothing) and increments the
## peer's rejected-batch count otherwise. The whole batch is admitted or
## rejected as one unit — never partially trimmed.
func try_consume(peer_id: int, event_count: int, now_unix: float) -> bool:
	_refill(peer_id, now_unix)
	var bucket: Dictionary = _buckets[peer_id]
	if bucket["tokens"] >= event_count:
		bucket["tokens"] -= event_count
		return true
	_rate_limited_counts[peer_id] = int(_rate_limited_counts.get(peer_id, 0)) + 1
	return false


## How many batches have been rejected for `peer_id` so far (0 if never seen).
func rate_limited_count(peer_id: int) -> int:
	return int(_rate_limited_counts.get(peer_id, 0))


## Clears all state for `peer_id`. Callers should invoke this on disconnect
## so the bucket dictionaries do not grow without bound across reconnects.
func forget_peer(peer_id: int) -> void:
	_buckets.erase(peer_id)
	_rate_limited_counts.erase(peer_id)


func _refill(peer_id: int, now_unix: float) -> void:
	if not _buckets.has(peer_id):
		_buckets[peer_id] = {"tokens": CAPACITY, "last_refill_unix": now_unix}
		return
	var bucket: Dictionary = _buckets[peer_id]
	var elapsed: float = maxf(0.0, now_unix - float(bucket["last_refill_unix"]))
	bucket["tokens"] = minf(CAPACITY, float(bucket["tokens"]) + elapsed * REFILL_PER_SECOND)
	bucket["last_refill_unix"] = now_unix
