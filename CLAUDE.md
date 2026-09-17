# CLAUDE.md — pointer

The canonical, tool-neutral systems specification has moved to
[docs/SYSTEMS-SPECIFICATION.md](docs/SYSTEMS-SPECIFICATION.md). This stub exists
only so tools that auto-load `CLAUDE.md` (and the repo's historical references to
it) still find the spec.

Read these, in order, before any implementation work:

1. [docs/SYSTEMS-SPECIFICATION.md](docs/SYSTEMS-SPECIFICATION.md) — the normative
   systems/implementation contract (formerly this file's contents).
2. [AGENTS.md](AGENTS.md) — repository commands, boundaries, sensitive data,
   deployment rules, and agent requirements.
3. [.github/copilot-instructions.md](.github/copilot-instructions.md) — Copilot
   orchestration and delivery-gate specifics.

Any LLM working this repository (Copilot, Claude, or another) should treat
`docs/SYSTEMS-SPECIFICATION.md` as authoritative; do not add spec content here.
