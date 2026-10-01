"""Linux-owned, bounded real-server lifecycle for issue #1260."""

import argparse
import hashlib
import json
import os
import platform
import re
import shutil
import signal
import socket
import sqlite3
import subprocess
import sys
import time
import uuid
from pathlib import Path

try:
    from scripts.coop_combat_protocol import validate_pair as validate_coop_combat_pair
except ModuleNotFoundError:
    from coop_combat_protocol import validate_pair as validate_coop_combat_pair

IMAGE = "sha256:801341fea24b22777e65e8ad5b38ca306c33e59b4adcdc14c37d8f461b162602"
HOST = "192.168.1.254"
SCENARIO = "authenticated-input-ack-v1"
SHARED_SCENARIO = "shared-exploration-v1"
COOP_COMBAT_SCENARIO = "coop-combat-v1"
FRONTIER_TIMEOUT_SCENARIO = "frontier-timeout-v1"
IDENTITY_KEYS = ("schema_version", "run_id", "scenario_id", "correlation_id", "client_build", "server_build")
RPC_FILES = ("network_client.gd", "player_identity.gd", "nakama_gameplay_bridge_client.gd",
             "sector_geometry_translator.gd", "sector_navigation_readiness.gd", "telemetry_batch_queue.gd")
PROJECT = '''config_version=5
[application]
config/name="Project0 Paired Server"
config/features=PackedStringArray("4.3", "GL Compatibility")
[autoload]
PlayerIdentity="*res://client/player_identity.gd"
NetworkClient="*res://client/network_client.gd"
[rendering]
renderer/rendering_method="gl_compatibility"
'''


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def command(*args, timeout=30, check=True):
    result = subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            text=True, timeout=timeout)
    if check and result.returncode:
        raise ValueError("command_failed:" + args[0])
    return result


def check_host(system=None, hostname=None):
    if (system or platform.system()) != "Linux" or (hostname or socket.gethostname()) != "okami":
        raise ValueError("wrong_host")


def allowed(path):
    return (path.startswith(("server/", "shared/", "addons/com.heroiclabs.nakama/"))
            and path.endswith(".gd")) or path in {
                "project.godot", "scripts/paired_server_fixture.gd",
                "shared/spatial_schema_v1.json",
                "addons/godot-sqlite/gdsqlite.gdextension",
                "addons/godot-sqlite/bin/libgdsqlite.linux.template_debug.x86_64.so",
                "addons/godot-sqlite/bin/libgdsqlite.linux.template_release.x86_64.so",
                *("client/" + name for name in RPC_FILES),
            }


def check_files(root, manifest):
    if not manifest.get("files"):
        raise ValueError("artifact_missing")
    for name, expected in manifest["files"].items():
        path = root / name
        if not allowed(name) or ".." in Path(name).parts or path.is_symlink():
            raise ValueError("artifact_path")
        if not path.is_file() or digest(path) != expected:
            raise ValueError("artifact_hash")
    actual = {path.relative_to(root).as_posix() for path in root.rglob("*")
              if path.is_file() and path.name != "manifest.json"}
    if actual != set(manifest["files"]):
        raise ValueError("artifact_extra_files")


def reserve_port(host, port):
    listener = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        listener.bind((host, port))
    except BaseException:
        listener.close()
        raise
    return listener


def check_runtime(manifest):
    if manifest["image"] != IMAGE or manifest["server_engine"] != "4.3.stable.official.77dcf97d8":
        raise ValueError("incompatible_runtime")


def redact(text, secrets):
    for value in secrets:
        if value:
            text = text.replace(value, "[REDACTED]")
    text = re.sub(r"\b[A-Za-z0-9+/=]{40,}\.[A-Za-z0-9+/=]{20,}\b", "[REDACTED]", text)
    return re.sub(r"\b[0-9a-fA-F]{64}\b", "[REDACTED]", text)


def healthy(snapshot, now, previous_tick):
    return (snapshot.get("status") == "healthy"
            and snapshot.get("server_tick", -1) > previous_tick
            and 0 <= now - snapshot.get("timestamp", 0) <= 5)


