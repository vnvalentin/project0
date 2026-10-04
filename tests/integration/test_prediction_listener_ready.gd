extends GutTest

const ReadyCodec = preload("res://tests/fixtures/prediction_listener_ready.gd")
const AUTHORED_RUN: String = "authored_fixture"
const AUTHORED_REVISION: String = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
const AUTHORED_PORT: int = 12345

var _namespace: String = ""
var _namespace_chain: Array[String] = []
var _ready_directory: String = ""
var _ready_chain: Array[String] = []
var _owned_files: Dictionary = {}


func test_authored_closed_readiness_round_trips() -> void:
	var bytes: String = ReadyCodec.encode_ready(AUTHORED_RUN, AUTHORED_REVISION, AUTHORED_PORT)
	var decoded: Dictionary = ReadyCodec.decode_ready(bytes, AUTHORED_RUN, AUTHORED_REVISION)
	assert_true(decoded["passed"] == true and decoded["port"] == AUTHORED_PORT, "authored closed readiness qualifies")


func test_duplicate_ready_keys_are_rejected_even_when_values_agree() -> void:
	var bytes: String = ReadyCodec.encode_ready(AUTHORED_RUN, AUTHORED_REVISION, AUTHORED_PORT)
	for replacement: String in ["\"schema_version\":1,\"schema_version\":1", "\"schema_version\":2,\"schema_version\":1"]:
		var duplicate: String = bytes.replace("\"schema_version\":1", replacement)
		assert_true(ReadyCodec.decode_ready(duplicate, AUTHORED_RUN, AUTHORED_REVISION)["passed"] == false, "duplicate keys never qualify readiness")


func test_equivalent_float_and_exponent_spellings_are_rejected() -> void:
	var bytes: String = ReadyCodec.encode_ready(AUTHORED_RUN, AUTHORED_REVISION, AUTHORED_PORT)
	for spelling: String in ["12345.0", "1.2345e4"]:
		var altered: String = bytes.replace("\"port\":12345", "\"port\":" + spelling)
		assert_true(ReadyCodec.decode_ready(altered, AUTHORED_RUN, AUTHORED_REVISION)["passed"] == false, "noncanonical numeric readiness is rejected")


func test_foreign_run_and_source_never_qualify() -> void:
	var bytes: String = ReadyCodec.encode_ready(AUTHORED_RUN, AUTHORED_REVISION, AUTHORED_PORT)
	assert_true(ReadyCodec.decode_ready(bytes, "foreign_fixture", AUTHORED_REVISION)["passed"] == false, "foreign run readiness is rejected")
	assert_true(ReadyCodec.decode_ready(bytes, AUTHORED_RUN, "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb")["passed"] == false, "foreign source readiness is rejected")


func test_extra_fields_wrong_types_and_trailing_data_are_rejected() -> void:
	var bytes: String = ReadyCodec.encode_ready(AUTHORED_RUN, AUTHORED_REVISION, AUTHORED_PORT)
	var invalid: Array[String] = [
		bytes.replace("\"port\":12345", "\"port\":true"),
		bytes.replace("\"schema_version\":1", "\"schema_version\":true"),
		bytes.replace("{", "{\"extra\":true,"),
		bytes + " ",
		"{",
	]
	for altered: String in invalid:
		assert_true(ReadyCodec.decode_ready(altered, AUTHORED_RUN, AUTHORED_REVISION)["passed"] == false, "malformed or open readiness is rejected")


func _create_ready_namespace() -> bool:
	var user_directory: String = ProjectSettings.globalize_path("user://").trim_suffix("/")
	var parent_chain: Array[String] = ReadyCodec.ordinary_chain(user_directory)
	if parent_chain.is_empty():
		return false
	var candidate: String = user_directory.path_join("listener-codec-fixture-%d" % Time.get_ticks_usec())
	if DirAccess.make_dir_absolute(candidate) != OK:
		return false
	_namespace = candidate
	_namespace_chain = ReadyCodec.ordinary_chain(_namespace)
	var expected_namespace: Array[String] = parent_chain.duplicate()
	expected_namespace.append(_namespace)
	if _namespace_chain != expected_namespace:
		return false
	var ready_candidate: String = _namespace.path_join("ready")
	if DirAccess.make_dir_absolute(ready_candidate) != OK:
		return false
	_ready_directory = ready_candidate
	_ready_chain = ReadyCodec.ordinary_chain(_ready_directory)
	var expected_ready: Array[String] = _namespace_chain.duplicate()
	expected_ready.append(_ready_directory)
	return _ready_chain == expected_ready


