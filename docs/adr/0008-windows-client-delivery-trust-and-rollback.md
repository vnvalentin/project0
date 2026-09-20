---
status: proposed
---

# Windows client delivery: signed patches, mandatory version gate, and rollback

## Context

Phase 16 combines three researched design maps: a unified Windows launcher, a
packaged-client auto-update path, and a controller placeholder. The shipped
client is `Project0.exe` plus a separate `Project0.pck`. A running Godot process
cannot safely replace or hot-reload its active pack, so update behavior is remote
code delivery and must be fail-closed.

**Correction (2026-09-18, measured).** The original wording implied the operating
system would prevent replacing a live pack. It does not. A probe against the real
packaged Windows client found rename, open-for-write, and delete all succeed
while the client is running. The decision below is unchanged, but its
justification is: Godot cannot hot-reload running scripts/scenes/autoloads; lazy
resource loads after a mid-run swap would mix new content with old code; and
since nothing at the OS level protects a live client, the updater's ordering and
transaction marker are the *only* protection against a half-applied swap.

The consolidated handoff is [.scratch/client-auto-update/spec.md](../../.scratch/client-auto-update/spec.md).

Governing issues: [#100](https://github.com/vnvalentin/project0/issues/100),
[#182](https://github.com/vnvalentin/project0/issues/182), and
[#117](https://github.com/vnvalentin/project0/issues/117).

## Decision

1. A generated `shared/client_build_version.gd` inside the `.pck` is the runtime
   client build version. The server owns `PROJECT0_REQUIRED_CLIENT_VERSION` and
the pre-auth version handshake requires exact equality. `schema_version` and
`tuning_version` remain unrelated data-contract terms.
2. The client sends its build version as the first post-connect message. The
server accepts or rejects before login/register. Rejections are bounded:
`CLIENT_OUTDATED`, `MALFORMED`, and reserved `UNSUPPORTED`; outdated responses
carry the required version and HTTPS manifest base URL.
3. V1 patches are full `Project0.pck` replacements. An offline release operator
signs canonical manifest bytes with RSA-3072; the detached signature binds the
required version, pck URL, byte size, and SHA-256. The public key is baked into
the currently trusted client pack. TLS transports bytes but is not the artifact
trust anchor.
4. Verification occurs before apply: verify manifest signature, download to
staging, verify size and streaming SHA-256, then invoke a detached updater. The
updater quits the client, atomically swaps the pack while retaining one `.bak`,
and relaunches.
5. A transaction marker and one prior known-good pack provide recovery from
interrupted swaps, startup failure, relaunch/version-handshake failure, and swap
failure. One retry is allowed per version; repeated failure enters repair-needed
state instead of looping.
6. The unified launcher owns persisted LAN/WAN selection. WAN is the first-run
default and uses existing WireGuard/enrollment/DPAPI plumbing; LAN requires an
explicit host and uses direct ENet login. It never silently changes modes.
7. The controller placeholder targets Windows XInput through Godot's built-in
InputMap/Joypad support. Left-stick movement and south/A attack map to existing
named actions; keyboard/mouse and server contracts remain unchanged.

## Security invariants

- An unverified manifest or mismatched pack is never applied.
- The update URL is not trusted by itself; the baked public key authenticates the
manifest and its pack hash.
- The private signing key is offline and absent from repo, CI, and hosting.
- The previous known-good pack is retained until the replacement passes its
post-patch readiness/version check.
- Passwords, tokens, raw responses, and patch contents never enter telemetry.
- The client cannot bypass the server-owned version gate or alter gameplay
authority through controller input.

## Consequences

The first release requires a trusted initial client distribution and an offline
release-signing operation. Full-pack updates use more bandwidth than deltas but
remove base-version ambiguity and keep verification simple. Key rotation requires
a trusted full re-release in v1. The launcher becomes the stable owner of mode,
onboarding, update, and recovery state; the game client remains focused on
runtime presentation and server-authoritative gameplay.

## Release staging decision

The initial release may ship the trusted packaged client, clean packaged boot,
first-install path, mandatory version gate, and public gameplay path without
enabling or advertising automatic updates. Live update, interrupted-swap
recovery, failed-readiness rollback, and retry exhaustion are post-release
hardening work. The existing updater code and unit tests remain in the tree, but
the auto-update path must not be treated as release-proven until executable
packaged-client evidence covers those transitions.

## Validation obligation

Implementation slices must add public-seam tests for the handshake, manifest
signature and hash failures, staging, atomic restart, interrupted-swap recovery,
rollback exhaustion, LAN/WAN selection, onboarding, and XInput action parity.
Initial-release acceptance requires packaged Windows boot and first-install
runtime evidence. This ADR cannot move to fully `accepted`, and automatic
updates cannot be enabled, until packaged Windows runtime evidence also covers
live update, interrupted-swap recovery, and rollback.