def valid_admission(admission, sequence, since, now):
    return (admission.get("authenticated") is True
            and type(admission.get("input_ack_sequence")) is int
            and admission["input_ack_sequence"] >= sequence
            and since <= admission.get("observed_at", 0) <= now)


def valid_shutdown(state, stop_code):
    return (stop_code == 0 and state.get("Running") is False
            and state.get("OOMKilled") is False and state.get("Error") == ""
            and type(state.get("ExitCode")) is int and state["ExitCode"] in (0, 143))


def owned_resource(kind, name, run_id):
    field = "{{json .Config.Labels}}" if kind == "container" else "{{json .Labels}}"
    result = command("docker", kind, "inspect", "--format", field, name, check=False)
    try:
        return result.returncode == 0 and (json.loads(result.stdout) or {}).get("project0.run") == run_id
    except (ValueError, AttributeError):
        return False


def remove_owned(kind, name, run_id):
    listing = ["docker", kind, "ls"]
    if kind == "container":
        listing += ["--all"]
    listing += ["--format", "{{.Names}}" if kind == "container" else "{{.Name}}"]
    before = command(*listing, check=False)
    if before.returncode:
        return False
    if name not in before.stdout.splitlines():
        return True
    if not owned_resource(kind, name, run_id):
        return False
    removal = ["docker", kind, "rm"] + (["--force"] if kind == "container" else [])
    command(*removal, name, check=False)
    after = command(*listing, check=False)
    return after.returncode == 0 and name not in after.stdout.splitlines()


def check_client(report, evidence):
    if any(evidence.get(key) != report[key] for key in IDENTITY_KEYS):
        raise ValueError("client_identity_mismatch")
    observed = evidence.get("observed_at", 0)
    if not isinstance(observed, (int, float)) or not report["started_at"] <= observed <= min(time.time() + 5, report["deadline_at"]):
        raise ValueError("client_evidence_stale")
    if (evidence.get("status") != "passed" or evidence.get("authenticated") is not True
            or evidence.get("world_entered") is not True
            or type(evidence.get("input_ack_sequence")) is not int
            or evidence["input_ack_sequence"] < 0):
        raise ValueError("client_evidence_failed")


def validate_frontier_observation(frontier, sector_id="sector-0--1"):
    if not isinstance(frontier, dict) or frontier.get("sector_id") != sector_id:
        raise ValueError("frontier_sector")
    if frontier.get("geometry_ready") is not True or frontier.get("crossed") is not True:
        raise ValueError("frontier_not_ready")
    started = frontier.get("started_at_msec")
    geometry_ready = frontier.get("geometry_ready_at_msec")
    crossed = frontier.get("crossed_at_msec")
    if not all(type(value) is int for value in (started, geometry_ready, crossed)):
        raise ValueError("frontier_timing_shape")
    if not started >= 0 or not started <= geometry_ready <= crossed:
        raise ValueError("frontier_timing_order")
    if frontier.get("ready_latency_ms") != geometry_ready - started:
        raise ValueError("frontier_ready_timing")
    if frontier.get("cross_latency_ms") != crossed - started:
        raise ValueError("frontier_cross_timing")


