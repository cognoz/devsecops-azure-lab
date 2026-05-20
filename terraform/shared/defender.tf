resource "azurerm_security_center_subscription_pricing" "containers" {
  count = var.defender_for_containers_enabled ? 1 : 0

  tier          = "Standard"
  resource_type = "Containers"

  extension {
    name = "ContainerRegistriesVulnerabilityAssessments"
  }

  extension {
    name = "AgentlessDiscoveryForKubernetes"
  }

  extension {
    name = "AgentlessVmScanning"
  }

  extension {
    name = "ContainerSensor"
  }
}
