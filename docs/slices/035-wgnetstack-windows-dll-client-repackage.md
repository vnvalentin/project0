# Slice 035: wgnetstack Windows DLL cross-compile + client repackage (S3b)
GitHub issue: #95

Status: delivered (build + package: the wgnetstack GDExtension cross-compiles
to a valid PE32+ Windows DLL and the portable Windows client package bundles
it alongside `Project0.exe`; the Windows *runtime* spawn-through-tunnel proof
over the public WAN is now user-confirmed, 2026-09-14 — see WAN runtime proof
below)

Tracker context: Phase 11 — Public game access; advances
[P-024](../FEATURE-LIST.md#p-024-public-game-access-via-opnsense-native-wireguard).
Completes the client-side half of the in-process tunnel design: after
[Slice 034](034-wgnetstack-godot-gdextension-tunnel-integration-linux.md)
proved the `WgNetstack` GDExtension tunnel in-process on Linux, this slice
cross-compiles the same extension to a Windows DLL and rebuilds the portable
Windows client so a remote tester runs one executable with the tunnel
available — no WireGuard app, no admin, no separate process. Planning ticket:
[map](../../.scratch/wan-wireguard/map.md), decision
[02](../../.scratch/wan-wireguard/issues/02-godot-gdextension-wireguard-netstack.md).

## SDD

**Problem.** The tester machine is Windows, but Slice 034 only built and
proved the GDExtension on Linux. There is no Windows `wgnetstack.dll`, and the
existing `Project0-client-windows-x64` package predates the extension, so a
Windows tester cannot yet run the client with the in-process tunnel.

**Outcome.** The `native/wgnetstack` Go bridge cross-compiles to a Windows
static c-archive (`libwgnetstack.windows.a`) via mingw-w64, the godot-cpp
GDExtension cross-compiles to `libwgnetstack_gdext.windows.template_release.x86_64.dll`
linking that archive plus the Windows system libraries the Go runtime needs,
the `.gdextension` declares the Windows library, and the portable Windows
client export bundles the extension so the tester's single `Project0.exe`
loads it. Tunnel activation stays the same env-gated seam delivered in Slice
034 (default off; direct connect unchanged).

**Boundary.** Build-and-package only:

- The Go Windows c-archive Makefile target and the SConstruct Windows branch.
- The `.gdextension` Windows library paths.
- The Windows client export including the extension + DLL.

It is explicitly **not**: the Windows *runtime* proof (the actual
spawn-through-tunnel on a Windows host, which requires a Windows machine and is
the tester's evidence, tracked as open), per-tester key/config provisioning
(S4 enrollment), revocation (S5), or the stop-on-disconnect refinement noted in
Slice 034.

**Public seams.** `native/wgnetstack/Makefile` (`windows`/c-archive targets),
`native/wgnetstack/gdext/SConstruct` (Windows branch), the
`addons/wgnetstack/wgnetstack.gdextension` Windows entries, and
`scripts/export_windows_client.sh`.

## TDD / validation plan

Native/GDExtension builds have no GUT seam (same posture as Slices 032/034).
Focused validation:

```sh
# Go Windows c-archive
cd native/wgnetstack && CC=x86_64-w64-mingw32-gcc GOOS=windows GOARCH=amd64 \
  CGO_ENABLED=1 GOTOOLCHAIN=local go build -buildmode=c-archive \
  -o build/libwgnetstack.windows.a ./cmd/cgoarchive
# GDExtension Windows DLL
cd native/wgnetstack/gdext && scons platform=windows target=template_release use_mingw=yes
# Portable Windows client with the extension bundled
scripts/export_windows_client.sh <version>
```

Acceptance (this slice): both Windows cross-compiles exit 0; the DLL is a valid
PE32+ x86-64 shared library; the Windows client export completes and its
package contains the `.gdextension` and the DLL alongside `Project0.exe`. The
Linux in-process proof (Slice 034) and the full GUT suite remain green.

**Open (tester-owned):** the Windows client, launched on a real Windows host
with tunnel mode enabled, reaching `connected: player spawned` through the
in-process tunnel over the WAN — the Windows analogue of Slice 034's Linux
proof. Also owed: a tester-facing launcher/config so activation needs no manual
env vars (folds into S4 enrollment).

## Validation Evidence (2026-09-13)

**Go Windows c-archive.** `CC=x86_64-w64-mingw32-gcc GOOS=windows GOARCH=amd64
CGO_ENABLED=1 GOTOOLCHAIN=local go build -buildmode=c-archive` produced
`native/wgnetstack/build/libwgnetstack.windows.a` (17 MB) + header, exit 0 —
wireguard-go/netstack cross-compiles cleanly for Windows.

**GDExtension Windows DLL.** After installing the mingw C++ cross-compiler
(`g++-mingw-w64-x86-64`) and adding a Windows branch to
`native/wgnetstack/gdext/SConstruct` (linking the Windows archive plus the
Windows system libs the Go runtime needs — `ws2_32`, `winmm`, `ntdll`,
`bcrypt`, `iphlpapi`, `userenv`, `psapi`, `advapi32`),
`scons platform=windows target=template_release use_mingw=yes` linked
`build/libwgnetstack_gdext.windows.template_release.x86_64.dll` with no errors.
`file` reports `PE32+ executable (DLL) x86-64 ... for MS Windows`.

**Client repackage.** `scripts/export_windows_client.sh 0.7.0-tunnel` produced
`dist/Project0-client-windows-x64-0.7.0-tunnel.zip` (34 MB) containing
`Project0.exe`, `Project0.pck` (with the `.gdextension` registered — packed
`extension_list.cfg`), and the bundled
`libwgnetstack_gdext.windows.template_release.x86_64.dll`. Godot's exporter
copied the Windows GDExtension library next to the executable automatically.

**No Linux regression.** The `.gdextension` Windows-path correction and the
SConstruct restructure left the Linux extension intact — it still loads
(`class_exists("WgNetstack") == true`, `start`/`stop` present).

**WAN runtime proof (user-confirmed 2026-09-14).** The packaged Windows tunnel
client, launched on a real remote Windows host with tunnel mode enabled,
connected to the home-hosted authoritative server through the in-process
WireGuard split-tunnel over the public WAN and entered the world — the Windows
analogue of Slice 034's Linux proof. This is the tester/user's runtime
confirmation (same evidentiary basis as the DT-003/DT-004 user-confirmed GUI
and two-machine LAN runs); no automated GUT seam covers a live WAN hop. Still
owed for the full Phase 13 exit gate: invite-code enrollment (issue 04) and
revocation/ban automation (issue 06).

## Non-goals (restated)

- Windows runtime spawn-through-tunnel proof (external tester).
- Per-tester key/config provisioning and invite enrollment (S4).
- Revocation/ban lifecycle (S5).
- stop-on-disconnect tunnel teardown refinement (tracked from Slice 034).
- Any OPNsense/host-firewall change (Slice 028).
