# Look up the LAW that lives in cluster/'s state by name. Deliberately
# avoid pulling it from cluster/'s remote_state outputs to keep shared/
# independent of cluster/
data "azurerm_log_analytics_workspace" "cluster" {
  count               = var.defender_for_containers_enabled && var.defender_export_enabled ? 1 : 0
  depends_on          = [azurerm_log_analytics_workspace.lab]
  name                = var.defender_export_law_name
  resource_group_name = var.defender_export_law_resource_group
}

resource "azurerm_security_center_automation" "export_to_workspace" {
  count = var.defender_for_containers_enabled && var.defender_export_enabled ? 1 : 0

  # Canonical name — required for the portal UI to show the export as configured.
  name                = "ExportToWorkspace"
  resource_group_name = azurerm_resource_group.shared.name
  location            = azurerm_resource_group.shared.location

  enabled = true
  scopes  = ["/subscriptions/${data.azurerm_subscription.current.subscription_id}"]

  action {
    type        = "loganalytics"
    resource_id = data.azurerm_log_analytics_workspace.cluster[0].id
  }

  source {
    event_source = "Alerts"
  }

  # Only ship ones that have actually triggered
  source {
    event_source = "Assessments"

    rule_set {
      rule {
        property_path  = "Status.Code"
        operator       = "Equals"
        expected_value = "Unhealthy"
        property_type  = "String"
      }
    }
  }

  # Sub-assessments are the per-finding detail under an assessment.
  source {
    event_source = "SubAssessments"
  }

  tags = local.common_tags
}
