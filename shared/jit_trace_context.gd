extends RefCounted
class_name JitTraceContext

const CanonEntityGuidScript: Script = preload("res://shared/canon_entity_guid.gd")


static func root(peer_id: int, sector_id: String) -> Dictionary:
	var trigger_usec: int = Time.get_ticks_usec()
	var trace_name: String = "jit:%d:%s:%d" % [peer_id, sector_id, trigger_usec]
	var spatial_guid: String = CanonEntityGuidScript.uuid_v5(
		CanonEntityGuidScript.NAMESPACE_URL_UUID,
		"project0:sector:%s" % sector_id,
	)
	return {
		"trace_id": CanonEntityGuidScript.uuid_v5(CanonEntityGuidScript.NAMESPACE_DNS_UUID, trace_name),
		"generation_started_usec": trigger_usec,
		"span_id": _uuid_v4(),
		"parent_span_id": null,
		"event_type": "player_trigger_event",
		"sector_id": sector_id,
		"spatial_guid": spatial_guid,
		"timestamp_ms": int(Time.get_unix_time_from_system() * 1000.0),
		"duration_ms": 0.0,
		"status": "OK",
	}


static func child(parent: Dictionary, event_type: String) -> Dictionary:
	var timestamp_ms: int = maxi(
		int(Time.get_unix_time_from_system() * 1000.0),
		int(parent.get("timestamp_ms", 0)) + 1,
	)
	return {
		"trace_id": String(parent.get("trace_id", "")),
		"span_id": _uuid_v4(),
		"parent_span_id": parent.get("span_id"),
		"event_type": event_type,
		"sector_id": String(parent.get("sector_id", "")),
		"spatial_guid": String(parent.get("spatial_guid", "")),
		"timestamp_ms": timestamp_ms,
		"duration_ms": 0.0,
		"status": "OK",
	}


static func _uuid_v4() -> String:
	var bytes: PackedByteArray = Crypto.new().generate_random_bytes(16)
	bytes[6] = (bytes[6] & 0x0f) | 0x40
	bytes[8] = (bytes[8] & 0x3f) | 0x80
	var hex: String = bytes.hex_encode()
	return "%s-%s-%s-%s-%s" % [
		hex.substr(0, 8),
		hex.substr(8, 4),
		hex.substr(12, 4),
		hex.substr(16, 4),
		hex.substr(20, 12),
	]