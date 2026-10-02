extends RefCounted
## #1376 experiment only: delegate unchanged public repository calls on original handles.

class ObservedCanon extends CanonRepository:
	var _recorder: RefCounted
	func _init(store: SqliteStore, recorder: RefCounted) -> void:
		super(store)
		_recorder = recorder
	func get_canonical_sector(sector_id: Variant) -> Dictionary:
		var started: int = Time.get_ticks_usec()
		var result: Dictionary = super(sector_id)
		_recorder.call("observe_child", "canon_read", started)
		return result

class ObservedJourney extends JourneyRepository:
	var _recorder: RefCounted
	func _init(store: SqliteStore, recorder: RefCounted) -> void:
		super(store)
		_recorder = recorder
	func save(record: Dictionary) -> Dictionary:
		var started: int = Time.get_ticks_usec()
		var result: Dictionary = super(record)
		_recorder.call("observe_child", "journey_save", started)
		return result

var _host: WeakRef
var _canon: WeakRef
var _journey: WeakRef
var _original_canon_store: SqliteStore
var _original_journey_store: SqliteStore
var _depth: int = 0
var _iteration: Dictionary = _empty_iteration()

func install(host: Object) -> bool:
	var original_canon: Object = host.get("_canon_repository")
	var original_journey: Object = host.get("_journey_repository")
	if original_canon == null or original_journey == null or host.get("_canon_generation_coordinator") == null or host.get("_journey_registry") == null:
		return false
	_original_canon_store = original_canon.get("_store")
	_original_journey_store = original_journey.get("_store")
	if _original_canon_store == null or _original_journey_store == null:
		return false
	var canon: Object = ObservedCanon.new(_original_canon_store, self)
	var journey: Object = ObservedJourney.new(_original_journey_store, self)
	_host = weakref(host)
	_canon = weakref(canon)
	_journey = weakref(journey)
	host.set("_canon_repository", canon)
	host.set("_journey_repository", journey)
	host.get("_canon_generation_coordinator").set_canonicalize_callback(Callable(canon, "canonicalize_blueprint"))
	host.get("_journey_registry").set_repository(journey)
	return bindings_qualified()

func binding_evidence() -> Dictionary:
	if _host == null or _canon == null or _journey == null:
		return {}
	var host: Object = _host.get_ref()
	var canon: Object = _canon.get_ref()
	var journey: Object = _journey.get_ref()
	if host == null or canon == null or journey == null:
		return {}
	var coordinator: Object = host.get("_canon_generation_coordinator")
	var registry: Object = host.get("_journey_registry")
	return {"server_canon": host.get("_canon_repository") == canon,
		"server_journey": host.get("_journey_repository") == journey,
		"coordinator": coordinator != null and coordinator.get("_canonicalize") == Callable(canon, "canonicalize_blueprint"),
		"registry": registry != null and registry.get("_repository") == journey,
		"canon_store_original": canon.get("_store") == _original_canon_store and _original_canon_store.is_open(),
		"journey_store_original": journey.get("_store") == _original_journey_store and _original_journey_store.is_open()}

func bindings_qualified() -> bool:
	var bindings: Dictionary = binding_evidence()
	return bindings.size() == 6 and bindings.values().all(func(value: Variant) -> bool: return value == true)

func begin_checkpoint() -> int:
	_depth += 1
	return Time.get_ticks_usec()

func end_checkpoint(started: int) -> void:
	_iteration["checkpoint_calls"] += 1
	_iteration["duration_usec"] += Time.get_ticks_usec() - started
	_depth -= 1

func observe_child(name: String, started: int) -> void:
	if _depth <= 0:
		return
	var duration: int = Time.get_ticks_usec() - started
	_iteration[name]["calls"] += 1
	_iteration[name]["duration_usec"] += duration

func take_iteration() -> Dictionary:
	var result: Dictionary = _iteration
	_iteration = _empty_iteration()
	return result

static func _empty_iteration() -> Dictionary:
	return {"checkpoint_calls": 0, "duration_usec": 0,
		"canon_read": {"calls": 0, "duration_usec": 0},
		"journey_save": {"calls": 0, "duration_usec": 0}}
