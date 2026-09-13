Type: grilling
Status: unclaimed
Blocked by: 02, 05, 07

## Question

Decide how a **verified** patch is applied, how the client **relaunches** into
the new version, and how a **failed or interrupted** patch recovers.

Resolve:

- **Apply mechanism**: runtime pck load vs self-replace-and-relaunch (per
  research [02](02-research-godot-pck-and-windows-self-replace.md)). For a
  portable Windows client with no installer: in-process
  (`load_resource_pack`) vs a small launcher/updater helper that swaps files
  while the game is exited and relaunches.
- **Atomicity**: download-to-temp, verify ([07](07-integrity-and-trust.md)),
  then an **atomic swap** (`DirAccess.rename`) so an interrupted patch never
  leaves a half-written exe/pck. Keep the prior known-good build for rollback.
- **Rollback trigger**: if the new build fails to launch or fails its own
  post-patch version handshake, revert to the prior build.
- **Tester-facing flow**: what the tester sees (progress, relaunch) — a
  `prototype` of the update/relaunch screen may be warranted.

Depends on the runtime-apply research
([02](02-research-godot-pck-and-windows-self-replace.md)), the patch unit
([05](05-patch-unit.md)), and integrity ([07](07-integrity-and-trust.md)).
Feeds the consolidated spec.
