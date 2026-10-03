"""Pure receipt validation for the bounded #1444 persistence affinity fixture.

This qualifies only the reviewed, lexically supported call sites. It neither
executes native code nor establishes hidden VM locks, kernel mutex identity,
continuous waiting duration, publisher attestation, or production acceptance.
The controller owns source/provenance capture, filesystem custody and processes.
"""

import hashlib
import json
import re


MODES = ("candidate", "main_sqlite_control", "main_wait_control")
MEASUREMENT_KEYS = ("known_native_entries", "known_main_native_entries",
                    "known_main_native_elapsed_usec", "known_worker_native_elapsed_usec",
                    "known_main_mailbox_elapsed_usec", "known_main_lock_call_elapsed_usec")
FAILURE_CODES = ("schema", "source_binding", "source_inventory", "provenance", "clock",
                 "mode_coverage", "span_coverage", "caller_owner", "object_lifecycle",
                 "chronology", "parity", "control_ineffective", "cleanup",
                 "forbidden_main_entry", "bounds")
MEMBER_SHA256 = {
    "debug": "d380b79c56073f63e41593ddbe3460977bb42b1ee03dddd0a80d334a0f79187a",
    "release": "09d73fac80382e172f4445b3da983e8db8e1317f0119188b99500832d660424a",
}
RELEASE_SHA256 = "639fd1c20ffaa8545f5341325eedfffa29fa3d8c3861c150aaacbc0478208ae3"
LIMITS = {"spans_per_mode": 256, "spans_total": 576, "mailbox_bytes": 65536,
          "thread_return_bytes": 131072, "report_bytes": 262144,
          "proc_line_bytes": 8192, "proc_total_bytes": 1048576}
MAX_INTEGER = (1 << 63) - 1
NOT_OBSERVED = "NOT_OBSERVED"
TOP_KEYS = {"schema_version", "experiment", "modes", "clock", "loaded_addon",
            "source_fixture_sha256", "limits", "exact_target_futex_identity",
            "continuous_wait_duration", "production_acceptance"}
MODE_KEYS = {"mode", "status", "failure_class", "main_caller", "worker_caller",
             "window_begin_usec", "window_end_usec", "initialization_begin_usec",
             "initialization_end_usec", "termination_observed_usec", "worker_return_usec",
             "completion_published_usec", "teardown_begin_usec", "teardown_end_usec",
             "submitted_once", "result_consumed", "worker_terminated", "worker_joined",
             "owned_state_removed", "lifecycles", "spans", "wait"}
SPAN_KEYS = {"site", "operation", "phase", "cycle", "role", "ordinal", "caller_begin",
             "caller_end", "owner", "object_begin", "object_end", "begin_usec", "end_usec",
             "outcome"}
CYCLE_KEYS = {"cycle", "success", "journal_mode_rows", "foreign_keys_rows", "user_version_rows",
              "committed_rows", "rolled_back_rows", "control_rows", "autocommit_values", "release"}
WAIT_KEYS = {"armed_attempt", "observation_attempt", "state_before_sleeping", "state_after_sleeping",
             "futex_class", "observation_begin_usec", "observation_end_usec", "worker_unlock_begin_usec",
             "source_attribution", "exact_target_identity", "continuous_wait_duration"}
OUTCOMES = {"ok", "observed", "released", "null", "busy", "acquired", "alive", "terminated",
            "failed", "retained"}