def check_shared_client(report, evidence):
    if report["scenario_id"] != SHARED_SCENARIO or evidence.get("scenario_id") != SHARED_SCENARIO:
        raise ValueError("shared_scenario_identity")
    if evidence.get("correlation_id") != report["correlation_id"]:
        raise ValueError("shared_correlation_identity")
    clients = evidence.get("clients", {})
    if set(clients) != {"a", "b"} or clients["a"].get("character_id") == clients["b"].get("character_id"):
        raise ValueError("shared_character_identity")
    for client_id in ("a", "b"):
        client = clients[client_id]
        if (client.get("status") != "passed" or client.get("scenario_id") != SHARED_SCENARIO
                or client.get("correlation_id") != report["correlation_id"]
                or client.get("client_id") != client_id
                or client.get("authenticated") is not True or client.get("world_entered") is not True):
            raise ValueError("shared_client_evidence_failed")
        if client.get("client_build") != report["client_build"] or client.get("server_build") != report["server_build"]:
            raise ValueError("shared_build_identity")
        remotes = client.get("remote_players", {})
        if set(remotes) != {"a" if client_id == "b" else "b"}:
            raise ValueError("shared_remote_presence")
        remote = remotes["a" if client_id == "b" else "b"]
        if isinstance(remote, dict):
            if remote.get("character_id") != clients["a" if client_id == "b" else "b"].get("character_id"):
                raise ValueError("shared_remote_character")
        elif not isinstance(remote, str):
            raise ValueError("shared_remote_shape")
    initial = evidence.get("phases", {}).get("initial", {})
    if evidence.get("phases", {}).get("movement", {}).get("verified") is True:
        initial = {}
    for client_id in ("a", "b") if initial else ():
        remote_id = "a" if client_id == "b" else "b"
        baseline = initial.get(client_id, {}).get("remote_players", {}).get(remote_id, {}).get("position")
        observed = clients[client_id].get("remote_players", {}).get(remote_id, {}).get("position")
        if not isinstance(baseline, list) or not isinstance(observed, list) or len(baseline) != 3 or len(observed) != 3:
            raise ValueError("shared_movement_shape")
        if sum((float(left) - float(right)) ** 2 for left, right in zip(baseline, observed)) ** 0.5 <= 0.5:
            raise ValueError("shared_authoritative_movement")
    phases = evidence.get("phases", {})
    if not {"initial", "disconnect", "reconnect"}.issubset(phases):
        raise ValueError("shared_lifecycle_phases")
    if phases["disconnect"].get("remote_players") != {}:
        raise ValueError("shared_disconnect_presence")
    if set(phases["reconnect"].get("remote_players", {})) != {"b"}:
        raise ValueError("shared_reconnect_presence")
    frontier_phase = phases.get("frontier", {})
    validate_frontier_observation(frontier_phase.get("a"))
    validate_frontier_observation(frontier_phase.get("b"))
    return True


def check_coop_combat_client(report, evidence):
    validate_coop_combat_pair(evidence, report["correlation_id"],
                               {"client": report["client_build"], "server": report["server_build"]})


def check_frontier_timeout_client(report, evidence):
    if report["scenario_id"] != FRONTIER_TIMEOUT_SCENARIO or evidence.get("scenario_id") != FRONTIER_TIMEOUT_SCENARIO:
        raise ValueError("frontier_timeout_scenario_identity")
    if evidence.get("correlation_id") != report["correlation_id"]:
        raise ValueError("frontier_timeout_correlation_identity")
    client = evidence.get("client", {})
    if (client.get("status") != "passed" or client.get("scenario_id") != FRONTIER_TIMEOUT_SCENARIO
            or client.get("correlation_id") != report["correlation_id"]
            or client.get("authenticated") is not True or client.get("world_entered") is not True):
        raise ValueError("frontier_timeout_client_failed")
    if client.get("client_build") != report["client_build"] or client.get("server_build") != report["server_build"]:
        raise ValueError("frontier_timeout_build_identity")
    validate_frontier_observation(client.get("frontier"))
    frames = client.get("frame_times", {})
    if type(frames.get("count")) is not int or frames["count"] <= 0:
        raise ValueError("frontier_timeout_frame_samples")
    reentry = client.get("reentry", {})
    if reentry.get("left") is not True or reentry.get("reentered") is not True:
        raise ValueError("frontier_timeout_reentry")
    return True


def check_frontier_timeout_server(observation):
    if observation.get("seeded") is not True or observation.get("authenticated_world_peers") != 1:
        raise ValueError("frontier_timeout_server_peer")
    generation = observation.get("generation", {})
    if generation.get("request_outcome") != "timeout" or generation.get("fallback_selected") is not True:
        raise ValueError("frontier_timeout_not_forced")
    if observation.get("canon_outcome") != "ok":
        raise ValueError("frontier_timeout_canon")
    generated = [event for event in observation.get("frontier_ready_events", [])
                 if event.get("sector_id") == "sector-0--1" and event.get("path") == "generated"]
    if len(generated) != 1:
        raise ValueError("frontier_timeout_ready_record")
    return True
    return True


