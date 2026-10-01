---
status: accepted
---

# Standalone macOS client component ownership

For [#1353](https://github.com/vnvalentin/project0/issues/1353), the user approved
a standalone universal macOS app, local packaging/client regression and the
required Mac ownership additions on 2026-10-01, while explicitly deferring
access to the other person's Linux and Windows hosts. Add Mac component suites
on `Philips-MacBook-Pro-2` with their own static preflight; this extends the
Windows-specific client validation wording in the systems specification only
for this standalone offline scope. It preserves the server authority and
dependencies, original Linux/Windows ownership, paired acceptance and merge
gates; it authorizes no server, production, signing or Windows runtime changes.
The decision is approved scope, not evidence that the app or delivery is accepted.

Philip's subsequent report that Character selection ends in
`server_admission_timeout` authorizes a bounded Mac client diagnostic against
the configured public game endpoint, recorded in
[#1353](https://github.com/vnvalentin/project0/issues/1353#issuecomment-5937286309).
Add a separate `macos-admission` owner selection and preflight contract. Run the
real client transport/version admission with isolated data, retain only public
allowlisted stage metadata, discard engine output before capture, and stop
before assertions/authentication. This adds no authority over the deferred
private hosts, server implementation/deployment, Windows behavior or merge.
Admission is supporting evidence; authenticated world entry remains its own
acceptance criterion.