# Exact authored next-line expressions make an annotation insufficient on its own.
SITE_LINES = {
    "native.new": ("sqlite.new", "var database: SQLite = SQLite.new()"),
    "native.identity": ("object.get_instance_id", "var object_id: int = database.get_instance_id()"),
    "native.path": ("sqlite.path.set", "database.path = path"),
    "native.foreign_keys": ("sqlite.foreign_keys.set", "database.foreign_keys = true"),
    "native.read_only": ("sqlite.read_only.set", "database.read_only = false"),
    "native.verbosity": ("sqlite.verbosity_level.set", "database.verbosity_level = SQLite.QUIET"),
    "native.open": ("sqlite.open_db", "var success: bool = database.open_db()"),
    "native.query": ("sqlite.query", 'success = database.query(action["sql"])'),
    "native.bound_query": ("sqlite.query_with_bindings", 'success = database.query_with_bindings(action["sql"], action["bindings"])'),
    "native.rows": ("sqlite.query_result.get", "var raw: Array = database.query_result"),
    "native.autocommit": ("sqlite.get_autocommit", "var value: int = database.get_autocommit()"),
    "native.close": ("sqlite.close_db", "var closed: bool = database.close_db()"),
    "native.weakref": ("weakref.new", "var native_weak: WeakRef = weakref(database)"),
    "native.release": ("sqlite.release", "database = null"),
    "native.weakref_check": ("weakref.get_ref", "var released: bool = native_weak.get_ref() == null"),
    "sync.mailbox.new": ("mutex.new", "_mailbox = Mutex.new()"),
    "sync.mailbox.identity": ("object.get_instance_id", "_mailbox_id = _mailbox.get_instance_id()"),
    "sync.control.new": ("mutex.new", "_control = Mutex.new()"),
    "sync.control.identity": ("object.get_instance_id", "_control_id = _control.get_instance_id()"),
    "sync.thread.new": ("thread.new", "_thread = Thread.new()"),
    "sync.thread.identity": ("object.get_instance_id", "_thread_id = _thread.get_instance_id()"),
    "sync.thread.start": ("thread.start", "var start_error: Error = _thread.start(_worker_main)"),
    "sync.thread.alive": ("thread.is_alive", "var alive: bool = _thread.is_alive()"),
    "sync.thread.join": ("thread.wait_to_finish", "var returned: Variant = _thread.wait_to_finish()"),
    "sync.mailbox.main_try": ("mutex.try_lock", "var acquired: bool = _mailbox.try_lock()"),
    "sync.mailbox.main_unlock": ("mutex.unlock", "_mailbox.unlock()"),
    "sync.mailbox.worker_lock": ("mutex.lock", "_mailbox.lock()"),
    "sync.mailbox.worker_unlock": ("mutex.unlock", "_mailbox.unlock()"),
    "sync.control.worker_lock": ("mutex.lock", "_control.lock()"),
    "sync.control.worker_unlock": ("mutex.unlock", "_control.unlock()"),
    "sync.control.main_try": ("mutex.try_lock", "var acquired: bool = _control.try_lock()"),
    "sync.control.main_try_unlock": ("mutex.unlock", "_control.unlock()"),
    "sync.control.main_lock": ("mutex.lock", "_control.lock()"),
    "sync.control.main_unlock": ("mutex.unlock", "_control.unlock()"),
    "sync.worker_delay": ("os.delay_usec", 'OS.delay_usec(4000 if phase == "init" else 1000)'),
    "sync.thread.release": ("thread.release", "_thread = null"),
    "sync.mailbox.release": ("mutex.release", "_mailbox = null"),
    "sync.control.release": ("mutex.release", "_control = null"),
}
ANNOTATION = re.compile(r"^\s*# AFFINITY_SITE ([a-z._]+) ([a-z._]+)\s*$")
STRINGS_COMMENTS = re.compile(r'"""[\s\S]*?"""|\x27\x27\x27[\s\S]*?\x27\x27\x27|"(?:\\.|[^"\\])*"|\x27(?:\\.|[^\x27\\])*\x27|\#[^\n]*')
SUPPORTED_ENTRY = re.compile(
    r"\b(?:SQLite\s*\.\s*new\s*\(|database\s*\.\s*\w+|database\s*=\s*null\b|"
    r"weakref\s*\(|native_weak\s*\.\s*\w+|Mutex\s*\.\s*new\s*\(|Thread\s*\.\s*new\s*\(|"
    r"_(?:mailbox|control|thread)\s*\.\s*\w+|_(?:mailbox|control|thread)\s*=\s*null\b|"
    r"OS\s*\.\s*delay_\w+\s*\(|Semaphore\s*\.\s*\w+)")
UNSUPPORTED_ENTRY = re.compile(r"\b(?:ClassDB|Semaphore)\b|\.\s*(?:lock|unlock|try_lock|wait_to_finish|start|is_alive|open_db|close_db|query|query_with_bindings|get_autocommit|get_ref)\s*\(")
STATE_PREFIX_READER = '''func _read_state(path: String) -> String:
var stream: FileAccess = FileAccess.open(path, FileAccess.READ)
if stream == null:
return ""
var prefix: String = str(OS.get_process_id()) + " ("
for index: int in range(prefix.length()):
if stream.eof_reached() or stream.get_8() != prefix.unicode_at(index):
stream.close()
return ""
for index: int in range(MAIN_COMM.length()):
if stream.eof_reached() or stream.get_8() != MAIN_COMM.unicode_at(index):
stream.close()
return ""
for expected: int in [41, 32]:
if stream.eof_reached() or stream.get_8() != expected:
stream.close()
return ""
if stream.eof_reached():
stream.close()
return ""
var state: int = stream.get_8()
if stream.eof_reached():
stream.close()
return ""
var separator: int = stream.get_8()
stream.close()
return String.chr(state) if separator == 32 and state in [82, 83, 68, 84, 116, 88, 90, 80, 73] else ""'''


def _record(value: object, keys: set[str]) -> bool:
    return type(value) is dict and set(value) == keys


def _integer(value: object, *, identity: bool = False) -> bool:
    if type(value) is not int:
        return False
    return -(1 << 63) <= value <= MAX_INTEGER and value != 0 if identity else 0 <= value <= MAX_INTEGER


def _need(condition: bool, code: str, errors: set[str]) -> None:
    if not condition:
        errors.add(code)


def _rows_equal(value: object, expected: list[list]) -> bool:
    return (type(value) is list and len(value) == len(expected)
            and all(type(row) is list and len(row) == len(wanted)
                    and all(type(cell) is type(target) and cell == target
                            for cell, target in zip(row, wanted))
                    for row, wanted in zip(value, expected)))


def _primitive(value: object, depth: int = 0) -> bool:
    if depth > 10:
        return False
    if type(value) is bool:
        return True
    if type(value) is int:
        return -(1 << 63) <= value <= MAX_INTEGER
    if type(value) is str:
        return len(value) <= 128
    if type(value) is list:
        return len(value) <= 256 and all(_primitive(child, depth + 1) for child in value)
    if type(value) is dict:
        return len(value) <= 64 and all(type(key) is str and len(key) <= 128
                                      and _primitive(child, depth + 1) for key, child in value.items())
    return False