def write_json(path, value):
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, indent=2) + "\n")
    temporary.replace(path)


def read_json(path):
    return json.loads(path.read_text())


def read_health(path, previous):
    try:
        return read_json(path)
    except json.JSONDecodeError:
        return previous


def prepare(root, output):
    check_host()
    source_commit = command("git", "-C", str(root), "rev-parse", "HEAD").stdout.strip()
    tracked = command("git", "-C", str(root), "ls-tree", "-r", "--name-only", source_commit).stdout.splitlines()
    if "scripts/paired_server_fixture.gd" not in tracked:
        raise ValueError("fixture_must_be_committed")
    output.mkdir(mode=0o700, parents=True, exist_ok=False)
    names = [name for name in tracked if allowed(name) and name != "project.godot"]
    for name in names:
        target = output / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(subprocess.check_output(
            ["git", "-C", str(root), "show", source_commit + ":" + name], timeout=30))
    (output / "project.godot").write_text(PROJECT)
    (output / ".godot").mkdir()
    manifest = {
        "schema_version": 1, "source_commit": source_commit,
        "prepared_by_sha256": digest(Path(__file__)),
        "image": IMAGE, "server_engine": "4.3.stable.official.77dcf97d8",
        "files": {path.relative_to(output).as_posix(): digest(path)
                  for path in sorted(output.rglob("*")) if path.is_file()},
    }
    write_json(output / "manifest.json", manifest)
    return {"artifact": str(output), "sha256": digest(output / "manifest.json"), "files": len(manifest["files"])}


def storage_facts(state, identity):
    facts = {}
    for filename, table in (("accounts.db", "journeys"), ("canon.db", "canon_sectors")):
        matches = list(state.rglob(filename))
        if len(matches) != 1:
            raise ValueError("storage_missing:" + filename)
        with sqlite3.connect(matches[0].as_uri() + "?mode=ro", uri=True, timeout=1) as database:
            facts[filename] = {"user_version": database.execute("PRAGMA user_version").fetchone()[0],
                               "rows": database.execute("SELECT COUNT(*) FROM " + table).fetchone()[0]}
            if filename == "accounts.db":
                facts["issued_character_journeys"] = database.execute(
                    "SELECT COUNT(*) FROM journeys WHERE character_id = ?", (identity,)).fetchone()[0]
    if facts["canon.db"]["rows"] < 1 or any(facts[name]["user_version"] != 1 for name in ("accounts.db", "canon.db")):
        raise ValueError("storage_not_ready")
    return facts


