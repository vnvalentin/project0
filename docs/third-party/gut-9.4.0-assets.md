# GUT 9.4.0 Image Assets

Governing issue: https://github.com/vnvalentin/project0/issues/1188
Parent validation cleanup: https://github.com/vnvalentin/project0/issues/1184

The vendored GUT plugin is version 9.4.0. Its six shipped PNGs were omitted
under the repository-wide `*.png` ignore rule. They are source assets, not
generated cache files. Restore them unchanged and retain exact-path ignore
exceptions so a new checkout contains the same dependency inputs.

## Provenance

- Upstream: https://github.com/bitwes/Gut/tree/v9.4.0/addons/gut
- Tag: `v9.4.0`
- Resolved commit: `ca6cf2006b887c5072410a3c89792110ba51d476`
- Retrieval: authenticated `gh api` contents endpoints pinned to that commit.
- Verification: content size and Git blob SHA-1 against the pinned upstream
  tree, plus SHA-256 below. No transformation or version upgrade.
- Existing `plugin.cfg`, `gui/GutBottomPanel.gd`, and `gui/ResultsTree.gd`
  match that commit's blobs exactly: `e08867398615c968253763dd97407cae0bbfce86`,
  `d9379184423a3362c13782dc697b5df8fccfebc6`, and
  `f512a5cfbaa75e59d29df7b7568bc591f693368e`, respectively.

Paths below are relative to `addons/gut/`.

| File | Bytes | Git Blob SHA-1 | SHA-256 |
| --- | ---: | --- | --- |
| `gui/arrow.png` | 122 | `d407714ccdeb1e30c6e363aab27146d3f9a03e97` | `7f5a2f25d0cc68b8281bda24cdcd1d816e718d11fa0d050ede6cbad9033d17ed` |
| `gui/play.png` | 143 | `06fbff3bf95daacb8079f76ebd4230627ac7fb09` | `d4280462a7940ebaf184e2b92bd01a69cf09ae1c97b175ac92e1410d16ecf278` |
| `icon.png` | 129 | `9ad6a1dd9959cc5f88d593408c8adbdbd18e7639` | `17186e5c117662f093554ade93529a8f2927750362004e133acf3ded0afba45d` |
| `images/green.png` | 213 | `c81fd09d931c7ac01599424b0d0d8eba5f0e3ef4` | `9137132eda912531252c215d698a604c401f2e59f8b29005117d72fef625ed75` |
| `images/red.png` | 213 | `3d9dec14b3dd89ec36dbb5b7008c36a10afe8e4b` | `e85d15987192029471051afc3b5de797629b95a5e02024fc5d14d81fdaf599bd` |
| `images/yellow.png` | 213 | `8b7dc35b0fc95b004901c205612515c2c3621942` | `d3e42a49cde1baf9dd2647d62ca58399efeb94c2eec39b2b62450021532c08c3` |

## Validation Boundary

An import exit code of zero is insufficient. Capture Godot's output and reject
engine/script errors, missing resources, and shutdown leaks. Keep checks of
initial resource/class/native-extension registration separate from test teardown.
The asset-only repair does not claim to fix GUT/Godot cold-start initialization:
an empty-cache first import can load the editor plugin before resource and class
registration completes. Preserve that failure evidence; do not silently reuse an
unknown cache or suppress it. Current validation evidence and remaining blockers
belong in the governing GitHub issues, not in this provenance record.

Rollback is the asset/ignore/provenance commit only. No addon logic, test guards,
product code, production state, dependency version, or native binary changes are
part of this restoration.