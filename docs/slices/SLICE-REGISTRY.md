# Slice & Feature Number Registry

Single source of truth for slice-number (and new feature-id) allocation, to
prevent collisions when more than one agent works this repository in parallel.

Created after two agents independently allocated **Slice 027 and 028** on
2026-09-13 — a classic "read the max, pick the next" race with no shared lock,
which produced duplicate slice files and duplicate tracker entries.

## Allocation rule

1. **One integrator owns allocation.** Exactly one agent/role assigns slice
   numbers and owns the delivery trackers (`docs/PROJECT-TRACKER.md`,
   `docs/FEATURE-LIST.md`). Parallel workers do **not** invent slice or feature
   numbers — they receive them from the integrator (or from their reserved
   block, below).
2. **Reserve before you create.** Before writing a `docs/slices/NNN-*.md`,
   append a row to the Allocations table below. The next free number is the
   invariant `max(existing docs/slices/ numbers, this table) + 1`. Reserving is
   one small commit; if two workers race, the second sees the first's row (or
   its file) and takes the next number.
3. **New feature ids** (`F-<n>`) follow the same reserve-first rule: take the
   next unused `F-` number and record it in `FEATURE-LIST.md`.

## Reserved blocks (only needed when a parallel autonomous worker is running)

If a second, autonomous agent (e.g. a long-running `claude -p` loop) runs
alongside interactive work, give it a reserved block **and disjoint files** so
the two can never collide:

| Block | Workstream |
| --- | --- |
| 001–099 | Primary / interactive gameplay slices (the default). |
| 100–199 | Reserved for a parallel autonomous worker (e.g. the WAN/infra loop). |

Within a block, allocation stays sequential.

## Allocations

Slices 001–026 are the linear delivery history (see `docs/slices/`). The
contended range and everything after it is tracked explicitly:

| Slice | Title | Workstream |
| --- | --- | --- |
| 027 | Agent-assisted delivery orchestration (P-004) | autonomous CLI |
| 028 | WireGuard remote-access infrastructure foundation (P-024) | autonomous CLI |
| 029 | Authoritative monster melee damage and death broadcast (IP-023) | autonomous CLI |
| 030 | Server-side wall and building collision (F-027) | interactive |
| 031 | Bigger rural village with NPC and leader housing (F-026) | interactive |
| 032 | wgnetstack netstack bridge, Linux prototype (P-024) | autonomous CLI |
| 033 | Client monster replication and rendering (IP-023) | interactive |
| 034 | wgnetstack in-client GDExtension + tunnel integration, Linux (P-024) | interactive |
| 035 | wgnetstack Windows DLL cross-compile + client repackage (P-024) | autonomous CLI |
| 036 | Imperial world-scale measurement contract — WorldScale (F-028) | interactive |
| 037 | World-scale constant relabel: meters → yards (F-028) | interactive |
| 038 | Shared server-owned SQLite persistence foundation, Wave 4 (F-029) | interactive |
| 039 | Accounts and characters persistence repository (F-030) | interactive |

Next free slice: **040** (verify against `docs/slices/` before reserving).

> Collision history: on 2026-09-13 the interactive and autonomous workstreams
> each allocated 027 and 028. Resolved by renumbering the **interactive** slices
> — the collision slice 028→030 and the village 027→031 — leaving the autonomous
> CLI slices at their original 027/028. Going forward, run parallel autonomous
> work in the 100–199 block to avoid a repeat.
