from __future__ import annotations

from fastapi.testclient import TestClient

from infra.enrollment.app import create_app
from infra.enrollment.tests.fakes import FakeLoginAuthorityClient


def test_patches_are_publicly_served_without_auth(tmp_path):
    patches = tmp_path / "patches"
    (patches / "0.7.0").mkdir(parents=True)
    (patches / "downloads").mkdir()
    (patches / "downloads" / "index.html").write_text("<h1>downloads</h1>")
    (patches / "manifest.json").write_bytes(b'{"schema_version":1}')
    (patches / "manifest.sig").write_bytes(b"signature")
    (patches / "0.7.0" / "Project0.pck").write_bytes(b"pack")

    client = TestClient(create_app(FakeLoginAuthorityClient(), patches_dir=str(patches)))

    assert client.get("/patches/manifest.json").status_code == 200
    assert client.get("/patches/manifest.sig").content == b"signature"
    assert client.get("/patches/0.7.0/Project0.pck").content == b"pack"
    assert client.get("/patches/downloads/").text == "<h1>downloads</h1>"
    assert client.get("/patches/missing.pck").status_code == 404


def test_patches_are_not_mounted_when_unconfigured():
    client = TestClient(create_app(FakeLoginAuthorityClient()))
    assert client.get("/patches/manifest.json").status_code == 404


def test_public_navigation_pages_are_available_without_auth():
    client = TestClient(create_app(FakeLoginAuthorityClient()))

    assert client.get("/").status_code == 200
    assert "/patches/downloads/0.13.2/Project0-client-windows-x64-0.13.2.zip" in client.get("/").text
    assert client.get("/downloads/").status_code == 200
    assert client.get("/telemetry").status_code == 200
    assert client.get("/dashboard").status_code == 200
    assert "project0.valentin.vip:9999" in client.get("/game").text
