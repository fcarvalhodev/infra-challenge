"""
API tests for the Robots Inc. Infrastructure Health API.
"""
import os
import urllib3
import pytest
import requests

urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

BASE_URL   = os.environ.get("API_BASE_URL", "https://localhost").rstrip("/")
VALID_KEY  = os.environ.get("API_KEY", "")
WRONG_KEY  = "this-is-definitely-wrong-0000000"

def get(path, key=None, **kwargs):
    headers = {"X-API-Key": key} if key else {}
    return requests.get(f"{BASE_URL}{path}", headers=headers, verify=False, **kwargs)

class TestHealth:
    def test_health_returns_200(self):
        assert get("/health").status_code == 200
    def test_health_body(self):
        assert get("/health").json() == {"status": "ok"}
    def test_health_no_auth_required(self):
        assert get("/health").status_code == 200

PROTECTED_PATHS = ["/resources", "/identity/roles", "/storage/ping"]

@pytest.mark.parametrize("path", PROTECTED_PATHS)
class TestAuth:
    def test_missing_key_returns_401(self, path):
        assert get(path).status_code == 401
    def test_wrong_key_returns_401(self, path):
        assert get(path, key=WRONG_KEY).status_code == 401
    def test_valid_key_does_not_return_401(self, path):
        if not VALID_KEY:
            pytest.skip("API_KEY not set")
        assert get(path, key=VALID_KEY).status_code != 401

class TestResources:
    @pytest.fixture(autouse=True)
    def _key(self):
        if not VALID_KEY:
            pytest.skip("API_KEY not set")
    def test_list_returns_200(self):
        assert get("/resources", key=VALID_KEY).status_code == 200
    def test_list_is_array(self):
        assert isinstance(get("/resources", key=VALID_KEY).json(), list)
    def test_list_items_have_required_fields(self):
        data = get("/resources", key=VALID_KEY).json()
        required = {"name", "type", "location", "provisioning_state", "tags"}
        for item in data:
            assert required.issubset(item.keys())
    def test_get_nonexistent_returns_404(self):
        assert get("/resources/this-does-not-exist-xyz", key=VALID_KEY).status_code == 404
    def test_get_existing_resource(self):
        items = get("/resources", key=VALID_KEY).json()
        if not items:
            pytest.skip("No candidate resources found")
        name = items[0]["name"]
        r = get(f"/resources/{name}", key=VALID_KEY)
        assert r.status_code == 200
        assert r.json()["name"] == name

class TestIdentityRoles:
    @pytest.fixture(autouse=True)
    def _key(self):
        if not VALID_KEY:
            pytest.skip("API_KEY not set")
    def test_returns_200(self):
        assert get("/identity/roles", key=VALID_KEY).status_code == 200
    def test_returns_array(self):
        assert isinstance(get("/identity/roles", key=VALID_KEY).json(), list)
    def test_has_exactly_three_assignments(self):
        data = get("/identity/roles", key=VALID_KEY).json()
        assert len(data) == 3, f"Expected 3, got {len(data)}: {data}"
    def test_has_reader_on_resource_group(self):
        data = get("/identity/roles", key=VALID_KEY).json()
        assert ("Reader", "ResourceGroup") in {(i["role_definition_name"], i["scope_type"]) for i in data}
    def test_has_kv_secrets_user(self):
        assert "Key Vault Secrets User" in [i["role_definition_name"] for i in get("/identity/roles", key=VALID_KEY).json()]
    def test_has_storage_blob_data_reader(self):
        assert "Storage Blob Data Reader" in [i["role_definition_name"] for i in get("/identity/roles", key=VALID_KEY).json()]
    def test_no_privileged_roles(self):
        forbidden = {"Owner","Contributor","User Access Administrator","Role Based Access Control Administrator"}
        data = get("/identity/roles", key=VALID_KEY).json()
        overlap = forbidden & {i["role_definition_name"] for i in data}
        assert not overlap, f"vm-mi has forbidden roles: {overlap}"
    def test_items_have_required_fields(self):
        for item in get("/identity/roles", key=VALID_KEY).json():
            assert {"role_definition_name","scope","scope_type"}.issubset(item.keys())

class TestStoragePing:
    @pytest.fixture(autouse=True)
    def _key(self):
        if not VALID_KEY:
            pytest.skip("API_KEY not set")
    def test_returns_200(self):
        assert get("/storage/ping", key=VALID_KEY).status_code == 200
    def test_reachable_true(self):
        assert get("/storage/ping", key=VALID_KEY).json()["reachable"] is True
    def test_response_shape(self):
        data = get("/storage/ping", key=VALID_KEY).json()
        assert data["container"] == "healthcheck"
        assert data["via"] == "private_endpoint"
        assert "account" in data
