# ---------------------------------------------------------------------------
# observability/main.tf
# Creates:
#   • Log Analytics workspace — 30-day retention, daily ingestion cap
#   • Diagnostic settings on Key Vault and Storage Account
#   • One metric alert: Key Vault availability < 100% for 5 min
#     Justification: KV unavailability means the API cannot fetch its api-key
#     at startup, causing total service failure. Early warning prevents silent
#     outages in prod.
# ---------------------------------------------------------------------------

resource "azurerm_log_analytics_workspace" "main" {
  name                = "law-fabio-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "PerGB2018" # pay-per-GB; cheapest option for small lab
  retention_in_days   = 30         # minimum; keeps recurring cost low
  tags                = var.tags

  # Daily ingestion cap — prevents runaway cost from noisy diagnostics
  daily_quota_gb = var.daily_quota_gb
}

# ── Key Vault diagnostics ─────────────────────────────────────────────────────
resource "azurerm_monitor_diagnostic_setting" "keyvault" {
  name                       = "diag-kv-fabio-${var.environment}"
  target_resource_id         = var.key_vault_id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  enabled_log {
    category = "AuditEvent"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# ── Storage Account diagnostics ───────────────────────────────────────────────
resource "azurerm_monitor_diagnostic_setting" "storage" {
  name                       = "diag-storage-fabio-${var.environment}"
  target_resource_id         = "${var.storage_account_id}/blobServices/default"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  enabled_log {
    category = "StorageRead"
  }

  metric {
    category = "Transaction"
    enabled  = true
  }
}

# ── Metric Alert: Key Vault Availability ──────────────────────────────────────
resource "azurerm_monitor_metric_alert" "kv_availability" {
  name                = "alert-kv-availability-fabio-${var.environment}"
  resource_group_name = var.resource_group_name
  scopes              = [var.key_vault_id]
  description         = "Fires when Key Vault availability drops below 100% — API will fail to start if KV is unreachable"
  severity            = var.alert_severity # 2=Warning (dev), 1=Error (prod)
  frequency           = "PT5M"
  window_size         = "PT5M"
  tags                = var.tags

  criteria {
    metric_namespace = "Microsoft.KeyVault/vaults"
    metric_name      = "Availability"
    aggregation      = "Average"
    operator         = "LessThan"
    threshold        = 100
  }

  # No action group in this lab — alert is observable in Azure Monitor
  # In production, attach an action group for PagerDuty/email.
}
