"""
API tests for the Robots Inc. Infrastructure Health API.
These tests run against a live deployment.

Usage:
    API_BASE_URL=http://localhost:80 API_KEY=<key> pytest -v
"""
import os
import pytest
import requests

BASE_URL = os.environ.get("API_BASE_URL", "http://localhost:80").rstrip("/")
VALID_KEY = os.environ.get("API_KEY", "")
WRONG_KEY  = "this-is-definitely-wrong-0000000"


# ---------------------------------------------------------------------------
# /health
# ---------------------------------------------------------------------------
class TestHealth:
    def test_health_returns_200(self):
        r = requests.get(f"{BASE_URL}/health")
        assert r.status_code == 200

    def test_health_body(self):
        r = requests.get(f"{BASE_URL}/health")
        assert r.json() == {"status": "ok"}

    def test_health_no_auth_required(self):
        """Health endpoint must work without any API key."""
        r = requests.get(f"{BASE_URL}/health", headers={})
        assert r.status_code == 200


# ---------------------------------------------------------------------------
# Authentication — every protected endpoint
# ---------------------------------------------------------------------------
PROTECTED_PATHS = ["/resources", "/identity/roles", "/storage/ping"]


@pytest.mark.parametrize("path", PROTECTED_PATHS)
class TestAuth:
    def test_missing_key_returns_401(self, path):
        r = requests.get(f"{BASE_URL}{path}")
        assert r.status_code == 401

    def test_wrong_key_returns_401(self, path):
        r = requests.get(f"{BASE_URL}{path}", headers={"X-API-Key": WRONG_KEY})
        assert r.status_code == 401

    def test_valid_key_does_not_return_401(self, path):
        if not VALID_KEY:
            pytest.skip("API_KEY not set")
        r = requests.get(f"{BASE_URL}{path}", headers={"X-API-Key": VALID_KEY})
        assert r.status_code != 401


# ---------------------------------------------------------------------------
# /resources
# ---------------------------------------------------------------------------
class TestResources:
    @pytest.fixture(autouse=True)
    def _key(self):
        if not VALID_KEY:
            pytest.skip("API_KEY not set")

    def _get(self, path=""):
        return requests.get(
            f"{BASE_URL}/resources{path}",
            headers={"X-API-Key": VALID_KEY},
        )

    def test_list_returns_200(self):
        assert self._get().status_code == 200

    def test_list_is_array(self):
        data = self._get().json()
        assert isinstance(data, list)

    def test_list_items_have_required_fields(self):
        data = self._get().json()
        required = {"name", "type", "location", "provisioning_state", "tags"}
        for item in data:
            assert required.issubset(item.keys()), f"Missing fields in {item}"

    def test_get_nonexistent_returns_404(self):
        r = self._get("/this-resource-absolutely-does-not-exist-xyz")
        assert r.status_code == 404

    def test_get_existing_resource(self):
        """If the list is non-empty, GET /resources/{name} must return the same object."""
        items = self._get().json()
        if not items:
            pytest.skip("No candidate resources found")
        name = items[0]["name"]
        r = self._get(f"/{name}")
        assert r.status_code == 200
        assert r.json()["name"] == name


# ---------------------------------------------------------------------------
# /identity/roles
# ---------------------------------------------------------------------------
class TestIdentityRoles:
    @pytest.fixture(autouse=True)
    def _key(self):
        if not VALID_KEY:
            pytest.skip("API_KEY not set")

    def _get(self):
        return requests.get(
            f"{BASE_URL}/identity/roles",
            headers={"X-API-Key": VALID_KEY},
        )

    def test_returns_200(self):
        assert self._get().status_code == 200

    def test_returns_array(self):
        assert isinstance(self._get().json(), list)

    def test_has_exactly_three_assignments(self):
        """vm-mi must have exactly the three runtime assignments, no more."""
        data = self._get().json()
        assert len(data) == 3, f"Expected 3 role assignments, got {len(data)}: {data}"

    def test_has_reader_on_resource_group(self):
        data = self._get().json()
        roles = {(item["role_definition_name"], item["scope_type"]) for item in data}
        assert ("Reader", "ResourceGroup") in roles

    def test_has_kv_secrets_user(self):
        data = self._get().json()
        role_names = [item["role_definition_name"] for item in data]
        assert "Key Vault Secrets User" in role_names

    def test_has_storage_blob_data_reader(self):
        data = self._get().json()
        role_names = [item["role_definition_name"] for item in data]
        assert "Storage Blob Data Reader" in role_names

    def test_no_privileged_roles(self):
        """vm-mi must NOT have Owner, Contributor, or RBAC Admin."""
        forbidden = {"Owner", "Contributor", "User Access Administrator",
                     "Role Based Access Control Administrator"}
        data = self._get().json()
        actual = {item["role_definition_name"] for item in data}
        overlap = forbidden & actual
        assert not overlap, f"vm-mi has forbidden roles: {overlap}"

    def test_items_have_required_fields(self):
        data = self._get().json()
        required = {"role_definition_name", "scope", "scope_type"}
        for item in data:
            assert required.issubset(item.keys())


# ---------------------------------------------------------------------------
# /storage/ping
# ---------------------------------------------------------------------------
class TestStoragePing:
    @pytest.fixture(autouse=True)
    def _key(self):
        if not VALID_KEY:
            pytest.skip("API_KEY not set")

    def _get(self):
        return requests.get(
            f"{BASE_URL}/storage/ping",
            headers={"X-API-Key": VALID_KEY},
        )

    def test_returns_200(self):
        assert self._get().status_code == 200

    def test_reachable_true(self):
        data = self._get().json()
        assert data["reachable"] is True

    def test_response_shape(self):
        data = self._get().json()
        assert data["container"] == "healthcheck"
        assert data["via"] == "private_endpoint"
        assert "account" in data