def supervise(run):
    report = read_json(run / "report.json")
    request = read_json(run / "request.json")
    state = run / "private"
    name = "p0-paired-" + report["run_id"]
    network = name + "-net"
    owned_container = False
    owned_network = False
    reservation = None
    interrupted = False

    def cancel(_signum, _frame):
        nonlocal interrupted
        interrupted = True

    signal.signal(signal.SIGTERM, cancel)
    signal.signal(signal.SIGINT, cancel)
    try:
        check_host()
        artifact = Path(request["artifact"])
        if digest(artifact / "manifest.json") != request["artifact_sha256"]:
            raise ValueError("artifact_manifest_hash")
        manifest = read_json(artifact / "manifest.json")
        check_files(artifact, manifest)
        report["server_build"]["source_commit"] = manifest["source_commit"]
        report["server_build"]["rpc_sha256"] = manifest["files"]["client/network_client.gd"]
        report["server_build"]["engine"] = manifest["server_engine"]
        report["supervisor_sha256"] = digest(Path(__file__))
        check_runtime(manifest)
        image = json.loads(command("docker", "image", "inspect", IMAGE).stdout)[0]
        if image["Id"] != IMAGE:
            raise ValueError("image_hash")
        reservation = reserve_port(HOST, request["port"])
        report["host"] = HOST
        report["port"] = reservation.getsockname()[1]
        state.mkdir(mode=0o700)
        (state / "cache").mkdir()
        (state / "cache/extension_list.cfg").write_text("res://addons/godot-sqlite/gdsqlite.gdextension\n")
        report["resources"] = {"container": name, "network": network}
        if command("docker", "network", "inspect", network, check=False).returncode == 0:
            raise ValueError("network_occupied")
        owned_network = True
        command("docker", "network", "create", "--label", "project0.issue=1260",
            "--label", "project0.run=" + report["run_id"], network)
        reservation.close()
        reservation = None
        script = (
            "umask 077; godot --version > /state/engine.txt; "
            "godot --headless --path /app --editor --import > /state/import.log 2>&1; "
            "exec godot --headless --path /app -s scripts/paired_server_fixture.gd"
        )
        args = ["docker", "run", "--detach", "--pull=never", "--name", name,
                "--label", "project0.issue=1260", "--label", "project0.run=" + report["run_id"], "--network", network,
                "--publish", f"{HOST}:{report['port']}:9999/udp", "--read-only", "--cap-drop=ALL",
                "--security-opt=no-new-privileges", "--user", f"{os.getuid()}:{os.getgid()}",
                "--tmpfs", "/tmp:rw,nosuid,size=64m", "--pids-limit", "128", "--memory", "1g",
                "--volume", f"{artifact}:/app:ro", "--volume", f"{state}:/state",
                "--volume", f"{state / 'cache'}:/app/.godot", "--entrypoint", "/usr/bin/timeout"]
        environment = {"HOME": "/state", "XDG_DATA_HOME": "/state/data", "PAIRED_RUN_ID": report["run_id"],
                   "PAIRED_SCENARIO": report["scenario_id"], "PAIRED_CORRELATION_ID": report["correlation_id"],
                       "PROJECT0_ACCOUNTS_DB_PATH": "accounts.db", "PROJECT0_CANON_DB_PATH": "canon.db",
                       "PROJECT0_HEALTH_FILE": "/state/health.json", "PROJECT0_SERVER_BIND_ADDRESS": "0.0.0.0",
                       "PROJECT0_SERVER_PORT": "9999", "PROJECT0_OPERATOR_CONTROL_PORT": "8097",
                       "PROJECT0_REQUIRED_CLIENT_VERSION": report["client_build"]["version"]}
        for key, value in environment.items():
            args += ["--env", key + "=" + value]
        args += [IMAGE, "--signal=TERM", "--kill-after=5", str(request["deadline_seconds"]), "sh", "-ec", script]
        owned_container = True
        command(*args)
        report["status"] = "starting"
        write_json(run / "report.json", report)
        ready_deadline = min(report["deadline_at"], time.time() + request["readiness_seconds"])
        previous_tick = -1
        health = {}
        finish_received_at = None
        finish_sequence = -1
        client_was_authenticated = False
        while True:
            now = time.time()
            if interrupted:
                raise ValueError("cancelled")
            if now >= report["deadline_at"]:
                raise ValueError("timeout")
            control_path = run / "control.json"
            control = None
            if control_path.exists():
                control = read_json(control_path)
                if control["action"] == "abort":
                    raise ValueError("aborted")
                if control["action"] == "reject":
                    raise ValueError("client_evidence_rejected")
            running = command("docker", "inspect", "--format", "{{.State.Running}}", name).stdout.strip()
            if running != "true":
                raise ValueError("runtime_exited")
            health_path = state / "health.json"
            if health_path.exists():
                health = read_health(health_path, health)
                report["observed_health"] = health
                if report["status"] == "starting" and healthy(health, now, previous_tick) and previous_tick >= 0:
                    engine = (state / "engine.txt").read_text().strip()
                    if engine != manifest["server_engine"]:
                        raise ValueError("runtime_version_mismatch")
                    auth = read_json(state / "auth.json")
                    if not all(auth.get(key) is True for key in ("issuer_validated", "tampered_rejected", "expired_rejected")):
                        raise ValueError("authentication_not_ready")
                    report.update(status="ready", ready_at=now, readiness={"health": health, "auth": auth,
                                  "storage": storage_facts(state, report["run_id"]), "engine": engine})
                    write_json(run / "report.json", report)
                previous_tick = health.get("server_tick", previous_tick)
                if report["status"] == "ready" and not healthy(health, now, -1):
                    raise ValueError("runtime_unhealthy")
                if report["status"] == "ready" and report["scenario_id"] == SCENARIO and (state / "admission.json").exists():
                    admission = read_json(state / "admission.json")
                    report["admission"] = admission
                    client_was_authenticated = client_was_authenticated or admission.get("authenticated") is True
                    if client_was_authenticated and admission.get("authenticated") is not True:
                        raise ValueError("client_disconnected")
            if control:
                if report["scenario_id"] == SHARED_SCENARIO:
                    check_shared_client(report, control["evidence"])
                    shared_observation = read_json(state / "shared-observation.json")
                    history_counts = [entry.get("authenticated_world_peers") for entry in shared_observation.get("history", [])]
                    if not {1, 2}.issubset(history_counts) or history_counts[-1] != 2:
                        raise ValueError("shared_server_lifecycle_missing")
                    frontier = shared_observation.get("frontier", {})
                    if shared_observation.get("frontier_fixture_seeded") is not True:
                        raise ValueError("shared_frontier_fixture_missing")
                    if set(frontier) != {"a", "b"}:
                        raise ValueError("shared_frontier_missing")
                    for client_id in ("a", "b"):
                        evidence = frontier[client_id]
                        if (evidence.get("sector_id") != "sector-0--1"
                                or evidence.get("source") != "fallback"
                                or evidence.get("fallback_selected") is not True
                                or evidence.get("canon_outcome") != "ok"
                                or evidence.get("presentation_ready") is not True):
                            raise ValueError("shared_frontier_authority_missing")
                    report.update(status="server_passed", shared_observation=shared_observation,
                                  client_evidence_sha256=digest(control_path))
                    break
                if report["scenario_id"] == FRONTIER_TIMEOUT_SCENARIO:
                    check_frontier_timeout_client(report, control["evidence"])
                    observation = read_json(state / "frontier-observation.json")
                    check_frontier_timeout_server(observation)
                    report.update(status="server_passed", frontier_observation=observation,
                                  client_evidence_sha256=digest(control_path))
                    break
                if report["scenario_id"] == COOP_COMBAT_SCENARIO:
                    check_coop_combat_client(report, control["evidence"])
                    combat_observation = read_json(state / "combat-observation.json")
                    if combat_observation.get("authenticated_world_peers") != 2:
                        raise ValueError("combat_server_peer_count")
                    if combat_observation.get("accepted_count") != 1 or combat_observation.get("hit_count") != 1:
                        raise ValueError("combat_server_encounter_count")
                    if combat_observation.get("accepted_resolution", {}).get("result") != "ACCEPTED":
                        raise ValueError("combat_server_resolution_missing")
                    if combat_observation.get("hit_event", {}).get("target_id") != "target_dummy_0":
                        raise ValueError("combat_server_hit_missing")
                    report.update(status="server_passed", combat_observation=combat_observation,
                                  client_evidence_sha256=digest(control_path))
                    break
                check_client(report, control["evidence"])
                admission = read_json(state / "admission.json")
                now = time.time()
                if finish_received_at is None:
                    finish_received_at = now
                    finish_sequence = admission.get("input_ack_sequence", -1)
                    report["finish_observation"] = {"received_at": now, "input_ack_sequence": finish_sequence}
                if report["status"] != "ready" or not healthy(health, now, -1):
                    raise ValueError("runtime_unhealthy")
                if admission.get("observed_at", 0) < finish_received_at:
                    if now - finish_received_at >= 2:
                        raise ValueError("server_admission_stale")
                else:
                    facts = storage_facts(state, report["run_id"])
                    if admission.get("authenticated") is not True or facts["issued_character_journeys"] != 1:
                        raise ValueError("server_admission_missing")
                    required_sequence = max(control["evidence"]["input_ack_sequence"], finish_sequence + 1)
                    if valid_admission(admission, required_sequence, finish_received_at, now):
                        report.update(status="server_passed", admission=admission, storage=facts,
                                      client_evidence_sha256=digest(control_path))
                        break
                    if now - finish_received_at >= 2:
                        raise ValueError("server_input_stale")
            if report["status"] == "starting" and now >= ready_deadline:
                raise ValueError("readiness_timeout")
            time.sleep(0.1)
    except Exception as error:
        report.update(status="failed", reason=redact(str(error), []))
    finally:
        if reservation:
            reservation.close()
        outstanding = []
        if owned_container:
            try:
                if not owned_resource("container", name, report["run_id"]):
                    raise ValueError("container_ownership_unverified")
                stopped = command("docker", "stop", "--time", "3", name, check=False)
                exit_state = json.loads(command("docker", "container", "inspect", "--format", "{{json .State}}", name).stdout)
                report["shutdown"] = {"stop_exit_code": stopped.returncode,
                                      "running": exit_state.get("Running"), "exit_code": exit_state.get("ExitCode"),
                                      "oom_killed": exit_state.get("OOMKilled"), "error": redact(str(exit_state.get("Error", "")), []),
                                      "passed": valid_shutdown(exit_state, stopped.returncode)}
                if report["status"] == "server_passed" and not report["shutdown"]["passed"]:
                    report.update(status="failed", reason="runtime_shutdown_failed")
                report["runtime_logs_complete"] = exit_state.get("Running") is False
                raw = command("docker", "logs", name).stdout
                tokens = [(state / name).read_text() for name in ("assertion", "assertion-a", "assertion-b")
                          if (state / name).exists()]
                if (state / "import.log").exists():
                    imported = redact((state / "import.log").read_text(), tokens)
                    (run / "import.log").write_text(imported)
                    report["import_log_sha256"] = digest(run / "import.log")
                    report["import_error_lines"] = sum("ERROR:" in line for line in imported.splitlines())
                sanitized = redact(raw, tokens)
                (run / "runtime.log").write_text(sanitized)
                report["log_sha256"] = digest(run / "runtime.log")
                report["runtime_error_lines"] = sum("ERROR:" in line or "SCRIPT ERROR:" in line for line in sanitized.splitlines())
                if report["status"] == "server_passed" and report["runtime_error_lines"]:
                    report.update(status="failed", reason="runtime_errors")
            except Exception:
                report["status"] = "failed"
                report.setdefault("reason", "runtime_evidence_unavailable")
                report["runtime_evidence_available"] = False
                report["runtime_error_lines"] = None
            try:
                if not remove_owned("container", name, report["run_id"]):
                    outstanding.append(name)
            except Exception:
                outstanding.append(name)
        if owned_network:
            try:
                if not remove_owned("network", network, report["run_id"]):
                    outstanding.append(network)
            except Exception:
                outstanding.append(network)
        try:
            if state.exists():
                shutil.rmtree(state)
        except OSError:
            outstanding.append(str(state))
        report["cleanup"] = {"passed": not outstanding, "outstanding": outstanding,
                             "private_state_removed": not state.exists()}
        if outstanding:
            report.update(status="failed", reason="cleanup_failed")
        report["finished_at"] = time.time()
        report["paired_acceptance"] = False
        write_json(run / "report.json", report)


