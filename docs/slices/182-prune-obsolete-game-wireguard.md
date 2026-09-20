# Slice 182: prune obsolete game WireGuard implementation

GitHub issue: #393
Issue link: https://github.com/vnvalentin/project0/issues/393

## Traceability

- Feature: [P-024](../FEATURE-LIST.md#p-024-public-game-access-via-opnsense-native-wireguard)
- Primary phase: Phase 11, public game access

## Outcome

Remove the obsolete game-access WireGuard implementation now that direct WAN
game traffic and HTTPS/Nakama authentication are the supported paths. Existing
historical slice records remain as append-only delivery history.

## Public seam and invariants

- `NetworkClient.connect_to_server()` continues to connect to the resolved
  direct target without a tunnel mode.
- The Windows launcher starts the packaged client and updater without creating,
  storing, or provisioning WireGuard peer material.
- The enrollment service retains HTTPS login, registration, character, and
  patch routes, but no peer redemption or OPNsense integration.
- The separate OPNsense admin VPN is outside this repository change.

## Non-goals

- Do not remove historical WireGuard slice/ADR records.
- Do not change Nakama gameplay behavior or the direct UDP game endpoint.
- Do not modify the unrelated admin WireGuard service on OPNsense.

## BDD

- Given a packaged Windows launcher, when it starts the client, then it does
  not require a peer configuration, DPAPI tunnel key, or WireGuard DLL.
- Given the enrollment service, when it starts, then it requires only the
  credentials and loopback authority needed for retained HTTPS routes.
- Given a direct client connection, when it resolves its target, then it uses
  the configured direct host and port without tunnel environment variables.

## Validation

- Focused launcher Go tests and enrollment Python tests pass.
- Targeted Godot parse/GUT validation passes for the changed client surface.
- `scripts/check_record_sync.sh` passes with zero errors.
- Full `scripts/run_gut_validation.sh` was attempted on Windows but is blocked
  by the pre-existing missing Windows `godot-sqlite` GDExtension; unrelated
  SQLite/socket tests fail before they can provide a full-suite signal.

## Rollback

Rollback is a revert of this slice before deployment. No database migration or
external permission change is introduced; the old game WireGuard deployment is
not recreated by this change.

## Root-cause learning

- Symptom: full GUT reports only 117/118 scripts ran and cannot load
  `addons/godot-sqlite/gdsqlite.gdextension` on Windows; unrelated socket and
  SQLite tests then fail. The affected seam is repository-wide validation, not
  the removed WireGuard path.
- Hypothesis: the Windows checkout lacks the platform-specific SQLite binary;
  the discriminating check is the engine's `No GDExtension library found for
  current OS and architecture (windows.x86_64)` error.
- Countermeasure: retain Linux-host validation as the full-suite gate; use
  Windows for launcher, Python, and targeted Godot parse checks. No production
  workaround or dependency was added in this slice.
- Regression evidence: launcher Go tests, retained enrollment/operator pytest,
  and targeted Godot parse checks pass. Remaining limitation is the existing
  Windows GUT environment gap, tracked outside this slice.