"""Build the standalone Mac client from an isolated client-only project (#1353)."""
from pathlib import Path
import re
import shutil
import subprocess


VERSION = re.compile(r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)")


def stage_project(root: Path, destination: Path, version: str) -> None:
    """Prepare a new client tree without importing or changing the source checkout."""
    if not VERSION.fullmatch(version):
        raise ValueError("version must be canonical MAJOR.MINOR.PATCH")
    if destination.exists():
        raise ValueError("staging destination already exists")
    tracked = subprocess.check_output(["git", "-C", str(root), "ls-files", "-z", "client", "shared", "project.godot", "server/starting_town_hub_fixture.gd"]).decode().split("\0")
    resources = [name for name in tracked if name and name != "shared/local_llm_client.gd"
                 and Path(name).suffix in (".gd", ".tscn", ".tres", ".json", ".uid", ".godot")]
    resources.append("scripts/macos/offline_probe.gd")
    for name in resources:
        source = root / name
        if source.is_symlink() or not source.is_file() or not source.resolve().is_relative_to(root.resolve()):
            raise ValueError("source must be a regular repository resource: " + name)
    destination.mkdir(parents=True)
    for name in resources:
        target = destination / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(root / name, target)
    contract = destination / "shared/client_build_version.gd"
    text, count = re.subn(r'^const CLIENT_BUILD_VERSION: String = "[^"\n]*"',
                         'const CLIENT_BUILD_VERSION: String = "' + version + '"',
                         contract.read_text(), flags=re.MULTILINE)
    if count != 1:
        raise ValueError("client version contract must contain exactly one version assignment")
    contract.write_text(text)
    project = destination / "project.godot"
    text = re.sub(r"\[editor_plugins\][\s\S]*?(?=\n\[|\Z)", "", project.read_text())
    project.write_text(text.replace('PackedStringArray("4.3", "Forward Plus")', 'PackedStringArray("4.7", "GL Compatibility")'))