def start(args):
    check_host()
    if not re.fullmatch(r"[A-Za-z0-9_-]{1,80}", args.correlation_id):
        raise ValueError("correlation_id")
    if args.scenario not in (SCENARIO, SHARED_SCENARIO, COOP_COMBAT_SCENARIO, FRONTIER_TIMEOUT_SCENARIO):
        raise ValueError("scenario")
    if not re.fullmatch(r"[a-f0-9]{64}", args.client_sha256) or not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", args.client_version):
        raise ValueError("client_build")
    if not 5 <= args.deadline_seconds <= 180 or not 1 <= args.readiness_seconds <= args.deadline_seconds:
        raise ValueError("deadline")
    args.run.mkdir(mode=0o700, parents=True, exist_ok=False)
    now = time.time()
    report = {"schema_version": 1, "scenario_id": args.scenario, "correlation_id": args.correlation_id,
              "run_id": uuid.uuid4().hex, "client_build": {"sha256": args.client_sha256,
              "version": args.client_version, "engine": args.client_engine},
              "server_build": {"sha256": args.artifact_sha256, "image": IMAGE},
              "started_at": now, "deadline_at": now + args.deadline_seconds, "status": "accepted",
              "paired_acceptance": False}
    write_json(args.run / "request.json", {"artifact": str(args.artifact.resolve()),
               "artifact_sha256": args.artifact_sha256, "port": args.port, "scenario": args.scenario,
               "deadline_seconds": args.deadline_seconds, "readiness_seconds": args.readiness_seconds})
    write_json(args.run / "report.json", report)
    with (args.run / "supervisor.log").open("w") as output:
        process = subprocess.Popen([sys.executable, str(Path(__file__).resolve()), "_supervise", "--run", str(args.run)],
                                   stdin=subprocess.DEVNULL, stdout=output, stderr=output, start_new_session=True)
    write_json(args.run / "supervisor.json", {"pid": process.pid})
    return report


