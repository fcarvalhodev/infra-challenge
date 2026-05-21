"""
Robots Inc. Infrastructure Health API
Uses the VM's system-assigned managed identity (vm-mi) for all Azure calls.
No secrets in code or environment variables.
"""
import os
import logging
from contextlib import asynccontextmanager
from typing import Optional

from fastapi import FastAPI, HTTPException, Header, Request
from fastapi.responses import JSONResponse

from azure.identity import ManagedIdentityCredential
from azure.keyvault.secrets import SecretClient
from azure.mgmt.resource import ResourceManagementClient
from azure.mgmt.authorization import AuthorizationManagementClient
from azure.storage.blob import BlobServiceClient
from azure.core.exceptions import HttpResponseError, ServiceRequestError

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Config from environment (non-secret infrastructure params)
# ---------------------------------------------------------------------------
SUBSCRIPTION_ID    = os.environ["SUBSCRIPTION_ID"]
RESOURCE_GROUP     = os.environ["RESOURCE_GROUP_NAME"]
KEY_VAULT_URL      = os.environ["KEY_VAULT_URL"]        # https://<name>.vault.azure.net/
STORAGE_ACCOUNT    = os.environ["STORAGE_ACCOUNT_NAME"]
VM_PRINCIPAL_ID    = os.environ["VM_PRINCIPAL_ID"]       # vm-mi object ID for role filtering

# ---------------------------------------------------------------------------
# Shared credential — system-assigned MI (no client_id = system-assigned)
# ---------------------------------------------------------------------------
credential = ManagedIdentityCredential()

# API key holder — populated at startup
_api_key: Optional[str] = None


# ---------------------------------------------------------------------------
# Startup: fetch API key from Key Vault using vm-mi
# ---------------------------------------------------------------------------
@asynccontextmanager
async def lifespan(app: FastAPI):
    global _api_key
    logger.info("Fetching api-key from Key Vault at startup...")
    kv_client = SecretClient(vault_url=KEY_VAULT_URL, credential=credential)
    secret = kv_client.get_secret("api-key")
    _api_key = secret.value
    logger.info("API key loaded successfully.")
    yield
    # Cleanup (nothing to do)


app = FastAPI(title="Robots Inc. Infra Health API", lifespan=lifespan)


# ---------------------------------------------------------------------------
# Auth helper
# ---------------------------------------------------------------------------
def _check_api_key(x_api_key: Optional[str]) -> None:
    if not x_api_key or x_api_key != _api_key:
        raise HTTPException(status_code=401, detail="Unauthorized")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
def _scope_type(scope: str) -> str:
    """Classify an ARM scope string into a human-readable type."""
    parts = [p for p in scope.strip("/").split("/") if p]
    if len(parts) == 2:
        return "Subscription"
    elif len(parts) == 4:
        return "ResourceGroup"
    else:
        return "Resource"


def _is_candidate_resource(resource) -> bool:
    """
    Return True if this resource belongs to the candidate's deployment.
    We identify ownership by the presence of the Owner=fabio tag.
    Interviewer-managed bootstrap resources lack this tag.
    """
    tags = resource.tags or {}
    return tags.get("Owner", "").lower() == "fabio"


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------

@app.get("/health")
def health():
    return {"status": "ok"}


@app.get("/resources")
def list_resources(x_api_key: Optional[str] = Header(None)):
    _check_api_key(x_api_key)
    rm = ResourceManagementClient(credential, SUBSCRIPTION_ID)
    result = []
    for r in rm.resources.list_by_resource_group(RESOURCE_GROUP):
        if not _is_candidate_resource(r):
            continue
        result.append({
            "name": r.name,
            "type": r.type,
            "location": r.location,
            "provisioning_state": (r.properties or {}).get("provisioningState"),
            "tags": r.tags or {},
        })
    return result


@app.get("/resources/{name}")
def get_resource(name: str, x_api_key: Optional[str] = Header(None)):
    _check_api_key(x_api_key)
    rm = ResourceManagementClient(credential, SUBSCRIPTION_ID)
    for r in rm.resources.list_by_resource_group(RESOURCE_GROUP):
        if r.name == name and _is_candidate_resource(r):
            return {
                "name": r.name,
                "type": r.type,
                "location": r.location,
                "provisioning_state": (r.properties or {}).get("provisioningState"),
                "tags": r.tags or {},
            }
    raise HTTPException(status_code=404, detail=f"Resource '{name}' not found")


@app.get("/identity/roles")
def identity_roles(x_api_key: Optional[str] = Header(None)):
    _check_api_key(x_api_key)
    auth = AuthorizationManagementClient(credential, SUBSCRIPTION_ID)

    rg_scope = f"/subscriptions/{SUBSCRIPTION_ID}/resourceGroups/{RESOURCE_GROUP}"

    # List all role assignments for vm-mi at subscription scope
    # (covers RG-level and resource-level assignments)
    sub_scope = f"/subscriptions/{SUBSCRIPTION_ID}"
    assignments = list(
        auth.role_assignments.list_for_scope(
            sub_scope,
            filter=f"principalId eq '{VM_PRINCIPAL_ID}'"
        )
    )

    result = []
    for a in assignments:
        try:
            role_def = auth.role_definitions.get_by_id(a.role_definition_id)
            role_name = role_def.role_name
        except Exception:
            role_name = a.role_definition_id  # fallback to ID if resolution fails

        result.append({
            "role_definition_name": role_name,
            "scope": a.scope,
            "scope_type": _scope_type(a.scope),
        })

    return result


@app.get("/storage/ping")
def storage_ping(x_api_key: Optional[str] = Header(None)):
    _check_api_key(x_api_key)
    account_url = f"https://{STORAGE_ACCOUNT}.blob.core.windows.net"
    try:
        blob_svc = BlobServiceClient(account_url=account_url, credential=credential)
        blob_client = blob_svc.get_blob_client(container="healthcheck", blob="ping.txt")
        blob_client.download_blob().readall()
        return {
            "reachable": True,
            "account": STORAGE_ACCOUNT,
            "container": "healthcheck",
            "via": "private_endpoint",
        }
    except (HttpResponseError, ServiceRequestError, Exception) as exc:
        logger.error("Storage ping failed: %s", exc)
        return JSONResponse(
            status_code=503,
            content={
                "reachable": False,
                "account": STORAGE_ACCOUNT,
                "container": "healthcheck",
                "error": str(exc),
            },
        )
