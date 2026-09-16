Type: grilling
Status: open
Blocked-by: 01-ops-snapshot-contract

## Question

Decide the **server registry**: how the console discovers which servers exist, where to
read each one's snapshot, and how a **newly built server** self-registers so "any other
server that gets built" plugs in cheaply.

Sub-questions to resolve here:

- **Registry source of truth.** A static declarative manifest (e.g. a versioned
  `servers.json` / a section in a config file listing `server_id`, `server_type`,
  snapshot path, systemd unit, control endpoint), or dynamic self-registration (each
  server announces itself by writing its snapshot into a well-known directory the
  console scans)?
- **New-server onboarding contract.** What is the minimal checklist a new server type
  implements to appear in the console (emit an `OpsSnapshot`, land its file in the
  scanned dir, declare its systemd unit + control seam)? Keep it a short, documented
  contract.
- **Identity + collision.** How are `server_id` / `server_type` assigned and kept unique;
  what does the console show for a registered-but-absent server vs. an unknown snapshot?
- **Coupling.** Does the registry also carry the control-targeting info (systemd unit
  name, control channel address) ticket 02/07 need, or stay telemetry-only?

Recommended direction: **directory-scan self-registration** — each server writes its
`OpsSnapshot` file into one well-known host directory; the console enumerates that
directory as the live fleet, keyed by `server_id`; a tiny static manifest supplies the
non-runtime facts (systemd unit, control address) per `server_type`. New server =
implement the snapshot + drop its file + add one manifest row. Confirm or revise.

## Answer

_Pending._