def main():
    os.umask(0o077)
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="action", required=True)
    package = commands.add_parser("prepare")
    package.add_argument("--source", type=Path, default=Path.cwd())
    package.add_argument("--artifact", type=Path, required=True)
    launch = commands.add_parser("start")
    launch.add_argument("--artifact", type=Path, required=True)
    launch.add_argument("--artifact-sha256", required=True)
    launch.add_argument("--correlation-id", required=True)
    launch.add_argument("--scenario", default=SCENARIO)
    launch.add_argument("--client-sha256", required=True)
    launch.add_argument("--client-version", required=True)
    launch.add_argument("--client-engine", required=True)
    launch.add_argument("--port", type=int, default=0)
    launch.add_argument("--deadline-seconds", type=int, default=180)
    launch.add_argument("--readiness-seconds", type=int, default=45)
    for action in ("start", "status", "finish", "abort", "_supervise"):
        child = launch if action == "start" else commands.add_parser(action)
        child.add_argument("--run", type=Path, required=True)
        if action == "finish":
            child.add_argument("--evidence", type=Path, required=True)
    args = parser.parse_args()
    check_host()
    if hasattr(args, "run"):
        args.run = args.run.resolve()
    if args.action == "prepare":
        result = prepare(args.source.resolve(), args.artifact.resolve())
    elif args.action == "start":
        result = start(args)
    elif args.action == "_supervise":
        supervise(args.run)
        return
    elif args.action == "status":
        result = read_json(args.run / "report.json")
        admission_path = args.run / "private/admission.json"
        if result["status"] == "ready" and admission_path.exists():
            result["admission"] = read_json(admission_path)
    else:
        report = read_json(args.run / "report.json")
        if "finished_at" in report:
            raise ValueError("already_finished")
        control = {"action": args.action}
        if args.action == "finish":
            try:
                evidence = read_json(args.evidence)
                if report["scenario_id"] == SHARED_SCENARIO:
                    check_shared_client(report, evidence)
                elif report["scenario_id"] == COOP_COMBAT_SCENARIO:
                    check_coop_combat_client(report, evidence)
                elif report["scenario_id"] == FRONTIER_TIMEOUT_SCENARIO:
                    check_frontier_timeout_client(report, evidence)
                else:
                    check_client(report, evidence)
            except (ValueError, OSError, TypeError):
                write_json(args.run / "control.json", {"action": "reject"})
                raise ValueError("client_evidence_rejected")
            control["evidence"] = (evidence if report["scenario_id"] in (SHARED_SCENARIO, COOP_COMBAT_SCENARIO, FRONTIER_TIMEOUT_SCENARIO) else
                                    {key: evidence[key] for key in (*IDENTITY_KEYS, "status", "observed_at", "authenticated", "world_entered", "input_ack_sequence")})
        write_json(args.run / "control.json", control)
        result = {"action": args.action, "status": "requested", "run_id": report["run_id"]}
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(json.dumps({"status": "rejected", "reason": redact(str(error), [])}))
        sys.exit(1)