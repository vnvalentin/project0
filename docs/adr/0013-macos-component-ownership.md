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
