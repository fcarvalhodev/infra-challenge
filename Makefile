ENV ?= dev

.PHONY: help init plan apply destroy env docker-up docker-down \
        test-api test-infra test logs

help:
	@echo "Targets:"
	@echo "  init         terragrunt run-all init  (ENV=dev|prod)"
	@echo "  plan         terragrunt run-all plan"
	@echo "  apply        deploy all infra modules in order"
	@echo "  destroy      tear down candidate-managed resources only"
	@echo "  env          write .env from Terraform outputs (run after apply)"
	@echo "  docker-up    build and start API + Caddy"
	@echo "  docker-down  stop containers"
	@echo "  test-api     run pytest against the live API"
	@echo "  test-infra   run Terratest Go tests"
	@echo "  logs         tail API container logs"

# ── Terraform / Terragrunt ───────────────────────────────────────────────────
TGDIR := infra/live/$(ENV)

init:
	cd $(TGDIR) && terragrunt run-all init --terragrunt-non-interactive

plan:
	cd $(TGDIR) && terragrunt run-all plan --terragrunt-non-interactive

apply:
	@echo "==> Deploying networking..."
	cd $(TGDIR)/networking   && terragrunt apply -auto-approve
	@echo "==> Deploying storage..."
	cd $(TGDIR)/storage      && terragrunt apply -auto-approve
	@echo "==> Deploying keyvault..."
	cd $(TGDIR)/keyvault     && terragrunt apply -auto-approve
	@echo "==> Deploying observability..."
	cd $(TGDIR)/observability && terragrunt apply -auto-approve
	@echo "==> Creating RBAC assignments..."
	cd $(TGDIR)/rbac         && terragrunt apply -auto-approve
	@echo "==> Infra ready. Run: make env && make docker-up"

# Destroy in reverse order; skip bootstrap resources
destroy:
	@echo "==> Removing RBAC assignments..."
	cd $(TGDIR)/rbac          && terragrunt destroy -auto-approve || true
	@echo "==> Removing observability..."
	cd $(TGDIR)/observability  && terragrunt destroy -auto-approve || true
	@echo "==> Removing keyvault..."
	cd $(TGDIR)/keyvault       && terragrunt destroy -auto-approve || true
	@echo "==> Removing storage..."
	cd $(TGDIR)/storage        && terragrunt destroy -auto-approve || true
	@echo "==> Removing networking..."
	cd $(TGDIR)/networking     && terragrunt destroy -auto-approve || true
	@echo "==> Stopping containers..."
	docker compose down || true
	@echo "==> Destroy complete. Bootstrap VM, VNet A, and admin KV are untouched."

# ── Environment file ─────────────────────────────────────────────────────────
# Reads Terraform outputs and writes .env for docker compose
env:
	@echo "Generating .env from Terraform outputs..."
	@KV_URI=$$(cd $(TGDIR)/keyvault && terragrunt output -raw key_vault_uri 2>/dev/null); \
	SA_NAME=$$(cd $(TGDIR)/storage  && terragrunt output -raw storage_account_name 2>/dev/null); \
	if [ -z "$$KV_URI" ] || [ -z "$$SA_NAME" ]; then \
	  echo "ERROR: could not read Terraform outputs. Run 'make apply ENV=$(ENV)' first."; \
	  exit 1; \
	fi; \
	printf "KEY_VAULT_URL=$$KV_URI\nSTORAGE_ACCOUNT_NAME=$$SA_NAME\n" > .env; \
	echo ".env written:"; cat .env

# ── Docker ───────────────────────────────────────────────────────────────────
docker-up:
	docker compose up -d --build

docker-down:
	docker compose down

logs:
	docker compose logs -f api

# ── Tests ────────────────────────────────────────────────────────────────────
test-api:
	@if [ -z "$$API_KEY" ]; then \
	  echo "Set API_KEY env var: export API_KEY=\$$(cd infra/live/$(ENV)/keyvault && terragrunt output -raw api_key_value 2>/dev/null || echo '')"; \
	  exit 1; \
	fi
	cd api/tests && API_BASE_URL=$${API_BASE_URL:-http://localhost:80} pytest -v

test-infra:
	cd tests/infra && go test -v -timeout 30m ./...
