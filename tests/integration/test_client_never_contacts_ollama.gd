extends GutTest
## Structural public-seam test for Slice 051 (P-009) and CLAUDE.md's Runtime
## Ownership law: "The client MUST NOT ... directly contact Ollama or SQLite."
## Scans every file under client/ for forbidden references to the
## server-only LocalLLMClient or the default Ollama port, rather than trusting
## a manual code-review claim.

const FORBIDDEN_TOKENS: PackedStringArray = ["local_llm_client", "LocalLLMClient", "11434"]
const CLIENT_ROOT: String = "res://client"


func _scan_dir(path: String, violations: Array) -> void:
	var dir: DirAccess = DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if entry in [".", ".."]:
			entry = dir.get_next()
			continue
		var full_path: String = path.path_join(entry)
		if dir.current_is_dir():
			_scan_dir(full_path, violations)
		elif entry.ends_with(".gd") or entry.ends_with(".tscn"):
			var file: FileAccess = FileAccess.open(full_path, FileAccess.READ)
			if file != null:
				var text: String = file.get_as_text()
				for token in FORBIDDEN_TOKENS:
					if text.find(token) != -1:
						violations.append("%s references forbidden token '%s'" % [full_path, token])
		entry = dir.get_next()
	dir.list_dir_begin()
	dir.list_dir_end()


func test_client_directory_never_references_ollama_or_local_llm_client() -> void:
	assert_true(DirAccess.dir_exists_absolute(CLIENT_ROOT), "client/ directory exists for scanning")
	var violations: Array = []
	_scan_dir(CLIENT_ROOT, violations)
	assert_eq(violations.size(), 0, "client/ must never reference LocalLLMClient or the Ollama port: %s" % [violations])