def _size(value: object) -> int:
    return len(json.dumps(value, separators=(",", ":"), ensure_ascii=False, allow_nan=False).encode("utf-8"))


def _source_inventory(fixture: bytes, public_test: bytes) -> bool:
    seen: set[str] = set()
    for source, is_fixture in ((fixture, True), (public_test, False)):
        text = source.decode("utf-8")
        if "\x00" in text:
            return False
        lines = text.splitlines()
        plain = STRINGS_COMMENTS.sub(lambda match: "\n" * match.group().count("\n"), text).splitlines()
        annotated_lines: set[int] = set()
        for index, line in enumerate(lines):
            annotation = ANNOTATION.fullmatch(line)
            if not annotation:
                if "AFFINITY_SITE" in line:
                    return False
                continue
            site, operation = annotation.groups()
            if not is_fixture or site in seen or site not in SITE_LINES or index + 1 >= len(lines):
                return False
            if SITE_LINES[site] != (operation, lines[index + 1].strip()):
                return False
            if site == "sync.control.main_lock":
                if index < 4 or index + 8 >= len(lines):
                    return False
                if (f'_begin("{site}", "{operation}",' not in lines[index - 4]
                        or lines[index - 3].strip() != "var lock_begin: int = 0"
                        or lines[index - 2].strip() != "var lock_end: int = 0"
                        or lines[index - 1].strip() != "lock_begin = Time.get_ticks_usec()"
                        or lines[index + 2].strip() != "lock_end = Time.get_ticks_usec()"
                        or lines[index + 3].strip() != 'lock_span["begin_usec"] = lock_begin'
                        or lines[index + 4].strip() != 'lock_span["end_usec"] = lock_end'
                        or lines[index + 5].strip() != 'lock_span["caller_end"] = OS.get_thread_caller_id()'
                        or lines[index + 6].strip() != 'lock_span["object_end"] = _control_id'
                        or lines[index + 7].strip() != 'lock_span["outcome"] = "ok"'
                        or lines[index + 8].strip() != "_append(_main_spans, lock_span)"):
                    return False
            elif site == "native.bound_query":
                # The two authored SQL arms share one epilogue, with no intervening call.
                if (index < 1 or index + 7 >= len(lines)
                        or '_begin("native.bound_query", "sqlite.query_with_bindings",' not in lines[index - 1]
                        or lines[index + 2].strip() != "else:"
                        or '_begin("native.query", "sqlite.query",' not in lines[index + 3]
                        or lines[index + 4].strip() != "# AFFINITY_SITE native.query sqlite.query"
                        or lines[index + 5].strip() != 'success = database.query(action["sql"])'
                        or not re.fullmatch(r'\s*_end\(span,.+\)\s*', lines[index + 6])):
                    return False
            elif (index < (2 if site == "sync.control.worker_unlock" else 1)
                  or f'_begin("{site}", "{operation}",' not in lines[index - (2 if site == "sync.control.worker_unlock" else 1)]
                  or (site == "sync.control.worker_unlock" and lines[index - 1].strip() != 'wait["worker_unlock_begin_usec"] = span["begin_usec"]')
                  or index + 2 >= len(lines) or not re.fullmatch(r'\s*_end\((?:span|identity|attempt|release),.+\)\s*', lines[index + 2])):
                return False
            seen.add(site)
            annotated_lines.add(index + 1)
        for index, line in enumerate(plain):
            # HashingContext.start is the reviewed initialization hashing call,
            # not Thread.start; no other receiver receives this exception.
            hash_start = lines[index].strip() == "if context.start(HashingContext.HASH_SHA256) != OK:"
            if (SUPPORTED_ENTRY.search(line) or UNSUPPORTED_ENTRY.search(line)) and index not in annotated_lines and not hash_start:
                return False
            if re.search(r"\b(?:var|const)\s+\w+(?:\s*:\s*\w*)?\s*=\s*(?:database|_mailbox|_control|_thread)\s*$", line):
                return False
            if re.search(r"\bSQLite\s*\.\s*(?!new\b|QUIET\b)\w+", line):
                return False
            for identifier, native_type in re.findall(r"\b(\w+)\s*:\s*(SQLite|Mutex|Thread)\b", line):
                if identifier not in {"SQLite": {"database"}, "Mutex": {"_mailbox", "_control"}, "Thread": {"_thread"}}[native_type]:
                    return False
            if is_fixture and re.search(r"\.\s*call(?:v|_deferred)?\s*\(", line):
                return False
            if not is_fixture and re.search(r"\.\s*call(?:v|_deferred)?\s*\(", line):
                if not re.search(r'\bfixture\.call\("(?:initialize|poll_once|try_submit|finalize_completed)"(?:,|\))', lines[index]):
                    return False
        if is_fixture:
            code = "\n".join(plain)
            if not re.search(r"lock_begin = Time\.get_ticks_usec\(\)\s+_control\.lock\(\)\s+lock_end = Time\.get_ticks_usec\(\)", code):
                return False
            reader = re.search(r"(?ms)^func _read_state\([^\n]+\n.*?(?=^func |\Z)", text)
            if reader is None:
                return False
            normalized = "\n".join(line.strip() for line in reader.group().splitlines()
                                   if line.strip() and not line.strip().startswith("#"))
            if normalized != STATE_PREFIX_READER or 'const MAIN_COMM: String = "godot"' not in lines:
                return False
            if text.count('task.path_join("stat")') != 2 or text.count('_read_state(task.path_join("stat"))') != 2:
                return False
    return seen == set(SITE_LINES)


