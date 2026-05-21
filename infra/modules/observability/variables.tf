variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "environment" { type = string }
variable "key_vault_id" { type = string }
variable "storage_account_id" { type = string }

variable "daily_quota_gb" {
  type        = number
  description = "Log Analytics daily ingestion cap in GB. 0.5 (dev) or 1 (prod)."
  default     = 0.5
}

variable "alert_severity" {
  type        = number
  description = "Alert severity: 2=Warning (dev), 1=Error (prod)"
  default     = 2
}

variable "tags" {
  type    = map(string)
  default = {}
}
