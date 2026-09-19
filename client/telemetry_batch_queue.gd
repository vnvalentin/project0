extends RefCounted
class_name TelemetryBatchQueue
## Slice 161 (telemetry map #282, decision #284): the client-side batching
## contract for outgoing telemetry. Accumulates events locally and reports
## when a bounded flush interval has elapsed, so the RPC entry point is
## called at a fixed cadence rather than once per event.
##
## Pure and side-effect free: no RPC, no networking, no reading the engine
## clock itself. Callers supply `now_msec` (typically `Time.get_ticks_msec()`)
## so this class stays deterministic and testable. Wiring this into
## `client/network_client.gd`'s actual send path is a follow-up slice.

## Flush cadence per decision #284: bounds RPC call frequency independent of
## how chatty a given event source is.
const FLUSH_INTERVAL_MSEC: int = 250

var _pending: Array[Dictionary] = []
var _last_flush_msec: int


func _init(now_msec: int = 0) -> void:
	_last_flush_msec = now_msec


## Adds one telemetry event Dictionary to the pending batch. Does not
## validate the event's shape — that is `shared/telemetry_event.gd`'s job,
## applied by the caller before or after enqueueing.
func enqueue(event: Dictionary) -> void:
	_pending.append(event)


## Number of events waiting for the next flush.
func pending_count() -> int:
	return _pending.size()


## True once FLUSH_INTERVAL_MSEC has elapsed since the last flush AND there is
## at least one pending event — an empty queue never triggers a flush.
func should_flush(now_msec: int) -> bool:
	if _pending.is_empty():
		return false
	return (now_msec - _last_flush_msec) >= FLUSH_INTERVAL_MSEC


## Drains and returns every pending event, and resets the flush clock to
## `now_msec`. Safe to call even when should_flush() would return false; the
## caller decides cadence.
func take_batch(now_msec: int) -> Array[Dictionary]:
	var batch: Array[Dictionary] = _pending.duplicate()
	_pending.clear()
	_last_flush_msec = now_msec
	return batch