def _native_sequence(cycle: str, role: str) -> list[tuple[str, int]]:
    sequence = [(site, 1) for site in ("native.new", "native.identity", "native.path", "native.foreign_keys",
                                      "native.read_only", "native.verbosity", "native.open")]
    if cycle == "first":
        sequence += [("native.query", 1), ("native.rows", 1), ("native.query", 2),
                     ("native.query", 3), ("native.rows", 2), ("native.query", 4),
                     ("native.query", 5), ("native.rows", 3), ("native.query", 6),
                     ("native.autocommit", 1), ("native.query", 7), ("native.autocommit", 2),
                     ("native.bound_query", 1), ("native.query", 8), ("native.autocommit", 3),
                     ("native.query", 9), ("native.autocommit", 4), ("native.bound_query", 2),
                     ("native.query", 10), ("native.autocommit", 5),
                     ("native.bound_query", 3), ("native.rows", 4),
                     ("native.bound_query", 4), ("native.rows", 5)]
        if role == "main_control":
            for index in range(32):
                sequence += [("native.bound_query", index + 5), ("native.rows", index + 6)]
    else:
        sequence += [("native.query", 1), ("native.rows", 1), ("native.query", 2),
                     ("native.rows", 2), ("native.query", 3), ("native.rows", 3),
                     ("native.autocommit", 1), ("native.bound_query", 1), ("native.rows", 4),
                     ("native.bound_query", 2), ("native.rows", 5)]
    return sequence + [(site, 1) for site in ("native.close", "native.weakref", "native.release", "native.weakref_check")]


def _span_shape(span: object) -> bool:
    if not _record(span, SPAN_KEYS):
        return False
    return (type(span["site"]) is str and span["site"] in SITE_LINES
            and type(span["operation"]) is str and span["operation"] == SITE_LINES[span["site"]][0]
            and span["phase"] in ("init", "request", "teardown")
            and span["cycle"] in ("first", "reopen", "none")
            and span["role"] in ("main", "worker", "main_control")
            and _integer(span["ordinal"]) and 1 <= span["ordinal"] <= 256
            and all(_integer(span[key], identity=True) for key in ("caller_begin", "caller_end", "owner"))
            and all(type(span[key]) is int and -(1 << 63) <= span[key] <= MAX_INTEGER
                    for key in ("object_begin", "object_end"))
            and all(_integer(span[key]) for key in ("begin_usec", "end_usec"))
            and span["outcome"] in OUTCOMES)


def _lifecycle(lifecycle: object, role: str, mode: dict, spans: list[dict], errors: set[str]) -> set[int]:
    identities: set[int] = set()
    if not _record(lifecycle, {"role", "success", "cycles"}) or lifecycle["role"] != role:
        errors.add("schema")
        return identities
    _need(type(lifecycle["success"]) is bool and lifecycle["success"], "object_lifecycle", errors)
    cycles = lifecycle["cycles"]
    names = ("first", "reopen") if role == "worker" else ("first",)
    if type(cycles) is not list or len(cycles) != len(names):
        errors.add("object_lifecycle")
        return identities
    owner = mode["worker_caller"] if role == "worker" else mode["main_caller"]
    previous_release = mode["window_begin_usec"]
    for index, cycle in enumerate(cycles):
        name = names[index]
        if not _record(cycle, CYCLE_KEYS) or cycle["cycle"] != name:
            errors.add("schema")
            continue
        _need(type(cycle["success"]) is bool and cycle["success"], "object_lifecycle", errors)
        _need(_rows_equal(cycle["journal_mode_rows"], [["wal"]]) and _rows_equal(cycle["foreign_keys_rows"], [[1]])
              and _rows_equal(cycle["user_version_rows"], [[1444]]) and _rows_equal(cycle["committed_rows"], [[7]])
              and _rows_equal(cycle["rolled_back_rows"], []), "parity", errors)
        count = 32 if role == "main_control" and name == "first" else 0
        control_rows = cycle["control_rows"]
        autocommit = cycle["autocommit_values"]
        _need(type(control_rows) is list and len(control_rows) == count
              and all(_rows_equal(rows, [[7]]) for rows in control_rows)
              and type(autocommit) is list and all(type(value) is int for value in autocommit)
              and autocommit == ([1, 0, 1, 0, 1] if name == "first" else [1]), "parity", errors)
        events = [span for span in spans if span["site"].startswith("native.")
                  and span["role"] == role and span["cycle"] == name]
        _need([(span["site"], span["ordinal"]) for span in events] == _native_sequence(name, role), "span_coverage", errors)
        if not events:
            continue
        object_id = events[0]["object_end"]
        _need(_integer(object_id, identity=True) and object_id not in identities, "object_lifecycle", errors)
        identities.add(object_id)
        for position, span in enumerate(events):
            expected_outcome = ("null" if span["site"] == "native.weakref_check" else
                                "released" if span["site"] == "native.release" else
                                "observed" if span["site"] in {"native.identity", "native.weakref", "native.rows", "native.autocommit"}
                                else "ok")
            _need(span["phase"] == "request" and span["outcome"] == expected_outcome, "span_coverage", errors)
            _need(span["caller_begin"] == span["caller_end"] == span["owner"] == owner, "caller_owner", errors)
            _need(span["object_end"] == object_id and span["object_begin"] == (0 if position < 2 else object_id), "object_lifecycle", errors)
            _need(previous_release <= span["begin_usec"] <= span["end_usec"] <= mode["window_end_usec"], "chronology", errors)
            previous_release = span["end_usec"]
        release = cycle["release"]
        if not _record(release, {"object_id", "weakref_null", "observed_caller", "tick_usec"}):
            errors.add("schema")
            continue
        _need(_integer(release["object_id"], identity=True) and release["object_id"] == object_id and type(release["weakref_null"]) is bool
              and release["weakref_null"] and release["observed_caller"] == owner
              and _integer(release["observed_caller"], identity=True)
              and _integer(release["tick_usec"]) and release["tick_usec"] == events[-1]["end_usec"], "object_lifecycle", errors)
        if role == "worker":
            _need(events[-1]["end_usec"] <= mode["completion_published_usec"], "chronology", errors)
    return identities


