# First-run onboarding and account setup flow

Status: open
Assignee: (unassigned)
Type: grilling
Blocked by: 01-prior-art-eqemu-and-launcher-patterns, 02-lan-wan-mode-selection-checkbox

## Question

Define the guided first-time/new-user flow the unified launcher presents, reusing
the existing enrollment/assertion plumbing rather than rewriting it.

Decide:

- **WAN first-run**: the ordered steps (login prompt -> signed account assertion
  -> WireGuard peer redemption -> DPAPI key protection -> launch), how they are
  presented in the launcher's UI surface (ticket 02), and where the
  `--invite-code` fallback fits.
- **LAN first-run**: what onboarding a LAN user needs given the ENet login path
  and no tunnel/enrollment (account selection, host entry), and how it differs
  from WAN.
- **Returning user**: how the launcher detects an already-enrolled device
  (existing `peer.json` + protected key) and skips straight to launch, and where
  version/patch checks sit relative to onboarding.
- **Account creation entry point**: how a brand-new user with no account is
  routed. Whether the launcher itself offers registration or directs the user
  elsewhere is the subject of ticket 06; this ticket defines the *flow shape*
  and where that entry point lives.
- **Credential handling**: reaffirm no persistence of the password beyond the
  in-flight request, matching the current launcher/`account_gate` behavior.

## Required decision output

An onboarding flow spec for WAN and LAN first-run and returning-user cases, with
the account-creation entry point located but its policy deferred to ticket 06.

## Answer

_(unresolved)_
