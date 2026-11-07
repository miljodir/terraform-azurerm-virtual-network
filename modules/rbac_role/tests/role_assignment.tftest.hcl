mock_provider "azurerm" {}

variables {
  subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet-test/subnets/snet-test"
  identities = [
    "00000000-0000-0000-0000-000000000001",
    "00000000-0000-0000-0000-000000000002",
  ]
}

run "creates_role_assignments_for_each_identity" {
  command = plan

  assert {
    condition     = toset(keys(azurerm_role_assignment.networkcontributor_optional)) == toset(var.identities)
    error_message = "A role assignment should be created for every configured identity."
  }

  assert {
    condition = alltrue([
      for identity, assignment in azurerm_role_assignment.networkcontributor_optional :
      assignment.scope == var.subnet_id &&
      assignment.principal_id == identity &&
      assignment.role_definition_name == "Network Contributor"
    ])
    error_message = "Each role assignment should use the subnet scope, configured identity, and Network Contributor role."
  }
}
