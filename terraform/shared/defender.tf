resource "azurerm_security_center_subscription_pricing" "containers" {
  tier          = "Standard"
  resource_type = "Containers"

  extension { name = "ContainerRegistriesVulnerabilityAssessments" }
  extension { name = "AgentlessDiscoveryForKubernetes" }
  extension { name = "AgentlessVmScanning" }
  # ContainerSensor = the per-node Defender DaemonSet
  extension { name = "ContainerSensor" }
}
