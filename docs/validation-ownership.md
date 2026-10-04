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
python scripts/test_validation_ownership.py --report build/validation/ownership-tests.json
python scripts/check_validation_ownership.py --output build/validation/ownership.json
python scripts/check_validation_ownership.py --plan .scratch/<issue>/validation-plan.json --output build/validation/plan-ownership.json
```

These commands inspect plans/source and never launch Godot, install a package,
start a server or invoke a Windows test. Exit 0 means the static check or plan
passed, not that runtime acceptance passed. Invalid input exits 1 with JSON reasons.
Existing Linux CI uses the explicit `github-actions-linux` host identifier.
The manifest assigns `SETSUJOKU` and `github-actions-windows` to Windows. Other
hosts require an ownership update; a platform label alone is insufficient.
Every step explicitly declares at least its suite's required dependencies.

## Linux Process-Monitored Validation

Use `scripts/run_validation_monitor.py` when a Linux validation needs an
independent process-identity and cleanup verdict. It accepts an argv after `--`
and never evaluates a shell string. It enables child-subreaper behavior, tracks
processes by PID plus kernel start time, checks the system Godot census against
the owned process tree and explicitly allowed cgroups, and signals only owned
pidfds. Forced recovery, an unknown engine, changed tracked source, incomplete
GUT inventory, or surviving owned processes fail the run. The report and
combined command log are unique retained artifacts; a prior run is never
overwritten.

For a complete host-wide Godot census, run the monitor as root and use
`--run-as-sudo-caller` so the validation command itself returns to the invoking
user. Supply exact known service cgroups with repeated `--allowed-cgroup`
options; do not allow broad process-name patterns. Unreadable `/proc` identity
data fails closed. The runner does not install a service, change system
configuration, or terminate processes it cannot prove it owns. M4's workload
harness retains its own exact Docker cgroup and container cleanup checks; the
generic monitor qualifies the separate GUT command.

The runner is reusable for bounded Linux test/build commands that meet the same
process-ownership contract. It is not a Windows/macOS supervisor, a replacement
for workload-specific resource cleanup, or proof that the command's product
acceptance criteria passed. See [#1411](https://github.com/vnvalentin/project0/issues/1411)
for the first monitored M4 use and retained acceptance evidence.

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
The regression runner writes JSON for passing and failing runs. CI retains that
report and its console log and runs the separate static audit even after a test
failure; no passing audit overrides a failed regression step.

Existing GUT and service gates remain unchanged. Windows scripts and launcher
tests are inventoried only, not executed by this Linux job. Their native validation
remains Windows-owned; launcher coverage is never standalone gameplay evidence.
No suite is skipped or removed to make the architecture gate pass.

Static dependency checks traverse client scripts/scenes/resources, literal
`res://` references and project `class_name` references through shared helpers.
Canonicalized resource paths (including symlink targets) to server
runtime/persistence and SQLite fail. The existing pure starting
town fixture is an exact path exception, and its dependencies are still checked.
`ResourceLoader.exists` probes are not imports. Comments are not dependencies.

This is a conservative lexical guard, not a full GDScript parser or exported
package audit. Computed resource paths, global extension discovery and actual
packaged contents require native artifact/startup checks on Windows. Do not claim
those checks passed from this report, and do not install Windows SQLite to make a
source-tree harness run. Fix client isolation under its Windows-owned issue.

## Windows Package Boundary

Run the Windows-only package controls on an assigned Windows host with a qualified
Godot 4.7.2 editor; the older `godot` on PATH may not read the current PCK format:

```powershell
pwsh -File scripts/test_windows_client_validation.ps1 -GodotPath $GodotPath
pwsh -File scripts/verify_standalone_package.ps1 -Version $Version -PackageRoot $PackageRoot -GodotPath $GodotPath -Windowed
```

The first command creates native PCK fixtures and records positive and negative
controls under `build/validation/windows-client/<run-id>/`. It proves the package
gate, not gameplay. The second verifies an existing immutable standalone archive,
audits its actual PCK, then runs its compiled native client probe. It records
evidence under `build/validation/standalone-package-<version>-<run-id>/` and proves
only the client/package behaviors asserted by that probe.

