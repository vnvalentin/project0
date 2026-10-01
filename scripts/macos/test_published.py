"""Synthetic Mac controls for the exact published-client packaging seam (#1353)."""
import argparse
from contextlib import redirect_stdout
from copy import deepcopy
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import platform
import socket
import stat
import tempfile
from types import SimpleNamespace
import unittest
from unittest import mock
import warnings
import zipfile


def load_module(name):
    spec = importlib.util.spec_from_file_location("macos_" + name, Path(__file__).with_name(name + ".py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def release_manifest_fixture():
    return {
        "package": "standalone-windows-client", "version": "0.14.20",
        "built_at_utc": "2026-10-01T00:00:00Z",
        "source_commit": "ff2989d5b88eee7e2ed21c87d493d31d74935a38",
        "source_tree_dirty": True, "godot_export_exit_code": 0,
        "godot_version": "4.7.2.stable.official.ed1daf0bf", "release_eligible": True,
        "export_error_lines": [],
        "archive": {
            "name": "Project0-client-windows-x64-0.14.20.zip", "bytes": 39750225,
            "sha256": "B6B723935797F0388A18D2C7A60185FD3723103DEDBE21A5CCB773462A130BCC",
        },
        "archive_contents": [
            {"name": "Project0.exe", "bytes": 109268480,
             "sha256": "806CD5D973EF6E0B4FAE2791C3CD9D7327908866FF590336810189A83C018F42"},
            {"name": "Project0.pck", "bytes": 624120,
             "sha256": "1F75603889ED79412286FC2CC8C79636244E05ACBDBE16D6FF1CFD1FDA31F94A"},
        ],
    }


def tiny_archive_fixture(root, entries=None):
    """An owned archive with literal member bytes and independently known digests."""
    entries = entries if entries is not None else [("Project0.exe", b"abc"), ("Project0.pck", b"hello")]
    archive = root / "synthetic-release.zip"
    with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED) as handle:
        for name, contents in entries:
            handle.writestr(name, contents)
    archive_record = {"name": archive.name, "bytes": archive.stat().st_size,
                      "sha256": hashlib.sha256(archive.read_bytes()).hexdigest()}
    member_records = [
        {"name": "Project0.exe", "bytes": 3,
         "sha256": "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"},
        {"name": "Project0.pck", "bytes": 5,
         "sha256": "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"},
    ]
    return archive, archive_record, member_records


class PublishedPlanTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="project0-macos-published-control-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()
        self.published = load_module("published")
        self.preflight = load_module("preflight")
        selected = ["scripts/macos/published.py", "scripts/macos/published_inventory.gd",
                    "scripts/macos/published_admission_probe.gd"]
        self.plan = {
            "schema_version": 1, "kind": "component",
            "issue": "https://github.com/vnvalentin/project0/issues/1353",
            "steps": [{
                "suite": "macos-published", "platform": "macos", "host": "Philips-MacBook-Pro-2",
                "command": "python3 scripts/macos/published.py --godot build/tools/godot/Godot.app/Contents/MacOS/Godot --template build/tools/godot/templates/macos.zip --version 0.14.20 --output dist/macos/published-control --plan .scratch/macos-client/published-control.json --report build/validation/macos/published-control.json",
                "dependencies": ["godot-client", "python", "git"],
                "tests": selected, "artifacts": ["build/validation/macos/published-control.json"],
            }],
        }
        self.manifest = {
            "schema_version": 1, "hosts": {"macos": ["Philips-MacBook-Pro-2"]},
            "server_dependencies": ["sqlite", "canon", "ollama"],
            "suites": {
                "macos-published": {"platform": "macos", "owner": "macos-client",
                                    "dependencies": ["godot-client", "python", "git"], "tests": selected},
                "macos-tooling": {"platform": "macos", "owner": "macos-tooling",
                                  "dependencies": ["python", "git"], "tests": ["scripts/macos/test_*.py"]},
            },
        }
        self.args = argparse.Namespace(
            godot=self.root / "build/tools/godot/Godot.app/Contents/MacOS/Godot",
            template=self.root / "build/tools/godot/templates/macos.zip", version="0.14.20",
            output=self.root / "dist/macos/published-control",
            plan=self.root / ".scratch/macos-client/published-control.json",
            report=self.root / "build/validation/macos/published-control.json",
        )
        for name in selected:
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("# owned source metadata fixture, never executed\n")
        for path in (self.args.godot, self.args.template):
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(b"owned tool fixture, never executed\n")
        self.args.plan.parent.mkdir(parents=True)
        self.args.plan.write_text(json.dumps(self.plan))

    def check(self, plan=None, manifest=None, os="Darwin", host="Philips-MacBook-Pro-2.local"):
        return self.preflight.validate_plan(self.root, manifest or self.manifest, plan or self.plan, os, host)

    def test_exact_owned_published_invocation_and_plan_are_accepted(self):
        self.published.validate_invocation(self.root, self.plan, self.args)
        self.assertEqual(self.check(), [])

    def test_actual_tool_template_version_output_plan_and_report_are_bound(self):
        for field, value in {
            "godot": self.root / "build/tools/godot/unplanned-editor",
            "template": self.root / "build/tools/godot/templates/unplanned.zip",
            "version": "0.14.21", "output": self.root / "dist/macos/unplanned",
            "plan": self.root / ".scratch/macos-client/unplanned.json",
            "report": self.root / "build/validation/macos/unplanned.json",
        }.items():
            with self.subTest(field=field):
                args = deepcopy(self.args)
                setattr(args, field, value)
                with self.assertRaises(ValueError):
                    self.published.validate_invocation(self.root, self.plan, args)

    def test_endpoint_auth_and_alternate_release_arguments_are_refused(self):
        original = self.plan["steps"][0]["command"]
        for command in (
            original + " --url https://example.invalid/alternate.zip",
            original + " --host 127.0.0.1", original + " --password synthetic-fixture",
            original + " --version 0.14.20", original.replace("--version 0.14.20", "--version 0.14.21"),
            original.replace(" --template build/tools/godot/templates/macos.zip", ""),
            original + " ; echo chained",
        ):
            with self.subTest(command=command):
                plan = deepcopy(self.plan)
                plan["steps"][0]["command"] = command
                self.assertTrue(self.check(plan))

    def test_wrong_host_paired_and_other_runtime_dependencies_are_refused(self):
        self.assertTrue(self.check(os="Linux"))
        self.assertTrue(self.check(host="Unassigned-Mac"))
        plan = deepcopy(self.plan)
        plan["kind"] = "paired-runtime"
        self.assertTrue(self.check(plan))
        for dependency in (" SQLite ", "canon", "ollama", "bash", "docker", "ssh", "scp", "powershell", "go"):
            with self.subTest(dependency=dependency):
                plan = deepcopy(self.plan)
                plan["steps"][0]["dependencies"].append(dependency)
                self.assertTrue(self.check(plan))

    def test_all_three_owned_entries_and_exact_report_are_required(self):
        for missing in self.plan["steps"][0]["tests"]:
            with self.subTest(missing=missing):
                plan = deepcopy(self.plan)
                plan["steps"][0]["tests"].remove(missing)
                self.assertTrue(self.check(plan))
        plan = deepcopy(self.plan)
        plan["steps"][0]["command"] = plan["steps"][0]["command"].replace(
            "--report build/validation/macos/published-control.json", "--report build/validation/macos/unplanned.json")
        self.assertTrue(self.check(plan))

    def test_nonpublished_suite_and_duplicate_ownership_are_refused(self):
        for suite in ("linux-unit", "windows-client", "macos-client"):
            with self.subTest(suite=suite):
                plan = deepcopy(self.plan)
                plan["steps"][0]["suite"] = suite
                self.assertTrue(self.check(plan))
        manifest = deepcopy(self.manifest)
        manifest["suites"]["linux-review"] = {
            "platform": "linux", "dependencies": ["python"],
            "tests": ["scripts/macos/published_inventory.gd"],
        }
        self.assertTrue(self.check(manifest=manifest))

    def test_unowned_evidence_and_extra_selected_resources_are_refused(self):
        plan = deepcopy(self.plan)
        plan["steps"][0]["command"] = plan["steps"][0]["command"].replace(
            "build/validation/macos/published-control.json", "../escaped.json")
        plan["steps"][0]["artifacts"] = ["../escaped.json"]
        self.assertTrue(self.check(plan))
        for extra in ("scripts/macos/published.py", "client/network_client.gd"):
            with self.subTest(extra=extra):
                plan = deepcopy(self.plan)
                plan["steps"][0]["tests"].append(extra)
                self.assertTrue(self.check(plan))

    def test_existing_report_is_preserved_without_process_or_network_access(self):
        self.args.report.parent.mkdir(parents=True)
        self.args.report.write_bytes(b"existing evidence is preserved\n")
        arguments = ["--godot", str(self.args.godot), "--template", str(self.args.template),
                     "--version", "0.14.20", "--output", str(self.args.output),
                     "--plan", str(self.args.plan), "--report", str(self.args.report)]
        with mock.patch.object(self.published, "ROOT", self.root), \
                mock.patch("subprocess.Popen") as launch, \
                mock.patch("subprocess.check_output") as external_query, \
                mock.patch("socket.create_connection") as connection, redirect_stdout(io.StringIO()):
            result = self.published.main(arguments)
        self.assertEqual(result, 1)
        launch.assert_not_called()
        external_query.assert_not_called()
        connection.assert_not_called()
        self.assertEqual(self.args.report.read_bytes(), b"existing evidence is preserved\n")


class PublishedManifestTests(unittest.TestCase):
    def setUp(self):
        self.published = load_module("published")

    def test_reviewed_dirty_release_is_accepted_without_rewriting_provenance(self):
        manifest = release_manifest_fixture()
        before = deepcopy(manifest)
        self.published.validate_manifest(manifest)
        self.assertEqual(manifest, before)
        self.assertTrue(manifest["source_tree_dirty"])
        self.assertEqual(manifest["source_commit"], "ff2989d5b88eee7e2ed21c87d493d31d74935a38")

    def test_version_archive_identity_size_and_hash_are_fixed(self):
        mutations = (
            ("version", "0.14.21"), ("package", "alternate-client"),
            ("source_commit", "synthetic-unqualified-revision"),
            ("godot_version", "4.3.stable.official.synthetic"),
        )
        for field, value in mutations:
            with self.subTest(field=field):
                manifest = release_manifest_fixture()
                manifest[field] = value
                with self.assertRaises(ValueError):
                    self.published.validate_manifest(manifest)
        for field, value in (("name", "alternate.zip"), ("bytes", 39750224), ("sha256", "0" * 64)):
            with self.subTest(archive=field):
                manifest = release_manifest_fixture()
                manifest["archive"][field] = value
                with self.assertRaises(ValueError):
                    self.published.validate_manifest(manifest)

    def test_both_exact_root_members_and_their_bytes_and_hashes_are_required(self):
        for member in (0, 1):
            for field, value in (("name", "nested/Project0.pck"), ("bytes", 1), ("sha256", "0" * 64)):
                with self.subTest(member=member, field=field):
                    manifest = release_manifest_fixture()
                    manifest["archive_contents"][member][field] = value
                    with self.assertRaises(ValueError):
                        self.published.validate_manifest(manifest)
        for contents in (
            [], release_manifest_fixture()["archive_contents"][:1],
            release_manifest_fixture()["archive_contents"] + [{"name": "unexpected.txt", "bytes": 1, "sha256": "0" * 64}],
            [release_manifest_fixture()["archive_contents"][0]] * 2,
        ):
            with self.subTest(contents=contents):
                manifest = release_manifest_fixture()
                manifest["archive_contents"] = contents
                with self.assertRaises(ValueError):
                    self.published.validate_manifest(manifest)

    def test_ineligible_failed_export_and_invalid_manifest_types_are_refused(self):
        for field, value in (
            ("release_eligible", False), ("release_eligible", 1),
            ("godot_export_exit_code", 1), ("godot_export_exit_code", False),
            ("export_error_lines", ["synthetic fixture error"]),
            ("source_tree_dirty", "true"), ("source_tree_dirty", 1),
            ("archive", []), ("archive_contents", {}),
        ):
            with self.subTest(field=field):
                manifest = release_manifest_fixture()
                manifest[field] = value
                with self.assertRaises(ValueError):
                    self.published.validate_manifest(manifest)
        for raw in (None, [], "synthetic fixture", {}):
            with self.subTest(raw=raw):
                with self.assertRaises(ValueError):
                    self.published.validate_manifest(raw)


class PublishedArchiveTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="project0-macos-published-archive-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()
        self.published = load_module("published")
        self.destination = self.root / "extracted"

    def extract(self, archive, record, members):
        return self.published.extract_archive(archive, self.destination, record, members)

    def test_matching_two_member_archive_extracts_exact_pck_without_changing_original(self):
        archive, record, members = tiny_archive_fixture(self.root)
        original = archive.read_bytes()
        self.extract(archive, record, members)
        self.assertEqual(sorted(path.name for path in self.destination.iterdir()), ["Project0.exe", "Project0.pck"])
        self.assertEqual((self.destination / "Project0.exe").read_bytes(), b"abc")
        self.assertEqual((self.destination / "Project0.pck").read_bytes(), b"hello")
        self.assertEqual(archive.read_bytes(), original)

    def test_archive_byte_count_and_hash_must_match_before_extraction(self):
        archive, record, members = tiny_archive_fixture(self.root)
        for field, value in (("bytes", record["bytes"] + 1), ("sha256", "0" * 64)):
            with self.subTest(field=field):
                changed = deepcopy(record)
                changed[field] = value
                with self.assertRaises(ValueError):
                    self.extract(archive, changed, members)
                self.assertFalse(self.destination.exists())

    def test_pck_byte_count_and_hash_must_match_before_it_is_usable(self):
        archive, record, members = tiny_archive_fixture(self.root)
        for field, value in (("bytes", 6), ("sha256", "0" * 64)):
            with self.subTest(field=field):
                changed = deepcopy(members)
                changed[1][field] = value
                with self.assertRaises(ValueError):
                    self.extract(archive, record, changed)
                self.assertFalse(self.destination.exists())

    def test_traversal_absolute_and_windows_separator_members_are_refused(self):
        for name in ("../outside.txt", str(self.root / "outside.txt"), "folder\\Project0.pck"):
            with self.subTest(name=name):
                archive, record, members = tiny_archive_fixture(
                    self.root, [("Project0.exe", b"abc"), (name, b"hello")])
                with self.assertRaises(ValueError):
                    self.extract(archive, record, members)
                self.assertFalse(self.destination.exists())
                self.assertFalse((self.root / "outside.txt").exists())

    def test_symlink_member_is_refused_and_never_materialized(self):
        link = zipfile.ZipInfo("Project0.pck")
        link.create_system = 3
        link.external_attr = (stat.S_IFLNK | 0o777) << 16
        archive, record, members = tiny_archive_fixture(
            self.root, [("Project0.exe", b"abc"), (link, b"hello")])
        with self.assertRaises(ValueError):
            self.extract(archive, record, members)
        self.assertFalse(self.destination.exists())

    def test_duplicate_unexpected_and_oversized_compressed_members_are_refused(self):
        for entries in (
            [("Project0.exe", b"abc"), ("Project0.pck", b"hello"), ("Project0.pck", b"hello")],
            [("Project0.exe", b"abc"), ("Project0.pck", b"hello"), ("unexpected.txt", b"x")],
            [("Project0.exe", b"abc"), ("Project0.pck", b"x" * 65536)],
        ):
            with self.subTest(count=len(entries), last_size=len(entries[-1][1])):
                with warnings.catch_warnings():
                    warnings.simplefilter("ignore", UserWarning)
                    archive, record, members = tiny_archive_fixture(self.root, entries)
                with self.assertRaises(ValueError):
                    self.extract(archive, record, members)
                self.assertFalse(self.destination.exists())

    def test_high_ratio_member_is_refused_even_when_its_declared_bytes_and_hash_match(self):
        payload = b"x" * 65536
        archive, record, members = tiny_archive_fixture(
            self.root, [("Project0.exe", b"abc"), ("Project0.pck", payload)])
        members[1]["bytes"] = len(payload)
        members[1]["sha256"] = hashlib.sha256(payload).hexdigest()
        with self.assertRaises(ValueError):
            self.extract(archive, record, members)
        self.assertFalse(self.destination.exists())

    def test_existing_destination_and_symlink_archive_are_preserved(self):
        archive, record, members = tiny_archive_fixture(self.root)
        self.destination.mkdir()
        marker = self.destination / "existing-evidence.txt"
        marker.write_bytes(b"existing owned evidence\n")
        with self.assertRaises(ValueError):
            self.extract(archive, record, members)
        self.assertEqual(marker.read_bytes(), b"existing owned evidence\n")
        self.assertEqual(list(self.destination.iterdir()), [marker])
        marker.unlink()
        self.destination.rmdir()
        alias = self.root / "alias" / archive.name
        alias.parent.mkdir()
        alias.symlink_to(archive)
        with self.assertRaises(ValueError):
            self.extract(alias, record, members)
        self.assertFalse(self.destination.exists())
        self.assertTrue(archive.is_file())


class PublishedDownloadTests(unittest.TestCase):
    MANIFEST_URL = "https://project0.valentin.vip/patches/downloads/0.14.20/deployment-manifest.json"
    ARCHIVE_URL = "https://project0.valentin.vip/patches/downloads/0.14.20/Project0-client-windows-x64-0.14.20.zip"

    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="project0-macos-published-download-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()
        self.published = load_module("published")
        self.destination = self.root / "downloaded-fixture"

    def response(self, payload=b"abc", status=200, url=None):
        response = mock.MagicMock()
        response.__enter__.return_value = response
        response.status = status
        response.geturl.return_value = url or self.MANIFEST_URL
        response.read.side_effect = io.BytesIO(payload).read
        return response

    def test_fixed_manifest_url_uses_anonymous_get_and_exact_payload_custody(self):
        opener = mock.Mock()
        opener.open.return_value = self.response()
        with mock.patch("urllib.request.build_opener", return_value=opener) as construct:
            self.published.download(self.MANIFEST_URL, self.destination, 3,
                                    "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        self.assertEqual(self.destination.read_bytes(), b"abc")
        request = opener.open.call_args.args[0]
        self.assertEqual(request.full_url, self.MANIFEST_URL)
        self.assertEqual(request.get_method(), "GET")
        self.assertIsNone(request.data)
        self.assertEqual({name.lower() for name, _ in request.header_items()}, {"accept", "user-agent"})
        self.assertEqual(opener.open.call_args.kwargs, {"timeout": 15})
        handlers = construct.call_args.args
        proxy = next(handler for handler in handlers if isinstance(handler, self.published.urllib.request.ProxyHandler))
        self.assertEqual(proxy.proxies, {})
        redirect = next(handler for handler in handlers if isinstance(handler, self.published.urllib.request.HTTPRedirectHandler))
        with self.assertRaises(ValueError):
            redirect.redirect_request(request, None, 302, "synthetic redirect", {}, self.ARCHIVE_URL)

    def test_alternate_release_endpoint_scheme_and_auth_urls_never_open_transport(self):
        for url in (
            self.MANIFEST_URL.replace("0.14.20", "0.14.21"),
            "http://project0.valentin.vip/patches/downloads/0.14.20/deployment-manifest.json",
            "https://example.invalid/deployment-manifest.json",
            "https://synthetic-user:synthetic-password@project0.valentin.vip/patches/downloads/0.14.20/deployment-manifest.json",
            self.MANIFEST_URL + "?token=synthetic-fixture",
        ):
            with self.subTest(url=url), mock.patch("urllib.request.build_opener") as construct:
                with self.assertRaises(ValueError):
                    self.published.download(url, self.destination, 3)
                construct.assert_not_called()
                self.assertFalse(self.destination.exists())

    def test_redirect_status_short_oversize_and_altered_bytes_leave_no_download(self):
        for response in (
            self.response(status=302), self.response(url=self.ARCHIVE_URL),
            self.response(payload=b"ab"), self.response(payload=b"abcd"), self.response(payload=b"xyz"),
        ):
            with self.subTest(status=response.status, url=response.geturl.return_value):
                opener = mock.Mock()
                opener.open.return_value = response
                with mock.patch("urllib.request.build_opener", return_value=opener), self.assertRaises(ValueError):
                    self.published.download(self.MANIFEST_URL, self.destination, 3,
                                            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
                self.assertFalse(self.destination.exists())

    def test_occupied_download_and_unbounded_size_are_refused_before_transport(self):
        self.destination.write_bytes(b"existing owned bytes\n")
        with mock.patch("urllib.request.build_opener") as construct, self.assertRaises(ValueError):
            self.published.download(self.MANIFEST_URL, self.destination, 3)
        construct.assert_not_called()
        self.assertEqual(self.destination.read_bytes(), b"existing owned bytes\n")
        self.destination.unlink()
        for maximum in (0, -1, True, 160 * 1024 * 1024 + 1):
            with self.subTest(maximum=maximum), mock.patch("urllib.request.build_opener") as construct:
                with self.assertRaises(ValueError):
                    self.published.download(self.MANIFEST_URL, self.destination, maximum)
                construct.assert_not_called()
                self.assertFalse(self.destination.exists())


class PublishedLifecycleTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="project0-macos-published-lifecycle-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()
        self.published = load_module("published")
        self.editor = self.root / "engine/Godot.app/Contents/MacOS/Godot"
        self.editor.parent.mkdir(parents=True)
        self.editor.write_bytes(b"owned engine fixture, never executed")
        self.template = self.root / "template.zip"
        self.template.write_bytes(b"owned template fixture, never executed")
        self.pack = self.root / "Project0.pck"
        self.pack.write_bytes(b"owned pack fixture, never executed")
        self.output = self.root / "candidate"
        self.evidence = self.root / "evidence"
        self.evidence.mkdir()
        self.support = self.root / "fixture-home/Library/Application Support"
        self.support.mkdir(parents=True)
        self.sentinel = self.support / "existing-profile.txt"
        self.sentinel.write_bytes(b"preserve existing fixture state")
        fixture_os = SimpleNamespace(environ={"HOME": str(self.root / "fixture-home")})
        self.addCleanup(mock.patch.stopall)
        mock.patch.object(self.published.package, "os", fixture_os).start()
        mock.patch.object(self.published.package, "source_hashes", return_value={"fixture": "owned"}).start()
        self.launch = mock.patch.object(self.published.admission, "run_suppressed").start()
        self.shell = mock.patch.object(self.published, "_bundle").start()

    def assemble(self, report):
        self.published.assemble_pack(self.editor, self.template, self.pack, self.output, report, self.evidence)

    def assert_clean_failure(self, report):
        self.assertTrue(report["temporary_state_removed"])
        self.assertFalse(self.output.exists())
        self.assertEqual(list(self.support.iterdir()), [self.sentinel])
        self.assertEqual(self.sentinel.read_bytes(), b"preserve existing fixture state")
        self.assertEqual(self.pack.read_bytes(), b"owned pack fixture, never executed")

    def test_rejected_data_audit_stops_before_qualification_or_published_script(self):
        report = {}
        with mock.patch.object(self.published, "audit_pack", side_effect=ValueError("owned audit rejection")), \
                mock.patch.object(self.published, "qualify_preboot") as qualify:
            with self.assertRaises(ValueError):
                self.assemble(report)
        qualify.assert_not_called()
        self.shell.assert_not_called()
        self.launch.assert_not_called()
        self.assertEqual(report["terminal_stage"], "data_only_pack_audit")
        self.assert_clean_failure(report)

    def test_failed_preboot_isolation_stops_before_published_script_or_output(self):
        report = {}
        with mock.patch.object(self.published, "audit_pack", return_value={"accepted": True}), \
                mock.patch.object(self.published, "qualify_preboot", side_effect=ValueError("owned isolation rejection")):
            with self.assertRaises(ValueError):
                self.assemble(report)
        self.shell.assert_not_called()
        self.launch.assert_not_called()
        self.assertEqual(report["terminal_stage"], "offline_preboot_qualification")
        self.assert_clean_failure(report)

    def test_outer_cleanup_cannot_hide_retained_inner_state(self):
        report = {}
        original_remove = self.published.package.shutil.rmtree
        retained = None

        def remove(path, *args, **kwargs):
            if retained is not None and Path(path) == retained:
                raise PermissionError("owned retained-state fixture")
            return original_remove(path, *args, **kwargs)

        with mock.patch.object(self.published.package.shutil, "rmtree", side_effect=remove):
            with self.assertRaises(PermissionError):
                with self.published.package.owned_state(report) as outer:
                    with self.published.package.owned_state(report) as inner:
                        retained = inner[1]
        self.assertFalse(report["temporary_state_removed"])
        self.assertEqual(report["cleanup_receipts"], [False, True])
        self.assertTrue(retained.exists())
        self.assertFalse(outer[0].exists())
        self.assertFalse(outer[1].exists())
        self.assertEqual(self.sentinel.read_bytes(), b"preserve existing fixture state")

    def test_main_pack_override_is_beside_pack_and_removed_after_failure(self):
        settings = "[application]\nconfig/name=\"Owned fixture\"\n"
        with self.assertRaises(RuntimeError):
            with self.published.pack_boot_settings(self.pack, settings) as override:
                self.assertEqual(override, self.pack.parent / "override.cfg")
                self.assertEqual(override.read_text(), settings)
                self.assertEqual(self.pack.read_bytes(), b"owned pack fixture, never executed")
                raise RuntimeError("owned runtime fixture failure")
        self.assertFalse((self.pack.parent / "override.cfg").exists())

    def test_main_pack_override_refuses_existing_state_without_overwrite(self):
        override = self.pack.parent / "override.cfg"
        override.write_bytes(b"existing owned state is preserved")
        with self.assertRaises(FileExistsError):
            with self.published.pack_boot_settings(self.pack, "new fixture"):
                self.fail("occupied override must stop startup")
        self.assertEqual(override.read_bytes(), b"existing owned state is preserved")

    def test_failure_json_retains_stage_and_type_without_exception_text(self):
        report_path = self.root / "build/validation/macos/failure.json"
        arguments = ["--godot", str(self.editor), "--template", str(self.template),
                     "--version", "0.14.20", "--output", str(self.output),
                     "--plan", str(self.root / "plan.json"), "--report", str(report_path)]

        def fail(_args, report, _evidence):
            report["terminal_stage"] = "offline_preboot_qualification"
            raise RuntimeError("untrusted exception text must not be copied")

        with mock.patch.object(self.published, "ROOT", self.root), \
                mock.patch.object(self.published, "diagnose", side_effect=fail), redirect_stdout(io.StringIO()):
            self.assertEqual(self.published.main(arguments), 1)
        receipt = json.loads(report_path.read_text())
        self.assertFalse(receipt["passed"])
        self.assertEqual(receipt["terminal_stage"], "offline_preboot_qualification")
        self.assertEqual(receipt["error_type"], "RuntimeError")
        self.assertNotIn("untrusted exception text", report_path.read_text())
        self.launch.assert_not_called()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    if args.report.exists():
        parser.error("report already exists; choose a new evidence path")
    suites = [unittest.defaultTestLoader.loadTestsFromTestCase(case)
              for case in (PublishedPlanTests, PublishedManifestTests, PublishedArchiveTests,
                           PublishedDownloadTests, PublishedLifecycleTests)]
    selected = [test.id() for suite in suites for test in suite]
    result = unittest.TextTestRunner(verbosity=2).run(unittest.TestSuite(suites))
    passed = result.wasSuccessful() and not result.skipped and result.testsRun == len(selected)
    args.report.parent.mkdir(parents=True, exist_ok=True)
    with args.report.open("x", encoding="utf-8") as handle:
        handle.write(json.dumps({
            "issue": 1353, "platform": "macos", "os": platform.system(), "host": socket.gethostname(),
            "passed": passed, "tests_run": result.testsRun, "failures": len(result.failures),
            "errors": len(result.errors), "skipped": len(result.skipped), "selected_tests": selected,
            "network_executed": False, "runtime_acceptance": False,
        }, indent=2) + "\n")
    return int(not passed)


if __name__ == "__main__":
    raise SystemExit(main())
