"""Public command controls; substituted engine/container boundaries never run native work."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class SourceIdentityTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="project0-gut-source-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        (self.root / "scripts").mkdir()
        for name in ("run_gut_validation.sh", "run_hosted_gut_container.sh"):
            shutil.copyfile(ROOT / "scripts" / name, self.root / "scripts" / name)
        (self.root / "tests/unit").mkdir(parents=True)
        (self.root / "tests/unit/test_fixture.gd").write_text("# Command fixture only\n")
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.engine_calls = self.root / "engine-calls.jsonl"
        self.docker_calls = self.root / "docker-calls.jsonl"
        self.env = {
            "PATH": str(self.bin) + os.pathsep + "/usr/bin:/bin",
            "HOME": str(self.root / "home"),
            "XDG_DATA_HOME": str(self.root / "data"),
            "TMPDIR": str(self.root),
            "GODOT_BIN": str(self.bin / "godot"),
            "RESULT_DIR": "build/validation",
            "DASHBOARD_RESULTS_DIR": str(self.root / "dashboard"),
            "FAKE_ENGINE_CALLS": str(self.engine_calls),
            "FAKE_DOCKER_CALLS": str(self.docker_calls),
        }
        self.write_executable("godot", '''#!/usr/bin/python3
import json, os, sys
from pathlib import Path
with open(os.environ["FAKE_ENGINE_CALLS"], "a") as output:
    output.write(json.dumps({"source": os.environ.get("M4_SOURCE_REVISION"), "args": sys.argv[1:]}) + "\\n")
for arg in sys.argv:
    if arg.startswith("-gjunit_xml_file="):
        Path(arg.split("=", 1)[1]).write_text('<testsuites><testsuite name="tests/unit/test_fixture.gd" tests="1" failures="0"/></testsuites>')
''')
        self.write_executable("docker", '''#!/usr/bin/python3
import json, os, sys
with open(os.environ["FAKE_DOCKER_CALLS"], "a") as output:
    output.write(json.dumps(sys.argv[1:]) + "\\n")
sys.exit(1 if sys.argv[1:3] == ["container", "inspect"] else 0)
''')
        for args in (["init", "-q"], ["add", "."],
                     ["-c", "user.name=Command Fixture", "-c", "user.email=fixture@example.invalid",
                      "-c", "commit.gpgsign=false", "commit", "-qm", "fixture"]):
            subprocess.run(["git", *args], cwd=self.root, env=self.env,
                           check=True, capture_output=True, timeout=10)
        self.sha = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=self.root,
                                           env=self.env, text=True, timeout=10).strip()

    def write_executable(self, name, source):
        path = self.bin / name
        path.write_text(source)
        path.chmod(0o755)

    def run_command(self, name, source=None):
        env = self.env.copy()
        if source is not None:
            env["M4_SOURCE_REVISION"] = source
        return subprocess.run(["bash", "scripts/" + name], cwd=self.root, env=env,
                              capture_output=True, text=True, timeout=20)

    def test_ordinary_runner_supplies_checkout_source_to_engine(self):
        result = self.run_command("run_gut_validation.sh")
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        calls = [json.loads(line) for line in self.engine_calls.read_text().splitlines()]
        self.assertEqual(len(calls), 2)
        self.assertTrue(all(call["source"] == self.sha for call in calls))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(SourceIdentityTests)
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps({"passed": result.wasSuccessful(), "tests": result.testsRun,
                                      "failures": len(result.failures), "errors": len(result.errors),
                                      "skipped": len(result.skipped)}, indent=2) + "\n")
    raise SystemExit(0 if result.wasSuccessful() else 1)
