#!/usr/bin/env python3
"""Experiment 1360: can the configured local Ollama return a validated sector
within the 3.0 s JIT cutoff? Runs on the Linux server host only.

Owns setup, sampling, evidence and teardown in one non-interactive path:
raw uncapped latency (Ollama timing metadata) plus the production service path
(cutoff, schema gate, placement gate) for cold and warm requests. Restores the
model's loaded/unloaded state on exit and fails closed when the target is missing.
"""
import argparse
import hashlib
import json
import math
import os
import shutil
import statistics
import subprocess
import sys
import tempfile
import time
import urllib.request

CUTOFF_MS = 3000.0
RAW_TIMEOUT_SEC = 180


def call(host, payload, timeout):
    request = urllib.request.Request(host + "/api/generate", data=json.dumps(payload).encode(),
                                     headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return json.loads(response.read())


def loaded_models(host):
    with urllib.request.urlopen(host + "/api/ps", timeout=5) as response:
        return [model["name"] for model in json.loads(response.read()).get("models", [])]


def unload(host, model):
    call(host, {"model": model, "keep_alive": 0}, 60)
    deadline = time.time() + 30
    while model in loaded_models(host) and time.time() < deadline:
        time.sleep(0.5)


def raw_sample(host, model, prompt, cold):
    if cold:
        unload(host, model)
    started = time.monotonic()
    try:
        body = call(host, {"model": model, "prompt": prompt, "format": "json", "think": False, "stream": False}, RAW_TIMEOUT_SEC)
    except (OSError, ValueError) as error:
        # A sample that exceeds the raw ceiling is a measurement, not a harness failure.
        return {"cold": cold, "wall_ms": (time.monotonic() - started) * 1000.0, "error": str(error)[:120]}
    wall_ms = (time.monotonic() - started) * 1000.0
    try:
        parsed = json.loads(body.get("response", ""))
        json_ok = isinstance(parsed, dict)
    except ValueError:
        json_ok = False
    nanos = {key: body.get(key, 0) / 1e6 for key in ("total_duration", "load_duration", "prompt_eval_duration", "eval_duration")}
    return {"cold": cold, "wall_ms": wall_ms, "json_object": json_ok, "eval_count": body.get("eval_count"),
            "prompt_eval_count": body.get("prompt_eval_count"), **{key + "_ms": value for key, value in nanos.items()}}


def godot(home, *arguments):
    environment = {"PATH": os.environ["PATH"], "HOME": home, "XDG_DATA_HOME": home + "/data",
                   "XDG_CONFIG_HOME": home + "/config", "XDG_CACHE_HOME": home + "/cache",
                   "PROJECT0_OLLAMA_HOST": ARGS.host, "PROJECT0_OLLAMA_MODEL": ARGS.model}
    completed = subprocess.run(["godot", "--headless", "-s", "res://scripts/exp1360_service_sampler.gd", "--", *arguments],
                               env=environment, capture_output=True, text=True, timeout=600)
    if completed.returncode != 0:
        raise RuntimeError("sampler exited %d: %s" % (completed.returncode, completed.stderr[-400:]))


def percentile(values, fraction):
    ordered = sorted(values)
    return ordered[max(0, math.ceil(fraction * len(ordered)) - 1)] if ordered else None


def summarize(samples):
    durations = [sample["timing"].get("generation_duration_ms", 0.0) for sample in samples]
    usable = [sample for sample in samples if sample["final_source"] == "llm"]
    return {"count": len(samples), "validated_by_schema": sum(s["request_outcome"] == "validated" and s["source"] == "llm" for s in samples),
            "usable_after_placement_gate": len(usable),
            "outcomes": {outcome: sum(s["request_outcome"] == outcome for s in samples) for outcome in {s["request_outcome"] for s in samples}},
            "generation_ms": {"p50": percentile(durations, 0.5), "p95": percentile(durations, 0.95), "max": max(durations) if durations else None}}


def main():
    output = os.path.abspath(ARGS.out)
    os.makedirs(output, exist_ok=False)
    evidence = {"issue": 1360, "host": ARGS.host, "model": ARGS.model, "cutoff_ms": CUTOFF_MS, "status": "failed",
                "started_at": time.time(), "raw": [], "service_cold": [], "service_warm": None, "failure": None}
    home = tempfile.mkdtemp(prefix="exp1360-")
    initially_loaded = None
    try:
        with urllib.request.urlopen(ARGS.host + "/api/tags", timeout=5) as response:
            models = [model["name"] for model in json.loads(response.read())["models"]]
        if ARGS.model not in models:
            raise RuntimeError("model %s not installed on %s" % (ARGS.model, ARGS.host))
        initially_loaded = ARGS.model in loaded_models(ARGS.host)
        evidence["initially_loaded"] = initially_loaded
        prompt_path = os.path.join(home, "prompt.json")
        godot(home, "prompt", prompt_path)
        prompt = json.load(open(prompt_path))["prompt"]
        evidence["prompt_sha256"] = hashlib.sha256(prompt.encode()).hexdigest()
        evidence["prompt_chars"] = len(prompt)
        for _ in range(ARGS.cold):
            evidence["raw"].append(raw_sample(ARGS.host, ARGS.model, prompt, True))
        for _ in range(ARGS.raw_warm):
            evidence["raw"].append(raw_sample(ARGS.host, ARGS.model, prompt, False))
        for index in range(ARGS.cold):
            unload(ARGS.host, ARGS.model)
            path = os.path.join(home, "cold-%d.json" % index)
            godot(home, "sample", path, "1")
            evidence["service_cold"].extend(json.load(open(path))["samples"])
        warm_path = os.path.join(home, "warm.json")
        godot(home, "sample", warm_path, str(ARGS.warm))
        evidence["service_warm"] = json.load(open(warm_path))
        warm = evidence["service_warm"]["samples"]
        raw_warm = [sample["wall_ms"] for sample in evidence["raw"] if not sample["cold"]]
        evidence["summary"] = {
            "service_warm": summarize(warm), "service_cold": summarize(evidence["service_cold"]),
            "raw_warm_wall_ms": {"p50": percentile(raw_warm, 0.5), "max": max(raw_warm) if raw_warm else None},
            "raw_cold_wall_ms": [sample["wall_ms"] for sample in evidence["raw"] if sample["cold"]],
        }
        usable = evidence["summary"]["service_warm"]["usable_after_placement_gate"] + evidence["summary"]["service_cold"]["usable_after_placement_gate"]
        evidence["verdict"] = "pass" if usable > 0 else "fail"
        evidence["status"] = "completed"
    except Exception as error:
        evidence["failure"] = str(error)[:400]
    finally:
        try:
            if initially_loaded is False:
                unload(ARGS.host, ARGS.model)
            evidence["restored_unloaded"] = initially_loaded is not False or ARGS.model not in loaded_models(ARGS.host)
        except Exception as error:
            evidence["restore_failure"] = str(error)[:200]
        shutil.rmtree(home, ignore_errors=True)
        evidence["temp_removed"] = not os.path.exists(home)
        evidence["finished_at"] = time.time()
        with open(os.path.join(output, "result.json"), "w") as handle:
            json.dump(evidence, handle, indent=2)
    print(json.dumps({"status": evidence["status"], "verdict": evidence.get("verdict"), "failure": evidence["failure"],
                      "summary": evidence.get("summary")}, indent=2))
    return 0 if evidence["status"] == "completed" and evidence["temp_removed"] else 1


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", default="http://192.168.1.254:11434")
    parser.add_argument("--model", default="qwen3.5:9b")
    parser.add_argument("--cold", type=int, default=3)
    parser.add_argument("--warm", type=int, default=20)
    parser.add_argument("--raw-warm", type=int, default=5)
    parser.add_argument("--out", required=True)
    ARGS = parser.parse_args()
    sys.exit(main())
