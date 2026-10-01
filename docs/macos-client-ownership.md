# macOS client component ownership

Governing issue: [#1353](https://github.com/vnvalentin/project0/issues/1353).
Decision: [ADR 0013](adr/0013-macos-component-ownership.md).

On 2026-10-01 the user approved a standalone universal macOS app, Mac packaging
and offline client regression, and the ownership additions needed to run that
scope locally. Linux/Windows access was explicitly deferred because those hosts
are on another person's local network. Their address is not an execution grant.
Final delivery, gameplay and player experience remain unaccepted until their
own evidence exists.

## Owned local scope

`scripts/validation_ownership.json` adds the exact Mac host
`Philips-MacBook-Pro-2` and disjoint suites:

| Suite | Selections | Required dependencies | Evidence |
| --- | --- | --- | --- |
| `macos-tooling` | `scripts/macos/test_*.py` | Python, Git | Mac component regression |
| `macos-client` | `scripts/macos/package_inventory.gd`, `scripts/macos/offline_probe.gd` | Godot client, Python coordinator, Git | Package audit and offline native client probe |
| `macos-admission` | `scripts/macos/admission.py`, `scripts/macos/admission_probe.gd` | Godot client, Python coordinator, Git | Bounded public pre-auth client admission |
| `macos-published` | `scripts/macos/published.py`, `scripts/macos/published_inventory.gd`, `scripts/macos/published_admission_probe.gd` | Godot client, Python coordinator, Git | Unchanged published PCK audit, Mac bundle and pre-auth admission |

The Mac client retains the existing client authority boundary: presentation,
input and disposable prediction only. No SQLite, Canon persistence, Ollama,
server startup or authoritative gameplay code may enter its package. The
existing exact pure-data starting-town fixture exception remains subject to
dependency inspection. Package assembly, audit, execution, evidence retention
and cleanup run within one non-interactive owned lifecycle.

Mac packaging explicitly uses the supplied Godot 4.7.2 editor and matching
universal macOS release template under `build/tools/godot/`. It does not install
an engine globally or use the Windows packaging scripts. A successful Mac
component report does not prove that an Intel Mac ran the app, a live server
accepted it, or a player approved its visual/input behavior.

The user's game-entry defect report also authorizes client-side admission
diagnosis against the configured public default `192.69.180.236:9999`, recorded
in [#1353](https://github.com/vnvalentin/project0/issues/1353#issuecomment-5937286309).
The separate `macos-admission` runner stages the same client source/version with
fresh user/editor state and invokes the real connection and admission waiters.
It stops before authentication/assertion presentation, reads no user settings,
credentials or logs, and captures only allowlisted connection/admission/version
metadata. Engine output is discarded before capture. It never executes server
commands or contacts the deferred private hosts. A successful admission report
does not establish Character assertion acceptance or gameplay. The original
offline package evidence and broader host/merge gates remain separate.

The real public admission test confirmed an RPC checksum mismatch in the
source-built `0.12.0` app. The Mac-only compatibility countermeasure packages
the exact publicly published `0.14.20` PCK with the qualified universal Mac
engine. The fixed anonymous deployment manifest and two-member Windows ZIP
are bounded and hash-verified; the Windows executable is never run. A data-only
Mac inventory rejects server/native/SQLite dependencies before packaged scripts
execute. The original app and reports are preserved. The published manifest
reports a dirty source tree, so its source commit cannot establish equality
with the PCK; retained manifest and PCK hashes bind artifact custody instead.

The separate published-pack lifecycle owns download, audit, isolated native
admission, universal bundle assembly, signing checks, archive fingerprints and
cleanup. It refuses existing outputs and captures only bounded admission
metadata, with engine output discarded. Normal standalone Character-to-world
entry requires separate computer-use evidence. Neither pre-auth admission nor
startup is a claim of gameplay, Intel runtime, or full cross-host regression.

## Separate Mac static preflight

After independent source review, run on the assigned Mac before any selected
Mac regression or app execution:

```sh
python3 scripts/macos/preflight.py --plan .scratch/macos-client/validation-plan.json --output build/validation/macos/preflight-1353.json
```

This is a new Mac-owned static entry point for the explicitly approved scope.
It does not execute the existing Linux-only ownership suite locally, and does
not relocate any existing test. It checks the observed Darwin/assigned host,
component-only plan, exact Mac suite selections with single ownership,
repository-relative existing test files, required declared dependencies,
concrete evidence paths and Mac entry commands. Server dependencies and
paired-runtime plans fail closed. `.local` is the only accepted hostname suffix.
The command never launches a test, Godot, a server, SSH/SCP or an installer.

The report records plan, manifest and preflight hashes and always reports
`runtime_executed: false` and `paired_acceptance: false`. Exit 0 confirms static
validity only; it grants no execution authority. Runtime acceptance requires
actual results within the user's approved scope. Evidence outputs refuse
overwrite. Use new paths for subsequent
runs and update the issue/plan before executing changed selections.

No original Linux/Windows host or suite entry is changed. Existing
`docs/validation-ownership.md`, Linux/Windows runners and CI source-routing
rules retain their force. Unknown/multiple ownership is still a failure. The
Mac additions are not permission to label Mac code Windows-required or to
execute a Windows-required branch elsewhere.

## Pending evidence and rollback

The governing issue and Project #2 carry status, evidence, blockers and next
actions. `.scratch/macos-client/issue.md` is a planning reference, not a second
active record. Independent review precedes this bootstrap preflight; runtime
evidence must bind to the final source/tool/package identity.

Linux full GUT, record-sync and server behavior, Windows native regression,
paired gameplay, and human visual/input acceptance remain separate pending
gates. Deferring access does not pass or remove them, and the branch must not
merge before the repository delivery gate is green. Rollback removes only the
new Mac code/metadata and uniquely owned temporary processes/files; retained
evidence and existing packages are preserved. It does not change a server,
credential store, host security setting, Windows installation or shared data.
