extends RefCounted
class_name TelemetryIngestService
## Slice 162 (telemetry map #282): composes the rate limiter, envelope
## builder, and sink into the single ingest path for client-originated
## telemetry batches. `server/server_main.gd`'s RPC handler forwards to this
## directly — kept as its own class so the real logic is testable without
## booting the full server, matching `server/character_service.gd`'s
## established pattern.
##
## `raw_events` are UNTRUSTED `{event_type, schema_version, payload}`
## Dictionaries from the client. Every correlation/timing field
## (`peer_id`, `character_id`, `emitted_at_unix`, `server_tick`) is supplied
## by the CALLER (resolved server-side from its own peer/session state), so a
## peer can never forge another identity's telemetry or backdate an event.
## Failures are always silent: a rejected rate limit, a malformed raw event,
## or a missing sink never surfaces to the client and never disconnects the
## peer (decision #284).

const TelemetryEventScript: Script = preload("res://shared/telemetry_event.gd")

var _sink: Object = null
var _rate_limiter: Object = null


func _init(sink: Object, rate_limiter: Object) -> void:
	_sink = sink
	_rate_limiter = rate_limiter


## Validates the batch against the rate limiter, then builds and emits one
## envelope per well-formed raw event. A malformed raw event (wrong types,
## missing fields) is skipped rather than aborting the rest of the batch.
## Returns only raw events whose validated envelopes were accepted by the sink.
func ingest_batch(peer_id: int, raw_events: Array, character_id: String, now_unix: int, server_tick: int) -> Array[Dictionary]:
	var accepted_events: Array[Dictionary] = []
	if _sink == null or _rate_limiter == null:
		return accepted_events
	if raw_events.is_empty():
		return accepted_events
	if not _rate_limiter.try_consume(peer_id, raw_events.size(), float(now_unix)):
		return accepted_events

	for raw_event: Variant in raw_events:
		if not (raw_event is Dictionary):
			continue
		var event_type: Variant = (raw_event as Dictionary).get("event_type")
		var schema_version: Variant = (raw_event as Dictionary).get("schema_version")
		var payload: Variant = (raw_event as Dictionary).get("payload", {})
		if not (event_type is String) or not (schema_version is int) or not (payload is Dictionary):
			continue
		var envelope: Dictionary = TelemetryEventScript.build(
			event_type, schema_version, now_unix, server_tick, peer_id, payload, "", character_id, ""
		)
		var emitted: Dictionary = _sink.emit(envelope)
		if emitted.get("outcome", "") == "ok":
			accepted_events.append((raw_event as Dictionary).duplicate(true))
	return accepted_events