Both require Windows PowerShell 7 and the Windows Godot editor, not SQLite,
Canon, Ollama or a local server. The audit mounts the pack in an isolated project
without running its scripts. It rejects server resources outside the manifest's
exact data exceptions, SQLite, and unapproved native libraries/extensions,
including unreferenced files and compiled-script remaps. Native dependencies
require a reviewed ownership change; renaming a library is not an exemption.
The standalone builder performs this audit before publishing its output.

For a PCK-only check, use `scripts/check_windows_client_package.ps1` with
`-PackPath`, `-GodotPath` and a new `-OutputPath`. Each result records host,
command, ownership/engine/inspector/package hashes, native inventory, failure
reason and cleanup. Evidence paths are not overwritten. Setup failures retain
JSON when an output location is available. Only owned processes/temp state are
removed; existing packages and development services are unchanged.

Package inventory, synthetic negative controls, and the compiled offline probe
are not paired-runtime evidence. Preserve the package's original source identity;
running a new validator against it does not rebuild or re-identify that client.
The package controls do not replace the other inventoried Windows or Linux tests.
The builder lifecycle regression is `scripts/test_build_current_deployment.ps1
-GodotPath <qualified-editor.exe>`: its exporter/EXE remain lifecycle fixtures,
while PCK creation and dependency inspection use the real editor. The builder's
optional `-PackageInspectorPath` supports that separation; ordinarily it defaults
to the same qualified editor supplied as `-GodotPath`.

The builder regression retains twelve named case results, exact commands and
allowlisted fixture inputs, source/tool hashes, generated tools and native audit
logs outside its temporary fixture. It verifies retained hashes after cleanup.
Run both `-BuildShell powershell` and `-BuildShell pwsh` for the supported caller
paths. Reports are `build/validation/standalone-packaging-tests-<run-id>.json`,
with retained artifacts in the matching directory. Interrupted or unexecuted
cases do not count as passes.

## Windows Transport Containment

`scripts/run_paired_validation.ps1` runs each SSH/SCP operation inside a Windows
Job Object. The worker waits for its request until job assignment succeeds;
termination checks that the job has no active processes. Closing the job when
the coordinator exits also terminates its contained descendants. Local client
and private-file cleanup precedes remote cleanup; an unreachable remote remains
unverified, never an inferred successful teardown.

The transport worker is the built-in unpackaged
`System32/WindowsPowerShell/v1.0/powershell.exe`, not the coordinator's executable
and not a PATH-selected `pwsh`. In #1244's controlled Windows probe, Store/MSIX
PowerShell belonged to the job but its unpackaged native descendants did not.
The built-in host contained the same native child and grandchild with unchanged
job flags and security settings. The SSH helper therefore executes as a script
inside that worker, not through a nested Store PowerShell process. Do not remove
compatibility/security settings or weaken host-key checks to make containment pass.

`-TransportTimeoutSeconds` defaults to 15 seconds per operation, followed by
bounded teardown. SCP is noninteractive with strict host-key checking. An ASCII
base64 request preserves Unicode arguments across PowerShell versions; scripts
receive named parameters and native executables receive argument arrays.
Results retain worker path/hash, PID, job assignment/empty state and timeout status.

Run `pwsh -NoProfile -File scripts/test_windows_paired_transport.ps1` on Windows.
Its six local-only controls cover success, transfer/status/cleanup stalls,
parent-first exit and coordinator termination with a live native descendant.
They assert pinned worker identity, private-state deletion and no surviving
fixture processes, including paths containing spaces and Unicode. The fixture
uses substituted transport/engine processes: it neither contacts Linux nor proves
paired gameplay. Evidence is retained under
`build/validation/windows-transport-<run-id>/`.

Two optional mutation controls deliberately alter only the temporary coordinator
copy: `-PackagedWorkerNegativeControl` restores the caller-selected host, and
`-DisableKillOnCloseNegativeControl` removes the job's kill-on-close flag. Each
must exit nonzero and retain a failed verdict with successful independent cleanup.
The coordinator-death control kills only the coordinator and observes descendant
exit before any fallback cleanup. Fallback termination never turns a failure into
a pass. Production files and host security settings are unchanged by these controls.

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