def _sync(mode: dict, spans: list[dict], errors: set[str]) -> set[int]:
    identities: set[int] = set()
    sync = [span for span in spans if span["site"].startswith("sync.")]
    objects: dict[str, int] = {}
    for kind in ("mailbox", "control", "thread"):
        created = [span for span in sync if span["site"] == f"sync.{kind}.new"]
        identified = [span for span in sync if span["site"] == f"sync.{kind}.identity"]
        released = [span for span in sync if span["site"] == f"sync.{kind}.release"]
        if len(created) != 1 or len(identified) != 1 or len(released) != 1:
            errors.add("span_coverage")
            continue
        first, identity, last = created[0], identified[0], released[0]
        object_id = first["object_end"]
        objects[kind] = object_id
        _need(_integer(object_id, identity=True) and object_id not in identities, "object_lifecycle", errors)
        identities.add(object_id)
        _need(first["object_begin"] == identity["object_begin"] == 0
              and identity["object_end"] == last["object_begin"] == last["object_end"] == object_id, "object_lifecycle", errors)
        _need(first["phase"] == identity["phase"] == "init" and last["phase"] == "teardown"
              and first["outcome"] == "ok" and identity["outcome"] == "observed"
              and last["outcome"] == "released", "span_coverage", errors)
        _need(first["end_usec"] <= identity["begin_usec"] <= identity["end_usec"] <= last["begin_usec"], "chronology", errors)
    for span in sync:
        site = span["site"]
        role = "worker" if ".worker_" in site or site == "sync.worker_delay" else "main"
        owner = mode["worker_caller"] if role == "worker" else mode["main_caller"]
        _need(span["role"] == role and span["caller_begin"] == span["caller_end"] == span["owner"] == owner
              and span["cycle"] == "none", "caller_owner", errors)
        kind = next((name for name in objects if site.startswith(f"sync.{name}.")), None)
        if kind is not None and not site.endswith((".new", ".identity")):
            _need(span["object_begin"] == span["object_end"] == objects[kind], "object_lifecycle", errors)
        if site == "sync.worker_delay":
            _need(span["object_begin"] == span["object_end"] == 0 and span["outcome"] == "ok", "object_lifecycle", errors)
        if site == "sync.thread.alive":
            _need(span["phase"] in {"request", "teardown"} and span["outcome"] in {"alive", "terminated"}, "span_coverage", errors)
        if site.startswith("sync.mailbox.") and not site.endswith((".new", ".identity", ".release")):
            _need(span["phase"] in {"init", "request"}, "span_coverage", errors)
        if span["phase"] == "teardown":
            _need(role == "main" and mode["teardown_begin_usec"] <= span["begin_usec"] <= span["end_usec"] <= mode["teardown_end_usec"], "chronology", errors)
        elif span["phase"] == "request":
            _need(mode["window_begin_usec"] <= span["begin_usec"] <= span["end_usec"] <= mode["window_end_usec"], "chronology", errors)
        else:
            # Worker readiness polling can overlap the main request-window start.
            upper = mode["initialization_end_usec"] if role == "main" else mode["worker_return_usec"]
            _need(mode["initialization_begin_usec"] <= span["begin_usec"] <= span["end_usec"] <= upper, "chronology", errors)
        if role == "main" and span["phase"] == "request" and span["operation"] in {"mutex.lock", "thread.wait_to_finish", "os.delay_usec"}:
            _need(mode["mode"] == "main_wait_control" and site == "sync.control.main_lock", "forbidden_main_entry", errors)
    starts = [span for span in sync if span["site"] == "sync.thread.start"]
    joins = [span for span in sync if span["site"] == "sync.thread.join"]
    stopped = [span for span in sync if span["site"] == "sync.thread.alive" and span["outcome"] == "terminated"]
    _need(len(starts) == len(joins) == 1 and starts[0]["phase"] == "init" and starts[0]["outcome"] == "ok"
          and joins[0]["phase"] == "teardown" and joins[0]["outcome"] == "ok", "span_coverage", errors)
    _need(any(span["phase"] == "request" and mode["worker_return_usec"] <= span["begin_usec"] <= span["end_usec"] <= mode["termination_observed_usec"] for span in stopped)
          and any(span["phase"] == "teardown" for span in stopped), "chronology", errors)
    for role in ("main", "worker"):
        held = False
        mailbox = [span for span in sync if span["site"].startswith("sync.mailbox.") and span["role"] == role
                   and not span["site"].endswith((".new", ".identity", ".release"))]
        _need(bool(mailbox), "span_coverage", errors)
        previous = mode["initialization_begin_usec"]
        for span in mailbox:
            _need(previous <= span["begin_usec"], "chronology", errors)
            previous = span["end_usec"]
            if span["operation"] == "mutex.unlock":
                _need(held and span["outcome"] == "ok", "span_coverage", errors)
                held = False
            else:
                _need(not held and span["outcome"] in ({"acquired", "busy"} if role == "main" else {"ok"}), "span_coverage", errors)
                held = span["outcome"] in {"acquired", "ok"}
        _need(not held, "cleanup", errors)
    worker_unlocks = [span for span in sync if span["site"] == "sync.mailbox.worker_unlock" and span["phase"] == "request"]
    _need(bool(worker_unlocks), "span_coverage", errors)
    if worker_unlocks:
        _need(mode["completion_published_usec"] <= worker_unlocks[-1]["begin_usec"] <= worker_unlocks[-1]["end_usec"] <= mode["worker_return_usec"], "chronology", errors)
    return identities


