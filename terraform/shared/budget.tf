# Budget is scoped to the whole subscription rather than the resource group, because
# the bootstrap state is in different RG

locals {
  # Budget needs a start date that is the first of a month, in the past or current month.
  budget_start = formatdate("YYYY-MM-01", timestamp())
  name_short_prefix  = "rk964"
}

data "azurerm_subscription" "current" {}

resource "azurerm_consumption_budget_subscription" "lab" {
  name            = "budget-${local.name_short_prefix}"
  subscription_id = data.azurerm_subscription.current.id
  amount          = var.budget_amount_usd
  time_grain      = "Monthly"

  time_period {
    start_date = "${local.budget_start}T00:00:00Z"
  }

  # Warn at 50%, action at 90% (still under the cap so you can react).
  notification {
    enabled        = true
    threshold      = 50
    operator       = "GreaterThan"
    threshold_type = "Actual"
    contact_emails = compact([var.budget_contact_email])
  }

  notification {
    enabled        = true
    threshold      = 90
    operator       = "GreaterThan"
    threshold_type = "Actual"
    contact_emails = compact([var.budget_contact_email])
  }

  # Forecast-based alert: fires if Azure projects exceed the budget,
  # which catches runaway spend earlier than actual-usage alerts.
  notification {
    enabled        = true
    threshold      = 100
    operator       = "GreaterThan"
    threshold_type = "Forecasted"
    contact_emails = compact([var.budget_contact_email])
  }

  # timestamp() in start_date will trigger drift on every plan. Tell Terraform to ignore.
  lifecycle {
    ignore_changes = [time_period]
  }
}