func _write_owned(leaf: String, bytes: String) -> bool:
	if ReadyCodec.ordinary_chain(_ready_directory) != _ready_chain:
		return false
	var file: FileAccess = FileAccess.open(_ready_directory.path_join(leaf), FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(bytes)
	file.flush()
	var written: bool = file.get_error() == OK
	file.close()
	if not written:
		return false
	_owned_files[leaf] = FileAccess.get_sha256(_ready_directory.path_join(leaf))
	return true


func _publish_owned(bytes: String) -> bool:
	var published: bool = ReadyCodec.publish_ready(_ready_directory, _ready_chain, bytes)
	if published:
		_owned_files[ReadyCodec.READY_LEAF] = FileAccess.get_sha256(_ready_directory.path_join(ReadyCodec.READY_LEAF))
	return published


func test_extra_leaf_rejects_final_readiness_and_preserves_foreign_bytes() -> void:
	var created: bool = _create_ready_namespace()
	assert_true(created, "owned codec namespace exists")
	if not created:
		return
	var bytes: String = ReadyCodec.encode_ready(AUTHORED_RUN, AUTHORED_REVISION, AUTHORED_PORT)
	assert_true(_publish_owned(bytes), "final readiness is published")
	assert_true(_write_owned("foreign.fixture", "owned foreign fixture"), "controlled extra leaf exists")
	assert_true(ReadyCodec.read_ready(_ready_directory, _ready_chain).is_empty(), "extra leaf never qualifies final readiness")
	assert_true(FileAccess.get_sha256(_ready_directory.path_join("foreign.fixture")) == _owned_files["foreign.fixture"], "rejected extra leaf is preserved")


func test_changed_final_readiness_rejects_frozen_bytes_and_source_run() -> void:
	var created: bool = _create_ready_namespace()
	assert_true(created, "owned codec namespace exists")
	if not created:
		return
	var bytes: String = ReadyCodec.encode_ready(AUTHORED_RUN, AUTHORED_REVISION, AUTHORED_PORT)
	assert_true(_publish_owned(bytes), "final readiness is published")
	var frozen: String = ReadyCodec.read_ready(_ready_directory, _ready_chain)
	assert_true(frozen == bytes, "source readiness is frozen")
	var changed: String = ReadyCodec.encode_ready("foreign_fixture", AUTHORED_REVISION, AUTHORED_PORT)
	assert_true(_write_owned(ReadyCodec.READY_LEAF, changed), "controlled changed readiness exists")
	var observed: String = ReadyCodec.read_ready(_ready_directory, _ready_chain)
	assert_true(observed != frozen and ReadyCodec.decode_ready(observed, AUTHORED_RUN, AUTHORED_REVISION)["passed"] == false, "changed readiness cannot qualify the frozen gate")


func test_pending_only_readiness_remains_unpublished() -> void:
	var created: bool = _create_ready_namespace()
	assert_true(created, "owned codec namespace exists")
	if not created:
		return
	var bytes: String = ReadyCodec.encode_ready(AUTHORED_RUN, AUTHORED_REVISION, AUTHORED_PORT)
	assert_true(_write_owned(ReadyCodec.PENDING_LEAF, bytes), "controlled pending leaf exists")
	assert_true(ReadyCodec.read_ready(_ready_directory, _ready_chain).is_empty(), "pending leaf never qualifies final readiness")
	assert_true(not FileAccess.file_exists(_ready_directory.path_join(ReadyCodec.READY_LEAF)), "pending state remains unpublished")


func test_publication_collision_preserves_existing_leaf() -> void:
	var created: bool = _create_ready_namespace()
	assert_true(created, "owned codec namespace exists")
	if not created:
		return
	assert_true(_write_owned(ReadyCodec.READY_LEAF, "owned prior fixture"), "controlled final collision exists")
	var frozen: String = _owned_files[ReadyCodec.READY_LEAF]
	var bytes: String = ReadyCodec.encode_ready(AUTHORED_RUN, AUTHORED_REVISION, AUTHORED_PORT)
	assert_true(not ReadyCodec.publish_ready(_ready_directory, _ready_chain, bytes), "publication collision is rejected")
	assert_true(FileAccess.get_sha256(_ready_directory.path_join(ReadyCodec.READY_LEAF)) == frozen, "prior final leaf is preserved")
	assert_true(not FileAccess.file_exists(_ready_directory.path_join(ReadyCodec.PENDING_LEAF)), "rejected publication creates no pending leaf")


func after_each() -> void:
	if _namespace.is_empty():
		return
	var qualified: bool = ReadyCodec.ordinary_chain(_namespace) == _namespace_chain
	if not _ready_directory.is_empty():
		qualified = qualified and ReadyCodec.ordinary_chain(_ready_directory) == _ready_chain
		var opened: DirAccess = DirAccess.open(_ready_directory)
		qualified = qualified and opened != null
		if qualified:
			opened.include_hidden = true
			qualified = opened.list_dir_begin() == OK
			var observed: Array[String] = []
			while qualified:
				var entry: String = opened.get_next()
				if entry.is_empty():
					break
				if observed.size() >= 3 or opened.current_is_dir() or opened.is_link(entry) \
					or not _owned_files.has(entry) \
					or FileAccess.get_sha256(_ready_directory.path_join(entry)) != _owned_files[entry]:
					qualified = false
					break
				observed.append(entry)
			opened.list_dir_end()
			qualified = qualified and observed.size() == _owned_files.size()
			if qualified:
				for entry: String in observed:
					if ReadyCodec.ordinary_chain(_ready_directory) != _ready_chain \
						or opened.is_link(entry) \
						or FileAccess.get_sha256(_ready_directory.path_join(entry)) != _owned_files[entry] \
						or DirAccess.remove_absolute(_ready_directory.path_join(entry)) != OK:
						qualified = false
						break
			if qualified:
				qualified = ReadyCodec.ordinary_chain(_ready_directory) == _ready_chain \
					and DirAccess.remove_absolute(_ready_directory) == OK
	if qualified:
		var namespace_directory: DirAccess = DirAccess.open(_namespace)
		qualified = namespace_directory != null and ReadyCodec.ordinary_chain(_namespace) == _namespace_chain
		if qualified:
			namespace_directory.include_hidden = true
			qualified = namespace_directory.list_dir_begin() == OK
			if qualified:
				qualified = namespace_directory.get_next().is_empty()
				namespace_directory.list_dir_end()
		if qualified:
			qualified = ReadyCodec.ordinary_chain(_namespace) == _namespace_chain \
				and DirAccess.remove_absolute(_namespace) == OK
	assert_true(qualified, "owned codec fixture cleanup qualifies")
	_namespace = ""
	_namespace_chain.clear()
	_ready_directory = ""
	_ready_chain.clear()
	_owned_files.clear()
