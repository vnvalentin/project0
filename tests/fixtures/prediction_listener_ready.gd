extends RefCounted
## Fixture-only closed readiness and ordinary filesystem observations.
## Fresh namespace ownership comes from the caller. No O_EXCL, atomic custody,
## inode attestation or hostile same-path replacement guarantee is claimed.

const READY_LEAF: String = "ready.json"
const PENDING_LEAF: String = "ready.pending"
const MAX_BYTES: int = 512


static func valid_run_id(value: String) -> bool:
	if value.is_empty() or value.length() > 128:
		return false
	for character: String in value:
		if not "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-".contains(character):
			return false
	return true


static func valid_revision(value: String) -> bool:
	if value.length() != 40:
		return false
	for character: String in value:
		if not "0123456789abcdef".contains(character):
			return false
	return true


static func encode_ready(run_id: String, revision: String, port: int) -> String:
	if not valid_run_id(run_id) or not valid_revision(revision) or port < 1 or port > 65535:
		return ""
	return JSON.stringify({
		"schema_version": 1, "run_id": run_id, "source_revision": revision,
		"state": "ready", "port": port,
	}, "", true)


static func decode_ready(bytes: String, run_id: String, revision: String) -> Dictionary:
	var rejected: Dictionary = {"passed": false, "outcome": "invalid_record", "port": null}
	if not valid_run_id(run_id) or not valid_revision(revision):
		return {"passed": false, "outcome": "source_unqualified", "port": null}
	if bytes.is_empty() or bytes.to_utf8_buffer().size() > MAX_BYTES:
		return rejected
	var parser: JSON = JSON.new()
	if parser.parse(bytes) != OK or typeof(parser.data) != TYPE_DICTIONARY:
		return rejected
	var record: Dictionary = parser.data
	if record.size() != 5:
		return rejected
	for field: String in ["schema_version", "run_id", "source_revision", "state", "port"]:
		if not record.has(field):
			return rejected
	if typeof(record["run_id"]) != TYPE_STRING or record["run_id"] != run_id \
		or typeof(record["source_revision"]) != TYPE_STRING or record["source_revision"] != revision \
		or typeof(record["state"]) != TYPE_STRING or record["state"] != "ready":
		return rejected
	var version: Variant = record["schema_version"]
	var port_value: Variant = record["port"]
	if (typeof(version) != TYPE_INT and typeof(version) != TYPE_FLOAT) or version != 1:
		return rejected
	if typeof(port_value) != TYPE_INT and typeof(port_value) != TYPE_FLOAT:
		return rejected
	if not is_finite(float(port_value)) or port_value < 1 or port_value > 65535 \
		or floor(float(port_value)) != float(port_value):
		return rejected
	var port: int = int(port_value)
	# Reconstruct validated integral fields. This rejects duplicate keys,
	# whitespace/trailing content and alternate numeric spellings collapsed by JSON.
	if bytes != encode_ready(run_id, revision, port):
		return rejected
	return {"passed": true, "outcome": "ready", "port": port}


static func ordinary_chain(path: String) -> Array[String]:
	var chain: Array[String] = []
	if not path.is_absolute_path() or path == "/" or path.length() > 4096 \
		or path.contains("\\") or path.simplify_path() != path:
		return chain
	var components: PackedStringArray = path.substr(1).split("/", false)
	if components.is_empty() or components.size() > 64:
		return chain
	var current: String = "/"
	var opened: DirAccess = DirAccess.open(current)
	if opened == null or opened.get_current_dir() != current:
		return []
	chain.append(current)
	for component: String in components:
		if component.is_empty() or component == "." or component == ".." \
			or opened.is_link(component) or not opened.dir_exists(component):
			return []
		current = current.path_join(component)
		opened = DirAccess.open(current)
		if opened == null or opened.get_current_dir() != current:
			return []
		chain.append(current)
	return chain


static func read_ready(directory: String, chain: Array[String]) -> String:
	if chain.is_empty() or ordinary_chain(directory) != chain:
		return ""
	var opened: DirAccess = DirAccess.open(directory)
	if opened == null or opened.is_link(READY_LEAF) or not opened.file_exists(READY_LEAF):
		return ""
	var file: FileAccess = FileAccess.open(directory.path_join(READY_LEAF), FileAccess.READ)
	if file == null:
		return ""
	var length: int = file.get_length()
	if length < 1 or length > MAX_BYTES:
		file.close()
		return ""
	var buffer: PackedByteArray = file.get_buffer(MAX_BYTES + 1)
	file.close()
	if buffer.size() != length or ordinary_chain(directory) != chain or opened.is_link(READY_LEAF):
		return ""
	return buffer.get_string_from_utf8()


static func publish_ready(directory: String, chain: Array[String], bytes: String) -> bool:
	if chain.is_empty() or ordinary_chain(directory) != chain or bytes.is_empty() \
		or bytes.to_utf8_buffer().size() > MAX_BYTES:
		return false
	var opened: DirAccess = DirAccess.open(directory)
	if opened == null:
		return false
	opened.include_hidden = true
	if not opened.get_files().is_empty() or not opened.get_directories().is_empty():
		return false
	var pending: String = directory.path_join(PENDING_LEAF)
	if opened.is_link(PENDING_LEAF) or opened.file_exists(PENDING_LEAF) or opened.dir_exists(PENDING_LEAF):
		return false
	var file: FileAccess = FileAccess.open(pending, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(bytes)
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	if write_error != OK or ordinary_chain(directory) != chain or opened.is_link(PENDING_LEAF):
		return false
	file = FileAccess.open(pending, FileAccess.READ)
	if file == null:
		return false
	var buffer: PackedByteArray = file.get_buffer(MAX_BYTES + 1)
	file.close()
	if buffer != bytes.to_utf8_buffer() or ordinary_chain(directory) != chain \
		or opened.is_link(PENDING_LEAF) or opened.is_link(READY_LEAF) \
		or opened.file_exists(READY_LEAF) or opened.dir_exists(READY_LEAF):
		return false
	# Ordinary move only after pending bytes are closed/read back. Fresh namespace
	# and absent-leaf checks are observations, not an exclusive-file syscall.
	if opened.rename(PENDING_LEAF, READY_LEAF) != OK:
		return false
	return read_ready(directory, chain) == bytes
