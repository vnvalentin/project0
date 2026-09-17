# Slice 074 — Signed Character snapshot in the session assertion (contract + issuer)
GitHub issue: #95

Status: **delivered**

Phase: 10 (Authoritative runtime and action input), advancing
[P-014](../FEATURE-LIST.md#p-014-containerized-fixed-tick-authoritative-server-runtime)
and the [login-boundary decision](../../.scratch/container-platform/issues/02-account-login-service-boundary.md).
Twentieth delivery of the [container-platform map](../../.scratch/container-platform/map.md);
it is the **first sub-slice of the cross-DB Character-data handoff**: the game
server needs the selected Character's presentation data (`display_name`,
`cosmetic`) to bind a Player at world entry, but its DB holds no such record
after the assertion handoff. This slice lets the login authority carry a bounded,
signed Character snapshot inside the selected-Character assertion so the game
server can trust it without a DB lookup or a game→login call.

## User outcome

The selected-Character assertion the login process mints can carry the
Character's `display_name` and `cosmetic`, HMAC-signed alongside the identity
claims, so the game server (which validates the signature) obtains authoritative,
tamper-proof Character presentation data without sharing the accounts database.

## Scope and non-goals

In scope:
- `shared/session_assertion.gd`: additive, backward-compatible `KEY_CHARACTER_NAME`
  (`cnm`) and `KEY_CHARACTER_COSMETIC` (`cos`) claims — always emitted in the
  canonical signed payload, tolerated-and-defaulted on parse for older tokens,
  and bounded (name ≤ `MAX_FIELD_LEN`, cosmetic a Dictionary whose JSON ≤
  `MAX_COSMETIC_JSON_LEN`). No schema-version break.
- `server/assertion_issuer.gd`: optional `character_name` / `character_cosmetic`
  parameters on `issue()` (default empty) that flow into the signed claims.
- The validator needs no change — it returns `parse_payload`'s claims, which now
  include the snapshot.

Out of scope (Slice 075): the login gateway populating the snapshot from the
selected Character; storing it in the game's session; the game's world-entry path
binding the Player from the session snapshot; the e2e proof of cross-process
world entry. This slice only extends the signed contract and the issuer.

## Public seam

- `shared/session_assertion.gd` (`KEY_CHARACTER_NAME`, `KEY_CHARACTER_COSMETIC`,
  `MAX_COSMETIC_JSON_LEN`, extended `build_payload`/`parse_payload`).
- `server/assertion_issuer.gd` (`issue(..., character_name, character_cosmetic)`).

## Safety invariant

The snapshot is part of the HMAC-signed payload, so the game server can trust it
only after signature verification — a tampered name/cosmetic fails validation and
binds nothing. Both fields are bounded (fail-closed on oversize / wrong type), so
an assertion can never carry an unbounded payload. The change is additive: older
tokens without the snapshot still parse (name empty, cosmetic `{}`), so nothing
that already validates breaks.

## ADR rationale

No new ADR. Signed, versioned assertions carrying bounded claims between the
login and game processes are exactly what the login-boundary decision specifies;
this adds a bounded presentation claim, analogous to profile claims in a signed
token, keeping the game server DB-free for accounts/characters.

## BDD / TDD

`tests/unit/test_session_assertion_snapshot.gd`: `issue()` with a name + cosmetic
round-trips through `validate()` into the claims; an account-only `issue()`
yields empty snapshot claims; an oversized name or cosmetic is rejected
(`INVALID_CLAIMS`); a tampered snapshot fails the signature; and an older
snapshot-less payload still parses with defaults (backward compatibility). The
existing assertion suite proves the additive change breaks nothing.

## Validation

- Focused + full suite: `scripts/run_gut_validation.sh` on the Linux host —
  **passed, 55/55 scripts, exit 0** (+1 new
  `tests/unit/test_session_assertion_snapshot.gd`; the existing assertion suite
  proves the additive change breaks nothing). Note: cosmetic travels as JSON in
  the signed payload, so numeric values return as floats — string values
  round-trip exactly.
- `scripts/check_record_sync.sh` exit 0 (6 pre-existing WARN).

## Root-cause learning

None yet.
