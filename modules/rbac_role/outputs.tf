output "assigned_identity_ids" {
  value = keys(azurerm_role_assignment.networkcontributor_optional)
}