def _wait(mode: dict, spans: list[dict], errors: set[str]) -> None:
    wait = mode["wait"]
    active = mode["mode"] == "main_wait_control"
    keys = WAIT_KEYS | ({"failed_try_lock", "main_lock_begin_usec", "main_lock_end_usec"} if active else set())
    if not _record(wait, keys):
        errors.add("schema")
        return
    _need(wait["source_attribution"] == "INFERENCE" and wait["exact_target_identity"] == NOT_OBSERVED
          and wait["continuous_wait_duration"] == NOT_OBSERVED, "control_ineffective", errors)
    control = [span for span in spans if span["site"].startswith("sync.control.")
               and not span["site"].endswith((".new", ".identity", ".release"))]
    if not active:
        _need(not control and all(type(wait[key]) is int and wait[key] == 0 for key in
                                 ("armed_attempt", "observation_attempt", "observation_begin_usec", "observation_end_usec", "worker_unlock_begin_usec"))
              and wait["state_before_sleeping"] is False and wait["state_after_sleeping"] is False
              and wait["futex_class"] == NOT_OBSERVED, "control_ineffective", errors)
        return
    expected_sites = {"sync.control.worker_lock", "sync.control.worker_unlock", "sync.control.main_try",
                      "sync.control.main_lock", "sync.control.main_unlock"}
    _need(len(control) == 5 and {span["site"] for span in control} == expected_sites, "span_coverage", errors)
    by_site = {span["site"]: span for span in control}
    _need(wait["failed_try_lock"] is True and type(wait["armed_attempt"]) is int and wait["armed_attempt"] == 1
          and type(wait["observation_attempt"]) is int and wait["observation_attempt"] == 1
          and wait["state_before_sleeping"] is True and wait["state_after_sleeping"] is True
          and wait["futex_class"] == "APPROVED_FUTEX_WAIT", "control_ineffective", errors)
    ticks = ("main_lock_begin_usec", "main_lock_end_usec", "observation_begin_usec",
             "observation_end_usec", "worker_unlock_begin_usec")
    if not all(_integer(wait[key]) for key in ticks) or not expected_sites.issubset(by_site):
        errors.add("control_ineffective")
        return
    lock, release = by_site["sync.control.main_lock"], by_site["sync.control.worker_unlock"]
    _need(wait["main_lock_begin_usec"] == lock["begin_usec"] and wait["main_lock_end_usec"] == lock["end_usec"]
          and wait["worker_unlock_begin_usec"] == release["begin_usec"]
          and by_site["sync.control.main_try"]["outcome"] == "busy", "control_ineffective", errors)
    _need(lock["begin_usec"] <= wait["observation_begin_usec"] <= wait["observation_end_usec"]
          < release["begin_usec"] < lock["end_usec"], "control_ineffective", errors)
    _need(by_site["sync.control.worker_lock"]["end_usec"] <= by_site["sync.control.main_try"]["begin_usec"]
          <= by_site["sync.control.main_try"]["end_usec"] <= lock["begin_usec"]
          <= lock["end_usec"] <= by_site["sync.control.main_unlock"]["begin_usec"], "chronology", errors)
    _need(all(span["outcome"] == ("busy" if span["site"] == "sync.control.main_try" else "ok") for span in control), "span_coverage", errors)
    for span in spans:
        if span["site"] == "sync.mailbox.main_unlock" and span["phase"] == "request":
            _need(not (span["begin_usec"] < lock["end_usec"] and lock["begin_usec"] < span["end_usec"]), "chronology", errors)


