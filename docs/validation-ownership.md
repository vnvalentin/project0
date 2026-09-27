# Validation Ownership

Governing change: [#1243](https://github.com/vnvalentin/project0/issues/1243).
This enforces the existing [runtime ownership contract](SYSTEMS-SPECIFICATION.md#runtime-ownership).
It does not change the architecture or authorize a paused workstream.

## Before Execution Or Dependency Installation

1. Identify the public behavior and owning runtime, then consult
   [the test ownership manifest](../scripts/validation_ownership.json).
2. Record the exact test selections, platform, host, dependencies, command,
   expected artifacts and rollback on the governing issue. Put the machine-readable
   portion in an owned validation plan and run the preflight below.
3. Require a passing preflight before execution. Check missing dependencies against
   architectural ownership before recommending installation. SQLite, real Canon
   stores and Ollama belong on the Linux server, not the Windows client.
4. Run each check on its owning host. Capture actual command, host, engine,
   revision/artifact fingerprints, results and cleanup. Link both host reports
   by scenario/correlation identity for paired acceptance.

A combined fixture that constructs server persistence and a client presentation
object is Linux supporting evidence. It must not be moved wholesale to Windows.
Windows tests validate the real client's presentation, input and readiness against
the Linux server. A mock Canon store is not a replacement for the required real
server persistence evidence.

## Commands

Run on `192.168.1.254` through SSH, using the configured Python interpreter:

```sh
python -m unittest discover -s scripts -p test_validation_ownership.py -v
python scripts/check_validation_ownership.py --output build/validation/ownership.json
python scripts/check_validation_ownership.py --plan .scratch/<issue>/validation-plan.json --output build/validation/plan-ownership.json
```

These commands inspect plans/source and never launch Godot, install a package,
start a server or invoke a Windows test. Exit 0 means the static check or plan
passed, not that runtime acceptance passed. Invalid input exits 1 with JSON reasons.
Existing Linux CI uses the explicit `github-actions-linux` host identifier.

Example component plan:

```json
{
  "schema_version": 1,
  "kind": "component",
  "steps": [{
    "suite": "godot-server",
    "platform": "linux",
    "host": "192.168.1.254",
    "command": "scripts/run_gut_validation.sh",
    "dependencies": ["godot", "sqlite"],
    "tests": ["tests/integration/test_canon_mutation_repository.gd"],
    "artifacts": ["build/validation/gut.xml", "build/validation/gut.log"]
  }]
}
```

For `kind: paired-runtime`, include both `linux-server` and `windows-client`
ownership steps and nonempty `scenario_id`, `client_build`, `server_build`,
`correlation_id`, `setup` and `cleanup`. These describe the planned execution;
actual correlated native client/server evidence is still mandatory. Component
or packaging tests in a valid plan do not establish a paired gameplay result.
Add a reviewed ownership entry for a new harness rather than misclassifying it
under an existing suite. Unknown and multiply owned tests fail closed.

## CI And Coverage

The Linux `Validation ownership and client boundary` CI job checks every discovered
first-party `test_*.gd`, `test_*.py`, `test_*.sh`, `test_*.ps1` and `*_test.go`
under the manifest's roots. Patterns match path components, so nested tests do not
silently become part of a nonrecursive GUT suite. Inventory includes the separate
GDScript smoke harnesses; it is not a claim that GUT executes them all.

Existing GUT and service gates remain unchanged. Windows scripts and launcher
tests are inventoried only, not executed by this Linux job. Their native validation
remains Windows-owned; launcher coverage is never standalone gameplay evidence.
No suite is skipped or removed to make the architecture gate pass.

Static dependency checks traverse client scripts/scenes/resources, literal
`res://` references and project `class_name` references through shared helpers.
Server runtime/persistence and SQLite references fail. The existing pure starting
town fixture is an exact path exception, and its dependencies are still checked.
`ResourceLoader.exists` probes are not imports. Comments are not dependencies.

This is a conservative lexical guard, not a full GDScript parser or exported
package audit. Computed resource paths, global extension discovery and actual
packaged contents require native artifact/startup checks on Windows. Do not claim
those checks passed from this report, and do not install Windows SQLite to make a
source-tree harness run. Fix client isolation under its Windows-owned issue.

## Blocker Handling

Classify a failed check as product behavior, test placement, host setup, missing
artifact, or unobservable evidence before proposing remediation. Record the actual
failing boundary and falsifiable check. Preserve the original report, append a
superseding correction when the premise was wrong, and keep the gameplay issue
open until its own runtime acceptance is satisfied.

For #1242, the earlier proposed Windows SQLite prerequisite is superseded by the
server-only ownership decision. Real SQLite/Canon evidence stays on Linux;
client readiness and player acceptance stay on Windows. This prevention gate
does not itself repair or close the town-exit defect.