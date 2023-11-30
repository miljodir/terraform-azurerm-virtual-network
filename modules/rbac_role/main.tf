resource "azurerm_role_assignment" "networkcontributor_optional" {
  for_each             = toset(var.identities)
  scope                = var.subnet_id
  role_definition_name = "Network Contributor"
  principal_id         = each.value
}