def _mode(mode: object, name: str, errors: set[str]) -> dict[str, object]:
    measurements: dict[str, object] = dict.fromkeys(MEASUREMENT_KEYS)
    if not _record(mode, MODE_KEYS) or mode["mode"] != name:
        errors.add("schema")
        return measurements
    if not all(_integer(mode[key]) for key in MODE_KEYS if key.endswith("_usec")) or not all(
            _integer(mode[key], identity=True) for key in ("main_caller", "worker_caller")):
        errors.add("schema")
        return measurements
    _need(mode["main_caller"] != mode["worker_caller"], "caller_owner", errors)
    _need(mode["status"] == "complete" and mode["failure_class"] == "none", "mode_coverage", errors)
    _need(all(mode[key] is True for key in ("submitted_once", "result_consumed", "worker_terminated", "worker_joined", "owned_state_removed")), "cleanup", errors)
    _need(mode["initialization_begin_usec"] <= mode["initialization_end_usec"] <= mode["window_begin_usec"]
          <= mode["completion_published_usec"] <= mode["worker_return_usec"] <= mode["termination_observed_usec"]
          <= mode["window_end_usec"] < mode["teardown_begin_usec"] <= mode["teardown_end_usec"], "chronology", errors)
    _need(mode["initialization_end_usec"] - mode["initialization_begin_usec"] <= 1000000
          and 0 < mode["window_end_usec"] - mode["window_begin_usec"] <= 150000
          and mode["teardown_end_usec"] - mode["teardown_begin_usec"] <= 1000000, "bounds", errors)
    if type(mode["spans"]) is not list or not 1 <= len(mode["spans"]) <= 256:
        errors.add("bounds")
        return measurements
    spans = [span for span in mode["spans"] if _span_shape(span)]
    _need(len(spans) == len(mode["spans"]), "span_coverage", errors)
    measurements = dict.fromkeys(MEASUREMENT_KEYS, 0)
    invalid_elapsed: set[str] = set()
    for span in spans:
        monotonic = span["begin_usec"] <= span["end_usec"]
        _need(monotonic, "clock", errors)
        _need(span["caller_begin"] == span["caller_end"] == span["owner"], "caller_owner", errors)
        elapsed = span["end_usec"] - span["begin_usec"] if monotonic else 0
        if span["operation"].startswith("sqlite."):
            measurements["known_native_entries"] += 1
            if span["caller_begin"] == mode["main_caller"]:
                measurements["known_main_native_entries"] += 1
                measurements["known_main_native_elapsed_usec"] += elapsed
                if not monotonic:
                    invalid_elapsed.add("known_main_native_elapsed_usec")
                _need(name == "main_sqlite_control", "forbidden_main_entry", errors)
            elif span["caller_begin"] == mode["worker_caller"]:
                measurements["known_worker_native_elapsed_usec"] += elapsed
                if not monotonic:
                    invalid_elapsed.add("known_worker_native_elapsed_usec")
            else:
                errors.add("caller_owner")
        if span["caller_begin"] == mode["main_caller"] and span["phase"] == "request":
            if span["site"].startswith("sync.mailbox."):
                measurements["known_main_mailbox_elapsed_usec"] += elapsed
                if not monotonic:
                    invalid_elapsed.add("known_main_mailbox_elapsed_usec")
            if span["operation"] == "mutex.lock":
                measurements["known_main_lock_call_elapsed_usec"] += elapsed
                if not monotonic:
                    invalid_elapsed.add("known_main_lock_call_elapsed_usec")
    _need(all(value <= MAX_INTEGER for value in measurements.values()), "bounds", errors)
    measurements = {key: value if value <= MAX_INTEGER and key not in invalid_elapsed else None
                    for key, value in measurements.items()}
    # Each supported call is synchronous on its observed caller. Grouped report
    # buffers need not be globally sorted, but same-caller calls cannot overlap.
    for owner in (mode["main_caller"], mode["worker_caller"]):
        calls = sorted((span["begin_usec"], span["end_usec"]) for span in spans if span["caller_begin"] == owner)
        _need(all(left[1] <= right[0] for left, right in zip(calls, calls[1:])), "chronology", errors)
    _sync_ids = _sync(mode, spans, errors)
    expected_roles = ["worker", "main_control"] if name == "main_sqlite_control" else ["worker"]
    lifecycles = mode["lifecycles"]
    if type(lifecycles) is not list or len(lifecycles) != len(expected_roles):
        errors.add("object_lifecycle")
    else:
        for lifecycle, role in zip(lifecycles, expected_roles):
            native_ids = _lifecycle(lifecycle, role, mode, spans, errors)
            _need(not (native_ids & _sync_ids), "object_lifecycle", errors)
            _sync_ids.update(native_ids)
    _need(all(span["role"] in expected_roles
              and span["cycle"] in (("first", "reopen") if span["role"] == "worker" else ("first",)) for span in spans
              if span["site"].startswith("native.")), "span_coverage", errors)
    _wait(mode, spans, errors)
    if name == "main_sqlite_control":
        _need(type(measurements["known_main_native_elapsed_usec"]) is int
              and measurements["known_main_native_entries"] > 0
              and measurements["known_main_native_elapsed_usec"] > 0, "control_ineffective", errors)
    if type(lifecycles) is list and lifecycles and _record(lifecycles[0], {"role", "success", "cycles"}):
        # These are the exact two primitive technical channels authored by the
        # fixture, reconstructed from qualified receipt fields rather than flags.
        worker_spans = [span for span in spans if span["role"] == "worker" and span["site"].startswith("sync.")]
        native_spans = [span for span in spans if span["role"] == "worker" and span["site"].startswith("native.")]
        summary = lifecycles[0]
        publication = {"worker_caller": mode["worker_caller"], "failure_class": mode["failure_class"],
                       "native_released": summary["success"], "cycles": summary["cycles"]}
        returned = {"worker_caller": mode["worker_caller"], "failure_class": mode["failure_class"],
                    "lifecycle": dict(summary, spans=native_spans), "wait": {key: mode["wait"][key] for key in WAIT_KEYS},
                    "spans": worker_spans, "completion_published_usec": mode["completion_published_usec"],
                    "worker_return_usec": mode["worker_return_usec"]}
        _need(_size(publication) <= LIMITS["mailbox_bytes"] and _size(returned) <= LIMITS["thread_return_bytes"], "bounds", errors)
    return measurements


