# Slice 110 - Ship the Linux wgnetstack GDExtension in the server image

Status: **delivered**

GitHub issue: #92

Phase: 7 (Delivery workflow capabilities), resolving
[DT-014](../TECHNICAL-DEBT-TRACKER.md#dt-014-container-images-ship-without-the-wgnetstack-gdextension).

## User outcome

The authoritative server and login server boot with a clean log. Previously
every boot opened with four GDExtension load errors for a library the image did
not contain, which is the kind of persistent false alarm that trains an
operator to skip past startup failures.

## Scope and non-goals

In scope: a cached `gdext-builder` stage in `deploy/game-server/Dockerfile` that
builds the Linux `template_debug` GDExtension, and copying it into the runtime
image before the import cache is baked.

Out of scope: the Windows DLL (already built by
`scripts/package_client_linux.sh`), the `template_release` Linux target, and any
server-side use of the tunnel bridge — the library is now loadable, not called.

## Public seam

`ghcr.io/vnvalentin/project0-godot:<tag>` now contains
`native/wgnetstack/gdext/build/libwgnetstack_gdext.linux.template_debug.x86_64.so`.

## Design notes

- Only `template_debug` is built. The image runs the headless **editor** binary,
  which resolves `linux.editor.x86_64` in
  `addons/wgnetstack/wgnetstack.gdextension` to the template_debug library —
  that is precisely the path the boot errors named.
- The builder stage copies only `native/wgnetstack` and pins the godot-cpp
  revision, so it depends on neither application code nor the delivery records
  and stays cached while ordinary changes ship.
- godot-cpp is pinned to `d5cc777`, the revision the shipped extension was built
  against in Slice 035, rather than tracking branch `4.3`.
- The `.so` is copied in **before** `godot --headless --import`, so the baked
  import cache records a successful extension load rather than a failed one.
- Debian's `golang-go` cannot parse this module's `go` directive, so the stage
  installs the upstream Go toolchain explicitly instead of trusting the distro.

## Safety invariants

- The runtime image gains one library and no new packages; the build toolchain
  stays in the discarded builder stage.
- The extension is loadable but unused by server code, so this changes no
  gameplay behaviour.
- Pinned godot-cpp revision and pinned Go version keep the build reproducible.

## Acceptance scenarios

1. Given a built image, then the Linux GDExtension is present under
   `native/wgnetstack/gdext/build/`.
2. Given the game or login container starts, then no
   `GDExtension dynamic library not found` or `Error loading extension` is
   logged.
3. Given application code changes, then the builder stage is served from cache.

## Validation

Focused validation: image build and container boot on okami, counting the
specific error lines that DT-014 recorded.

## Validation evidence

- Image built on okami; the runtime image contains
  `libwgnetstack_gdext.linux.template_debug.x86_64.so` (6,965,392 bytes).
- Game and login containers started from that image: the count of
  `GDExtension dynamic library not found` **and** `Error loading extension`
  lines in the boot log is **0** (previously four lines at every boot).
- Boot log now opens directly with
  `[entrypoint] ... starting` → `Godot Engine v4.3.stable` →
  `Starting town hub fixture validated: 28 structures.`
- Host restored to the released tag afterwards: `v0.1.3` deployed with both
  smoke checks passing.

## Root-cause learning

- Symptom: `GDExtension dynamic library not found:
  .../libwgnetstack_gdext.linux.template_debug.x86_64.so` at every container
  boot, for both Godot processes.
- Confirmed root cause: `native/wgnetstack/gdext/build/` is gitignored, so the
  library was never in the build context. The server does not call the bridge,
  so the failure was non-fatal and was accepted as noise.
- Why it mattered anyway: these errors were present in the login server's log
  throughout the WAN outage investigated in Slice 106. Persistent expected
  errors reduce the signal value of an authoritative server's log exactly when
  it is needed.
- Countermeasure: build the library in a cached image stage rather than
  shipping an image whose declared extensions cannot load.
- Remaining limitation: the first build of the stage on a cold cache costs a
  full godot-cpp compile. It is keyed to `native/wgnetstack` and the pinned
  revision, so it should be paid rarely.

## Record links

- Resolves: [DT-014](../TECHNICAL-DEBT-TRACKER.md#dt-014-container-images-ship-without-the-wgnetstack-gdextension)
- Feature: [P-014](../FEATURE-LIST.md#p-014-containerized-fixed-tick-authoritative-server-runtime),
  [P-024](../FEATURE-LIST.md#p-024-public-game-access-via-opnsense-native-wireguard)
- Prior slices: [105](105-container-images-and-registry.md), [109](109-host-assumption-sweep.md)
- Phase tracker: [PROJECT-TRACKER.md](../PROJECT-TRACKER.md#phase-7--delivery-workflow-capabilities)
- Registry: [SLICE-REGISTRY.md](SLICE-REGISTRY.md), reservation 110
