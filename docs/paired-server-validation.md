# Paired Server Validation

Owner: [#1260](https://github.com/vnvalentin/project0/issues/1260), Linux component
of #1244. This is not #1242 town-exit or #1213 player acceptance.

## Boundary

Run every command below on `okami` (`192.168.1.254`) through the approved SSH
helper. The implementation branch contains only Linux validation files. Do not
check out a Windows-required branch on Linux. No downloads, deployment, shared
Canon, auth bypass, or client execution is involved.

`scripts/paired_server.py` supervises a fresh real `server_main.gd` instance.
The fixture subclasses that entry point only to issue a short-lived assertion
through `AssertionIssuer`, check the real validator's valid/tampered/expired
paths, and observe admitted character/input state. It does not implement an
alternative server, authentication, movement, or persistence path.

The pinned Godot 4.3 image supplies the runtime, not its older baked source:
`sha256:801341fea24b22777e65e8ad5b38ca306c33e59b4adcdc14c37d8f461b162602`.
Preparation copies an explicit allowlist from the Linux source: server/shared
GDScript and the spatial JSON schema, Linux SQLite libraries/descriptor, Nakama GDScript, six existing RPC
autoload dependencies under client/, and the fixture. A minimal project loads
the real server's RPC autoload without a client scene. No Windows executable,
library, branch, test or presentation runtime is transferred or executed.
`manifest.json` lists every file SHA-256, source commit, runtime and image.
Publish this manifest and its hash on the issue before runtime execution.

## Protocol V1

Prepare once, then publish the emitted hash and full manifest:

```sh
python3 scripts/paired_server.py prepare --artifact "$PWD/build/paired-server-artifact-v1"
```

Start with the actual client executable/package hash, declared version and engine:

```sh
python3 scripts/paired_server.py start \
  --artifact "$PWD/build/paired-server-artifact-v1" --artifact-sha256 MANIFEST_SHA256 \
  --run "$PWD/build/validation/paired-UNIQUE" --correlation-id UNIQUE \
  --client-sha256 CLIENT_SHA256 --client-version 0.14.14 --client-engine 4.7.2 \
  --deadline-seconds 180 --readiness-seconds 45
python3 scripts/paired_server.py status --run "$PWD/build/validation/paired-UNIQUE"
```

`start` detaches a bounded Linux supervisor and returns `accepted`, not readiness.
The caller polls `status` within its own bound until `ready` or terminal failure.
The fresh UDP port is published only on the designated LAN address, inside an
owned private bridge network with a return route to the Windows LAN client.
Docker's port bind must succeed after the
reservation check; there is no fallback to a shared port. All signing, storage,
import cache, Canon and generation stay inside owned Linux state. No LLM service
is used for this in-town scenario.

Readiness requires advancing, fresh healthy ticks, actual engine identity,
real SQLite schema and at least one persisted Canon sector, plus successful
issuer/validator controls. It does not prove Windows rendering, admission,
input acknowledgement, player feel, or engine interoperability.

Ready/final reports carry `schema_version: 1`, unique `run_id`,
`scenario_id: authenticated-input-ack-v1`, `correlation_id`, exact `client_build`
and `server_build`, `host`, `port`, deadline, readiness facts and cleanup.
Use identities from the **ready** report, not the initial accepted report.
Server build includes manifest hash, source commit, image, engine and RPC hash.
Different engine versions are explicitly recorded, never assumed compatible.
The client must pass the normal version handshake, session assertion, world
entry, and input ACK before any compatible paired result can be claimed.

## Private Handoff

After readiness, the coordinator copies only `RUN/private/assertion` directly
over authenticated SCP into an ACL-restricted, coordinator-owned temporary
file. Capture neither file content nor SCP payload in model/tool output. Do not
use `cat`, console output, command-line token arguments, report fields or public
artifacts for this bearer. The signing key exists only in the Linux Godot process;
it is never written or transferred. The assertion expires after 180 seconds and
is useless against other runs' independent keys.

The native Windows probe reads the private file and calls the real NetworkClient
seams: connect to report host/port, wait for version admission, call
`submit_present_assertion`, require `session_established_received("ok")`, call
`submit_enter_world`, require `world_entry_received("ok", ...)`, send sequenced
input and observe `authoritative_position_received(..., sequence >= 0)`.
No call to `gameplay_test_session.begin()` or server startup is allowed on Windows.
Keep the client connected until the finish request is acknowledged. Delete the
local bearer in the coordinator's `finally` path on success and failure.

## Finish And Abort

Upload a sanitized client evidence JSON with the six identity fields copied
exactly from readiness, plus `status: passed`, Unix `observed_at`,
`authenticated: true`, `world_entered: true`, and integer `input_ack_sequence`.
No credentials, account names or free-form client logs belong in that file.

```sh
python3 scripts/paired_server.py finish --run RUN --evidence CLIENT_REPORT.json
python3 scripts/paired_server.py abort --run RUN
python3 scripts/paired_server.py status --run RUN
```

Missing, stale, mismatched or failed evidence is rejected. A syntactically valid
client pass also requires the issued character's real persisted journey and
matching authenticated input state observed on the Linux server. Finish returns
`requested`; poll for terminal `server_passed` and `cleanup.passed: true`.
The Windows coordinator still owns the combined verdict; `paired_acceptance`
is always false in server-only reports. No parent issue is auto-closed.

Abort, SIGINT/SIGTERM cancellation, deadline, runtime exit, failed readiness or
disconnect ends the run and records the reason. Cleanup stops/removes only the
uniquely named owned container/network and private tree. Cleanup failure overrides
success and lists outstanding resources. Reports and redacted log fingerprints
remain under RUN; raw private storage and bearer are deleted. Runtime errors are
counted separately in import/runtime logs, not hidden or called clean. The pinned
engine importer reports a retained resource-at-exit diagnostic; its count and
fingerprint are separate from live-server errors and do not prove clean import.
An independent container timeout bounds
runtime if the supervisor dies. SIGKILL/host failure cannot guarantee immediate
host-file cleanup: retained owned paths must be inspected by the Linux owner,
and such a run cannot pass from a partial report.

## Checks

```sh
python3 -m unittest scripts.test_paired_server
PAIRED_LIVE=1 PAIRED_ARTIFACT="$PWD/build/paired-server-artifact-v1" \
  PAIRED_RESULTS="$PWD/build/validation/paired-controls-UNIQUE" \
  python3 -m unittest scripts.test_paired_server
bash scripts/check_record_sync.sh
RESULT_DIR="$PWD/build/validation/gut-1260" \
  DASHBOARD_RESULTS_DIR="$PWD/build/validation/gut-mirror-1260" \
  bash scripts/run_gut_validation.sh
```

Live controls declare a zero client hash explicitly as server-only test metadata;
they never claim a native client ran. They test real readiness/auth/storage and
failure cleanup independently of Windows. Retain failed runs before repairs.
Independent review and the producer's PR/merge gate remain required.