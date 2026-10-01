"""Mac-only regression at the client staging and packaging seams (#1353)."""
import argparse
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]


class PackageTests(unittest.TestCase):
    def test_staged_client_excludes_server_runtime_and_preserves_source_version(self):
        spec = importlib.util.spec_from_file_location("macos_package", Path(__file__).with_name("package.py"))
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        source_version = (ROOT / "shared/client_build_version.gd").read_bytes()
        with tempfile.TemporaryDirectory(prefix="project0-macos-test-") as temporary:
            stage = Path(temporary) / "client"
            module.stage_project(ROOT, stage, "0.12.0")
            self.assertTrue((stage / "client/account_gate.tscn").is_file())
            self.assertTrue((stage / "server/starting_town_hub_fixture.gd").is_file())
            self.assertFalse((stage / "server/server_main.gd").exists())
            self.assertFalse((stage / "addons").exists())
            self.assertFalse((stage / "shared/local_llm_client.gd").exists())
            self.assertFalse((stage / "native").exists())
            self.assertFalse((stage / "tests").exists())
            self.assertEqual((ROOT / "shared/client_build_version.gd").read_bytes(), source_version)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    if args.report.exists():
        parser.error("report already exists; choose a new evidence path")
    result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(PackageTests))
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps({"issue": 1353, "platform": "macos", "passed": result.wasSuccessful(),
        "tests_run": result.testsRun, "failures": len(result.failures), "errors": len(result.errors),
        "runtime_acceptance": False}, indent=2) + "\n")
    return int(not result.wasSuccessful())


if __name__ == "__main__":
    raise SystemExit(main())
