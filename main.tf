locals {
  azurerm_subnets = {
    for index, subnet in azurerm_subnet.subnet :
    subnet.name => subnet.id
  }
  vnet_name           = var.vnet_name != null ? var.vnet_name : "${var.resource_group_name}-vnet"
  location            = var.location != null && var.create_resource_group == true ? var.location : data.azurerm_resource_group.vnet[0].location
  resource_group_name = var.create_resource_group == true ? azurerm_resource_group.rg[0].name : data.azurerm_resource_group.vnet[0].name
}

data "azurerm_resource_group" "vnet" {
  count = var.create_resource_group != true ? 1 : 0
  name  = var.resource_group_name
}

resource "azurerm_resource_group" "rg" {
  count    = var.create_resource_group == true ? 1 : 0
  location = var.location
  name     = var.resource_group_name
}

resource "azurerm_virtual_network" "vnet" {
  name                = local.vnet_name
  resource_group_name = local.resource_group_name
  location            = local.location
  address_space       = length(var.address_space) > 0 ? var.address_space : null
  dns_servers         = var.dns_servers
  tags                = var.tags

  dynamic "ip_address_pool" {
    for_each = var.ipam_pool_v4_id != null && length(var.address_space) == 0 ? [var.number_of_ipv4_addresses] : []
    content {
      id                     = var.ipam_pool_v4_id
      number_of_ip_addresses = ip_address_pool.value
    }
  }

  dynamic "ip_address_pool" {
    for_each = var.ipam_pool_v6_id != null && length(var.address_space) == 0 ? [var.number_of_ipv6_addresses] : []
    content {
      id                     = var.ipam_pool_v6_id
      number_of_ip_addresses = ip_address_pool.value
    }
  }
}

resource "azurerm_subnet" "subnet" {
  for_each                          = var.subnets
  name                              = each.key
  resource_group_name               = local.resource_group_name
  virtual_network_name              = azurerm_virtual_network.vnet.name
  address_prefixes                  = length(var.address_space) > 0 ? each.value["address_prefixes"] : null
  service_endpoints                 = each.value["service_endpoints"]
  private_endpoint_network_policies = "Enabled"
  default_outbound_access_enabled   = each.value["default_outbound_access_enabled"]

  dynamic "ip_address_pool" {
    for_each = var.ipam_pool_v4_id != null && length(var.address_space) == 0 ? [each.value["number_of_ipv4_addresses"]] : []
    content {
      id                     = var.ipam_pool_v4_id
      number_of_ip_addresses = ip_address_pool.value
    }
  }

  dynamic "ip_address_pool" {
    for_each = var.ipam_pool_v6_id != null && length(var.address_space) == 0 ? [each.value["number_of_ipv6_addresses"]] : []
    content {
      id                     = var.ipam_pool_v6_id
      number_of_ip_addresses = ip_address_pool.value
    }
  }

  dynamic "delegation" {
    for_each = each.value["delegation"] == null ? {} : each.value["delegation"]
    content {
      name = delegation.key
      service_delegation {
        name    = delegation.value["name"]
        actions = delegation.value["actions"]
      }
    }
  }
}

locals {
  nsgs = {
    for key, subnet in var.subnets : key => subnet
    if subnet.create_nsg == true
  }
  subnets_map = {
    for key, subnet in azurerm_subnet.subnet : key => try(subnet.ip_address_pool[0].allocated_ip_address_prefixes[0], try(subnet.address_prefixes[0], ""))
  }
}

module "nsgs" {
  # source                    = "miljodir/nsg/azurerm"
  # version                   = "~> 1.0"
  source = "git@github.com:miljodir/terraform-azurerm-nsg?ref=ipam-subnet-nsg-logic"
  for_each                  = local.nsgs
  resource_group_name       = local.resource_group_name
  security_group_name       = coalesce(each.value.network_security_group_name, lower("${local.vnet_name}-${each.key}-nsg"))
  disable_microsegmentation = var.disable_microsegmentation
  custom_rules              = length(each.value["custom_rules"]) > 0 ? each.value["custom_rules"] : []
  location                  = local.location
  subnets                   = local.subnets_map

  depends_on = [azurerm_subnet.subnet]
}

resource "azurerm_subnet_network_security_group_association" "nsg_assoc" {
  for_each                  = local.nsgs
  subnet_id                 = azurerm_subnet.subnet[each.key].id
  network_security_group_id = module.nsgs[each.key].network_security_group_id
}

resource "azurerm_subnet_route_table_association" "vnet" {
  for_each       = var.route_tables_ids
  route_table_id = each.value
  subnet_id      = local.azurerm_subnets[each.key]
}
