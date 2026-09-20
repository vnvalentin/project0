# Fleet operator console runbook

The operator console is a LAN-only, read-only current-state surface until the
control executor slices are deployed. It is separate from the public enrollment
and Nakama surfaces.

## Read-only deployment

The service is the `operator-console` Compose service, enabled with the
`operator` profile. It binds to the LAN address on port 8090 by default and
mounts these paths read-only:

- `/etc/project0/operator-console/servers.json`
- `/var/lib/project0/ops-snapshots/`

The console exposes `/healthz`, `/`, and `/server/<server_id>`. Unknown or stale
snapshots are displayed as non-healthy states; they are never treated as live
authority.

## Control boundary

Control actions are not enabled by the read-only console slice. When Slice 189
and the host/Godot executors are deployed, configure the assertion secret only
through host-managed environment configuration. The console must not mint,
modify, or independently trust a control request. The host helper and Godot seam
verify the assertion and scope independently.

## Safety

Never expose the operator console, Nakama Console, PostgreSQL, or host helper to
WAN traffic. Do not place tokens, secrets, passwords, player text, or Canon
mutation controls in snapshots or audit records.

## Rollback

Rollback is the normal Compose deployment rollback for the application image,
plus restoration of the prior host configuration and snapshot directory when a
configuration or schema change is involved. A Nakama database migration always
requires the recorded PostgreSQL backup path; image rollback alone is not enough.

## Current validation

The pure OpsSnapshot, atomic writer, registry scanner, read-only console, control
contracts, and operator assertion verifier have focused automated validation.
A full live operator-control proof remains gated on the host helper and
authoritative Godot control seam.
