Type: grilling
Status: unclaimed
Blocked by: 01, 02

## Question

Decide **what the client downloads and swaps** to update: a `.pck`-only
replacement, a full-package (exe + pck) replacement, or a binary diff.

Resolve:

- Given `embed_pck=false` (`Project0.pck` ships as a separate file) and that
  scripts/scenes live in the pck while the exe/engine rarely changes: is the
  primary patch unit a **replacement `.pck`**? When must the **exe** also change
  (Godot engine/export-template upgrade, changed export settings) and how is
  that heavier case handled (a full-package path)?
- **Whole-file replace vs binary diff**: at this scale (a single home-hosted
  build, a handful of testers), is a whole-file swap the right simplicity/
  bandwidth trade, or is a diff warranted?
- **Naming / matching**: how the patch unit is versioned and named so it maps
  unambiguously to the client build version (ties to
  [01](01-domain-model-and-version-identity.md)).

Depends on the version identity
([01](01-domain-model-and-version-identity.md)) and the runtime pck-load /
self-replace research ([02](02-research-godot-pck-and-windows-self-replace.md)).
Feeds transport, integrity, and apply.
