# WAN self-service registration decision (resolve or scope DT-010)

Status: open
Assignee: (unassigned)
Type: grilling
Blocked by: 05-first-run-onboarding-and-account-setup

## Question

"Handle first-time or new accounts" implies creating accounts over the internet,
but public self-service registration is currently **deferred (DT-010)** and the
public surface intentionally exposes login only. Decide whether WAN self-service
registration is in scope for this launcher, and if so, under what controls.

Decide:

- **In scope or not**: does the unified launcher expose account **creation** on
  the public HTTPS enrollment surface, or does account creation remain
  out-of-band (operator-provisioned / invite-only) with the launcher handling
  login + enrollment only?
- **If in scope**: the registration contract on the public surface, the abuse
  controls (rate limiting — relation to DT-009; bot/abuse mitigation; email or
  other verification if any), and the security review gate before the surface
  ships.
- **If out of scope for now**: the explicit account-provisioning path a
  first-time user follows instead, and the note that closes/relates DT-010.

## Required decision output

A decision that either brings WAN registration in scope with its security-gated
contract, or keeps it out and defines the interim account-provisioning path.
Update DT-010 accordingly (or record why it stays open). If registration is
ruled beyond this destination, this ticket is closed to Out of scope on the map.

## Answer

_(unresolved)_