def validate_evidence(report: object, expected_manifest: object,
                      fixture_source_bytes: bytes,
                      public_test_source_bytes: bytes) -> dict[str, object]:
    """Return a closed verdict; unknown or malformed inputs never become zero proof."""
    errors: set[str] = set()
    measurements = {mode: dict.fromkeys(MEASUREMENT_KEYS) for mode in MODES}
    try:
        if not _record(report, TOP_KEYS) or type(report["schema_version"]) is not int or report["schema_version"] != 1 or report["experiment"] != "1444":
            errors.add("schema")
        elif not _primitive(report) or _size(report) > LIMITS["report_bytes"]:
            errors.add("bounds")
        elif not _record(expected_manifest, {"schema_version", "source_revision", "source_hashes", "expected_provenance"}):
            errors.add("source_binding")
        else:
            hashes = expected_manifest["source_hashes"]
            provenance = expected_manifest["expected_provenance"]
            source_valid = (type(expected_manifest["schema_version"]) is int and expected_manifest["schema_version"] == 1
                            and type(expected_manifest["source_revision"]) is str and re.fullmatch(r"[0-9a-f]{40}", expected_manifest["source_revision"])
                            and _record(hashes, {"fixture", "public_test"})
                            and all(type(value) is str and re.fullmatch(r"[0-9a-f]{64}", value) for value in hashes.values())
                            and type(fixture_source_bytes) is bytes and 0 < len(fixture_source_bytes) <= 262144
                            and type(public_test_source_bytes) is bytes and 0 < len(public_test_source_bytes) <= 65536)
            _need(bool(source_valid), "source_binding", errors)
            if source_valid:
                _need(hashlib.sha256(fixture_source_bytes).hexdigest() == hashes["fixture"]
                      and hashlib.sha256(public_test_source_bytes).hexdigest() == hashes["public_test"]
                      and report["source_fixture_sha256"] == hashes["fixture"], "source_binding", errors)
                _need(_source_inventory(fixture_source_bytes, public_test_source_bytes), "source_inventory", errors)
            _need(_record(provenance, {"schema_version", "member_sha256", "release_artifact_sha256"})
                  and type(provenance["schema_version"]) is int and provenance["schema_version"] == 1
                  and _record(provenance["member_sha256"], {"debug", "release"})
                  and provenance["member_sha256"] == MEMBER_SHA256 and provenance["release_artifact_sha256"] == RELEASE_SHA256, "provenance", errors)
            addon = report["loaded_addon"]
            _need(_record(addon, {"selected_mode", "mapped_member_sha256"}) and addon["selected_mode"] in MEMBER_SHA256
                  and addon["mapped_member_sha256"] == MEMBER_SHA256[addon["selected_mode"]], "provenance", errors)
            clock = report["clock"]
            if not _record(clock, {"units", "samples_usec"}) or clock["units"] != "us" or type(clock["samples_usec"]) is not list or len(clock["samples_usec"]) != 32 or not all(_integer(sample) for sample in clock["samples_usec"]):
                errors.add("clock")
            else:
                samples = clock["samples_usec"]
                _need(all(left <= right for left, right in zip(samples, samples[1:]))
                      and any(left < right for left, right in zip(samples, samples[1:])), "clock", errors)
            _need(_record(report["limits"], set(LIMITS)) and all(type(report["limits"][key]) is int and report["limits"][key] == value for key, value in LIMITS.items()), "bounds", errors)
            _need(all(report[key] == NOT_OBSERVED for key in ("exact_target_futex_identity", "continuous_wait_duration", "production_acceptance")), "schema", errors)
            modes = report["modes"]
            if type(modes) is not list or len(modes) != 3:
                errors.add("mode_coverage")
            else:
                total = sum(len(mode["spans"]) for mode in modes if type(mode) is dict and type(mode.get("spans")) is list)
                _need(total <= LIMITS["spans_total"], "bounds", errors)
                for mode, name in zip(modes, MODES):
                    measurements[name] = _mode(mode, name, errors)
                main_ids = [mode.get("main_caller") for mode in modes if type(mode) is dict]
                _need(len(main_ids) == 3 and len(set(main_ids)) == 1, "caller_owner", errors)
                if _record(clock, {"units", "samples_usec"}) and type(clock["samples_usec"]) is list and clock["samples_usec"]:
                    _need(modes[0]["initialization_begin_usec"] <= clock["samples_usec"][0]
                          <= clock["samples_usec"][-1] <= modes[0]["initialization_end_usec"], "clock", errors)
    except (TypeError, ValueError, KeyError, UnicodeError, OverflowError, AttributeError, RecursionError):
        errors.add("schema")
    failed = [code for code in FAILURE_CODES if code in errors]
    return {"schema_version": 1, "passed": not failed,
            "coverage": NOT_OBSERVED if failed else "QUALIFIED", "failure_codes": failed,
            "measurements": measurements}
