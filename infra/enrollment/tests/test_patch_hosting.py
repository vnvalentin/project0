from __future__ import annotations

from fastapi.testclient import TestClient

from infra.enrollment.app import create_app
from infra.enrollment.service import EnrollmentService
from infra.enrollment.tests.test_app import make_config
from infra.enrollment.tests.fakes import FakeLoginAuthorityClient, FakeOpnsenseWireguardClient
from infra.enrollment.store import EnrollmentStore


def test_patches_are_publicly_served_without_auth(tmp_path):
    patches = tmp_path / "patches"
    (patches / "0.7.0").mkdir(parents=True)
    (patches / "manifest.json").write_bytes(b'{"schema_version":1}')
    (patches / "manifest.sig").write_bytes(b"signature")
    (patches / "0.7.0" / "Project0.pck").write_bytes(b"pack")

    store = EnrollmentStore(":memory:")
    try:
        service = EnrollmentService(make_config(), store, FakeOpnsenseWireguardClient())
        client = TestClient(create_app(service, FakeLoginAuthorityClient(), patches_dir=str(patches)))

        assert client.get("/patches/manifest.json").status_code == 200
        assert client.get("/patches/manifest.sig").content == b"signature"
        assert client.get("/patches/0.7.0/Project0.pck").content == b"pack"
        assert client.get("/patches/missing.pck").status_code == 404
    finally:
        store.close()


def test_patches_are_not_mounted_when_unconfigured():
    store = EnrollmentStore(":memory:")
    try:
        service = EnrollmentService(make_config(), store, FakeOpnsenseWireguardClient())
        client = TestClient(create_app(service, FakeLoginAuthorityClient()))
        assert client.get("/patches/manifest.json").status_code == 404
    finally:
        store.close()
