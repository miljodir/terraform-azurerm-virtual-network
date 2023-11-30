output "vnet" {
  description = "All outputs from the virtual network resource"
  value       = azurerm_virtual_network.vnet
}

output "rg" {
  description = "All available outputs from the resource group resource"
  value = {
    id       = var.create_resource_group == true ? azurerm_resource_group.rg[0].id : null
    name     = local.resource_group_name
    location = local.location
  }
}

output "subnets" {
  description = "All outputs from the created subnets"
  value       = azurerm_subnet.subnet
}

output "nsgs" {
  description = "All nsgs created by this module"
  value = {
    for k in module.nsgs : k.network_security_group_name => k
  }
}

output "nsg_association_ids" {
  description = "The ids of all NSG associations"
  value       = azurerm_subnet_network_security_group_association.nsg_assoc
}
