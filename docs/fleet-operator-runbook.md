# Fleet operator console runbook

The operator console is a LAN-only, read-only current-state surface until the
control executor slices are deployed. It is separate from the public enrollment
and Nakama surfaces.

## Read-only deployment

The services are `operator` and `operator-console`, enabled with the
`operator` profile. On `okami`, port 8090 is occupied by an unrelated service,
so the console binds to LAN port 18090. Start both services with the deployed
Project0 image tag so the operator API includes the merged control adapter:

```sh
export PROJECT0_IMAGE_TAG=sha-91103a2921eec9d849330e5f93738dc516418d4d
export OPERATOR_CONSOLE_PORT=18090
sudo -n env PROJECT0_IMAGE_TAG="$PROJECT0_IMAGE_TAG" \
	OPERATOR_CONSOLE_PORT="$OPERATOR_CONSOLE_PORT" \
	docker compose -f deploy/compose.yml --profile operator \
	up -d operator operator-console
```

The console binds to the LAN address on port 18090 and
mounts these paths read-only:

- `/etc/project0/operator-console/servers.json`
- `/var/lib/project0/ops-snapshots/`

The manifest must use the OpsSnapshot registry contract. The current v1
entries are `project0-game` with `server_type: world` and `project0-login` with
`server_type: login`; each entry uses the `unit` field. Producer containers
write into their per-server snapshot directories, and the console reads the
parent directory read-only.

The console exposes `/healthz`, `/`, and `/server/<server_id>`. Unknown or stale
snapshots are displayed as non-healthy states; they are never treated as live
authority.

The private operator API binds to loopback on port 8099. Invalid bearer
assertions return HTTP 403; valid privileged action proofs remain a separate
operator step and must never be run from public traffic.

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
Remote deployment health, smoke checks, fresh world/login console rows, invalid
assertion rejection, and reversible authorized control proof passed on `okami`.
