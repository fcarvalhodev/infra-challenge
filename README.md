# Robots Inc. Azure Infrastructure Challenge

**Candidate:** Fabio Carvalho
**Repository:** https://github.com/fcarvalhodev/infra-challenge

---

## Quick Start for Reviewers

The deployment is live on the bootstrap VM. To verify:

    curl -sk https://localhost/health

To get the API key and run all tests:

    cd ~/challenge
    az login --identity --client-id 297f855a-c1c3-4a2a-94c8-04e9b4557c62
    export API_KEY=$(cd infra/live/dev/keyvault && terragrunt output -raw api_key_value)

    # API tests (28 tests)
    cd api/tests && API_BASE_URL=https://localhost API_KEY=$API_KEY python3 -m pytest -v

    # Infrastructure tests (5 tests)
    cd ~/challenge/tests/infra && go test -v -timeout 30m ./...

---

## Architecture

````mermaid
graph TD
    subgraph VNetA["VNet A 10.0.0.0/16 — provided"]
        VM["vm-fabio-001
Caddy :443 → API :8000"]
        VMID["vm-mi system-assigned"]
        VM --> VMID
    end

    subgraph VNetB["VNet B 10.1.0.0/16 — candidate"]
        subgraph Subnet["snet-storage 10.1.0.0/24 + NSG"]
            PE["pe-storage-fabio-dev
10.1.0.4"]
        end
    end

    subgraph RG["rg-devtest-lab-interviews"]
        KV["kv-fabio-dev-1df2f8
api-key secret"]
        SA["stfabiodev8803c819
healthcheck/ping.txt"]
        LAW["law-fabio-dev
30d retention 0.5GB/day cap"]
        DNS["privatelink.blob.core.windows.net"]
    end

    VMID -->|"Storage Blob Data Reader"| PE
    PE --> SA
    VMID -->|"Key Vault Secrets User"| KV
    VMID -->|"Reader"| RG
    DNS -->|"A record 10.1.0.4"| PE
    SA --> LAW
    KV --> LAW
    VNetA -.->|"VNet Peering"| VNetB
```

---

## Identity Lanes

| Identity | Role | Scope | Purpose |
|---|---|---|---|
| vm-mi (system-assigned) | Reader | Resource Group | Running API — list resources |
| vm-mi (system-assigned) | Key Vault Secrets User | App Key Vault | Running API — read api-key |
| vm-mi (system-assigned) | Storage Blob Data Reader | Storage Account | Running API — read ping.txt |
| id-manager (user-assigned) | Contributor | Resource Group | Terraform provisioning only |
| id-manager (user-assigned) | Key Vault Secrets Officer | App Key Vault | Terraform secret write (provisioning only) |
| access-manager (user-assigned) | RBAC Admin | Resource Group | Terraform role assignments only |

---

## RBAC Matrix

| Identity | Read api-key | Read ping.txt | List RG | Write storage | Create resources | Assign roles |
|---|---|---|---|---|---|---|
| vm-mi | YES | YES | YES | NO | NO | NO |
| id-manager | YES (write+read) | NO | YES | NO | YES | NO |
| access-manager | NO | NO | NO | NO | NO | YES |

---

## Prerequisites (one-time setup on the bootstrap VM)

    # Terragrunt
    curl -sL https://github.com/gruntwork-io/terragrunt/releases/download/v0.58.0/terragrunt_linux_amd64 \
      -o /usr/local/bin/terragrunt && sudo chmod +x /usr/local/bin/terragrunt

    # Docker Compose v2
    DOCKER_CONFIG=${DOCKER_CONFIG:-$HOME/.docker}
    mkdir -p $DOCKER_CONFIG/cli-plugins
    curl -SL https://github.com/docker/compose/releases/download/v2.27.0/docker-compose-linux-x86_64 \
      -o $DOCKER_CONFIG/cli-plugins/docker-compose && chmod +x $DOCKER_CONFIG/cli-plugins/docker-compose

    # Go (for Terratest)
    curl -sL https://go.dev/dl/go1.21.11.linux-amd64.tar.gz | sudo tar -C /usr/local -xz
    export PATH=$PATH:/usr/local/go/bin

    # Python test deps
    pip3 install pytest requests

---

## Step-by-step Deploy

### 1. Clone the repository

    git clone https://github.com/fcarvalhodev/infra-challenge.git challenge
    cd challenge

### 2. Fill in tag values from the assignment email

    find infra/live -name "terragrunt.hcl" | xargs sed -i \
      's/CostCenter   = "FILL_ME"/CostCenter   = "<your-value>"/g'
    find infra/live -name "terragrunt.hcl" | xargs sed -i \
      's/AssignmentId = "FILL_ME"/AssignmentId = "<your-value>"/g'

### 3. Login as id-manager (provisioning identity)

    az login --identity --client-id 297f855a-c1c3-4a2a-94c8-04e9b4557c62

### 4. Initialize Terraform

    make init ENV=dev

### 5. Deploy all infrastructure modules

    make apply ENV=dev

Modules deploy in this order:

1. networking — VNet B, NSG, VNet peering A to B, private DNS zone
2. storage — storage account, private endpoint, ping.txt blob
3. keyvault — application Key Vault, api-key secret
4. observability — Log Analytics, diagnostic settings, metric alert
5. rbac — 3 role assignments for vm-mi via access-manager

### 6. Start the API

    # Stop system Caddy if it is occupying port 80/443
    sudo systemctl stop caddy 2>/dev/null || true

    # Write .env from Terraform outputs
    make env ENV=dev

    # Build and start API + Caddy
    make docker-up

    # Verify
    curl -sk https://localhost/health

### 7. Enable real HTTPS when DNS hostname is provided

Replace localhost in caddy/Caddyfile with the assigned hostname:

    fabio.interviews.robots-inc.io {
        reverse_proxy api:8000
    }

Then restart Caddy — it will obtain a Let's Encrypt certificate automatically:

    docker compose restart caddy

---

## Step-by-step Destroy

Destroys only candidate-managed resources. Bootstrap VM, VNet A, admin Key Vault, id-manager, and access-manager are never touched.

    # Stop containers
    make docker-down

    # Login as id-manager
    az login --identity --client-id 297f855a-c1c3-4a2a-94c8-04e9b4557c62

    # Destroy all modules in reverse order
    make destroy ENV=dev

---

## Running Tests

### API tests — 28 tests

    az login --identity --client-id 297f855a-c1c3-4a2a-94c8-04e9b4557c62
    export API_KEY=$(cd infra/live/dev/keyvault && terragrunt output -raw api_key_value)
    cd api/tests && API_BASE_URL=https://localhost API_KEY=$API_KEY python3 -m pytest -v

### Infrastructure tests — 5 tests

    az login --identity --client-id 297f855a-c1c3-4a2a-94c8-04e9b4557c62
    cd tests/infra && go test -v -timeout 30m ./...

What the infra tests validate:

- VNet peering is Connected in both directions
- Every candidate subnet has an NSG with no 0.0.0.0/0 inbound rule
- Storage FQDN resolves to private IP 10.1.0.4
- Storage public network access is disabled
- vm-mi has exactly 3 role assignments with no privileged roles

---

## Design Decisions

### NSG rules

The storage subnet NSG allows inbound HTTPS only from VNet A (10.0.0.0/16), which is the CIDR containing the bootstrap VM. All other inbound traffic is denied at priority 4000. There is no 0.0.0.0/0 allow rule anywhere. Outbound is permitted only back to VNet A and within VNet B.

### Why vm-mi for runtime and id-manager for provisioning

Least privilege by lane. The running API only reads — it never creates or modifies infrastructure. Giving it Contributor would turn a container escape into an infrastructure escape. id-manager is Contributor for provisioning but cannot assign roles, preventing privilege escalation.

### How the API authenticates without storing credentials

ManagedIdentityCredential() with no client_id argument uses the system-assigned identity. It acquires short-lived OAuth2 tokens from the Azure IMDS endpoint (169.254.169.254). Tokens are automatically refreshed by the SDK. No secrets, no service principal keys, no credentials in environment variables.

### Why a candidate-owned Key Vault instead of the shared admin vault

The shared KV (dtlinterviews3004) is interviewer-managed infrastructure. Storing the API key there would require granting vm-mi access to a vault we do not own, leave traces after teardown, and violate the resource ownership boundary defined in the challenge.

### Metric alert choice

Key Vault Availability below 100% for 5 minutes. If the KV becomes unavailable, the API cannot fetch its api-key at startup, causing total service failure with no visible error to callers. The alert provides early warning before a KV issue becomes a deployment failure. Dev uses Warning severity; prod uses Error severity.

### Recurring cost resources

| Resource | Cost driver | Mitigation |
|---|---|---|
| Private Endpoint | ~$7/month | One PE per env; removed on destroy |
| Log Analytics | Per-GB ingestion | 30-day retention; 0.5 GB/day cap in dev, 1 GB/day in prod |
| Storage Account | Capacity and transactions | LRS in dev; ZRS only in prod |

VNets, NSGs, managed identities, RBAC assignments, and private DNS zones have no meaningful direct cost.

---

## What Was Provided vs What Was Created

### Provided by interviewer — not modified

- vm-fabio-001 — bootstrap VM
- vnet-lab-interviews — VNet A (10.0.0.0/16)
- dtlinterviews3004 — shared admin Key Vault
- id-manager-fabio-001 — provisioning identity
- access-manager-fabio-001 — RBAC assignment identity
- stinterviewtfstate001 — Terraform state backend

### Created by this solution

- vnet-b-fabio-dev — VNet B (10.1.0.0/16)
- nsg-storage-fabio-dev — NSG for storage subnet
- snet-storage-fabio-dev — storage subnet (10.1.0.0/24)
- stfabiodev8803c819 — storage account (LRS, public access disabled)
- pe-storage-fabio-dev — private endpoint (10.1.0.4)
- privatelink.blob.core.windows.net — private DNS zone + VNet links
- kv-fabio-dev-1df2f8 — application Key Vault
- law-fabio-dev — Log Analytics workspace
- 3 role assignments for vm-mi

---

## Missing Items — Pending Interviewer Input

| Item | What is needed | Current state |
|---|---|---|
| Real TLS certificate | DNS hostname delegation | Self-signed cert on localhost. One-line Caddyfile change when hostname is provided. |
| CostCenter tag value | Value from assignment email | Placeholder: interview-lab |
| AssignmentId tag value | Value from assignment email | Placeholder: fabio-001 |

---

## Known Issues and Things I Would Do With More Time

- State backend auth: Currently uses account key (listKeys) for the Terraform backend. Proper least-privilege would grant each identity Storage Blob Data Contributor on the tfstate container and use use_azuread_auth = true. Blocked by access-manager not having Contributor on the state account.

- Secret rotation: The api-key is set once at terraform apply. A production setup would use Key Vault rotation policies with an Event Grid trigger.

- Prod environment: Terragrunt is fully configured for prod with ZRS storage, stricter alert thresholds, and a separate state key. Not deployed as the interviewer confirmed dev is sufficient for the assessment.

- Observability deprecations: azurerm v4 deprecated the metric block in diagnostic settings in favour of enabled_metric. Will be a breaking change in v5.
