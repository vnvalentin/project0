# Planning reference: #1353 standalone macOS client

Active record: https://github.com/vnvalentin/project0/issues/1353 and GitHub
Project `Project0 Delivery` #2. This local ticket refines the implementation
brief; it does not own delivery status or replace GitHub evidence.

## Orientation and approved scope

- Base revision: `4f112ec26163531870c9cd505ef32c24411eed5a`.
- Branch: `slice/1353-macos-client`.
- Shared Harness guidance consumed:
  `77de008a0f28eb91726527d543adb435735a2157`.
- Foundation checklist is complete, marker absent, and active foundation
  placeholder scan found no matches. Current record-sync evidence is pending.
- The user approved a standalone universal Mac app, Mac packaging/client
  regression and required local ownership additions on 2026-10-01.
- Linux/Windows host access is explicitly deferred. No connection to either
  host is within this local execution scope.
- This is standalone platform support with no new gameplay milestone
  commitment or invented parent/group; applicable relationships remain owned
  by #1353 and the active Project record.

## User outcome, design and behavior

The user can build and launch a universal `Project0.app` from this Mac and retain
repeatable Mac component evidence. The smallest slice stages the existing client
and pure shared dependencies, audits the exported package, then runs an offline
native probe through the packaged release engine. It preserves the authoritative
server boundary and existing Windows delivery paths.

Public seams are the Mac package CLI, its static plan preflight, exported PCK
inventory and packaged offline client probe. The hypothesis is that the existing
Godot client can run unchanged on macOS when only client-owned resources and the
qualified universal release engine are packaged. The cheapest discriminating
check is passing the reviewed Mac-only static plan and Python packaging controls
before building or running the app.

Behavior scenarios and acceptance:

- A valid owned Mac plan passes static preflight; wrong hosts, non-Mac suites,
  conflicting ownership, undeclared/server dependencies and paired plans fail.
- Qualified inputs produce a version-stamped universal app and fresh evidence;
  missing inputs, unsafe package contents, export diagnostics or probe failure
  fail closed and retain failure evidence.
- The compiled offline probe loads packaged client contracts, verifies its
  own version and client presentation checks without starting a network peer.
- Every path cleans up only its owned staging/process state; existing outputs
  are never overwritten.
- Full Linux/Windows and paired regression remains awaiting its host evidence.
  Standalone success is not a claim of player or final delivery acceptance.

Unacceptable outcomes are packaged server authority/SQLite/Ollama, secret
capture, unauthorized network access, false regression/runtime claims,
overwritten evidence/packages, leftover owned processes or weakened merge gates.
Non-goals are login/live gameplay, server deployment, Windows changes, signed
distribution/notarization, global dependency installation and cross-host tests.

## Validation, review and rollback

Machine-readable selections: [validation-plan.json](validation-plan.json).
Ownership decision: [ADR 0013](../../docs/adr/0013-macos-component-ownership.md).
Local instructions: [Mac ownership](../../docs/macos-client-ownership.md).

Independent ownership/source review precedes Mac preflight and execution.
No runtime checks are claimed by this planning ticket. Actual commands, host,
source/tool/package fingerprints, pass/failure results and cleanup belong in the
governing issue. Root-cause learning for unexpected failures must be recorded
there before completion; existing evidence is preserved during repairs.

Rollback is limited to the additive Mac files/metadata and owned staging and
process state. Original Linux/Windows manifest entries, existing packages,
external services and shared data remain outside that rollback scope. The PR
uses `Refs #1353` while mandatory cross-host or delivery evidence is pending.

## Frontier and next actor

The implementing agent next performs independent source review, runs the Mac
static preflight, then the exact Mac component commands in the owned plan.
Linux/Windows owners supply their deferred evidence only under a later access
grant. The governing issue must remain open or explicitly blocked until its own
acceptance and required delivery gates are satisfied.

## Game-entry investigation

Computer use confirmed the user's `server_admission_timeout` on the Character
screen. [Issue checkpoint](https://github.com/vnvalentin/project0/issues/1353#issuecomment-5937286309)
owns the expanded bounded public client diagnosis and unresolved root cause.
The exact preflight/commands/evidence are in `admission-plan.json`. Native
admission tests read no user settings or credentials and stop before assertions;
they do not prove authenticated world entry. Private host access stays deferred.

The native public test at clean `1cb76ebba6bb5a8d2c9afbdee0f7b45fd31aa58a`
confirmed an RPC checksum mismatch before admission. The issue checkpoint
records the focused Mac countermeasure: retain the exact published `0.14.20`
PCK bytes in a universal Mac bundle after a data-only dependency audit, then
verify native admission and the original Character-to-world UI seam. The new
`published-plan.json` owns exact Mac selections; it does not admit Windows
execution or deferred private server access. Published dirty source metadata
does not prove source/PCK equality. Existing apps and evidence remain intact.


## 2026-10-01 native retry frontier

At committed `93204a8a737563242bde00759a5db3f7e166609e`, 32 packaging and36 published controls passed;24 unchanged admission controls remain applicable. Fourth native run stopped in setup with PermissionError when creating uniquely owned validation data under Library/Application Support in the restricted sandbox; no engine or transport started. This was invocation permission, not product or preboot failure. Fifth native selection uses fresh report/output with escalated execution for precisely that owned temporary state, qualified local tools and anonymous public release/admission target. Existing app/evidence and unnamed-project state remain preserved.

Source-only reviews: Spec unnamed-project finding resolved at cbb81c2; source custody findings resolved in93204a8 working diff. Standards process/cleanup fixes are covered by the32 controls. Exact final revision and actual normal Character-to-world runtime acceptance remain required. GitHub checkpoint update prepared but approval review timed out twice before execution; human retry permission requested. Active governing record remains https://github.com/vnvalentin/project0/issues/1353, awaiting evidence/access rather than complete. This local note is a planning pointer and retained handoff frontier, not a replacement delivery record.
