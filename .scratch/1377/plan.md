# M4.2 boundary and persistence evidence

Governing issue: https://github.com/vnvalentin/project0/issues/1377
Parent: #204. Milestone 4 / M4.2.
Implementation brief and SDD/BDD/TDD: https://github.com/vnvalentin/project0/issues/1377#issuecomment-5954622774

Linux-only isolated component evidence. No production behavior changes.
First increment proves rejected Canon requests make zero SQL INSERT/UPDATE attempts and preserve exact database/sidecar digests and raw rows. Positive writes and missing observations are deliberate detector controls.
Three-case boundary parity awaits the M4.1 fixture and resolution of unavailable authoritative state fields; never report absent representations as observed passes.

Owned files: tests/integration/test_m4_boundary_parity.gd and scripts/m4_canon_evidence.gd.
Rollback: close owned stores, remove only unique fixture files/sidecars, and discard owned XDG directory. Production paths and services are excluded.
Validation: machine-readable plan alongside this note; focused GUT then full GUT and record sync at final revision. Review remains required.
