mock_provider "azurerm" {
  mock_data "azurerm_resource_group" {
    defaults = {
      location = "westeurope"
    }
  }

  # Generated mock IDs are random strings; resources that parse IDs need a real-looking one.
  mock_resource "azurerm_subnet" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/rg-test-vnet/subnets/snet"
    }
  }

  mock_resource "azurerm_network_security_group" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/networkSecurityGroups/nsg"
    }
  }
}

variables {
  resource_group_name = "rg-test"
  address_space       = ["10.10.0.0/16"]
}

run "existing_resource_group" {
  command = plan

  override_data {
    target = data.azurerm_resource_group.vnet[0]
    values = {
      location = "westeurope"
    }
  }

  assert {
    condition     = length(azurerm_resource_group.rg) == 0
    error_message = "No resource group should be created by default."
  }

  assert {
    condition     = azurerm_virtual_network.vnet.name == "rg-test-vnet"
    error_message = "VNet name should default to '<resource group>-vnet'."
  }

  assert {
    condition     = azurerm_virtual_network.vnet.location == "westeurope"
    error_message = "Location should come from the existing resource group."
  }

  assert {
    condition     = azurerm_virtual_network.vnet.address_space == toset(["10.10.0.0/16"])
    error_message = "Address space should be passed through."
  }

  assert {
    condition     = length(azurerm_virtual_network.vnet.ip_address_pool) == 0
    error_message = "IPAM pools should not be used with a static address space."
  }
}

run "create_resource_group" {
  command = plan

  variables {
    create_resource_group = true
    location              = "norwayeast"
    vnet_name             = "vnet-custom"
  }

  assert {
    condition     = azurerm_resource_group.rg[0].name == "rg-test" && azurerm_resource_group.rg[0].location == "norwayeast"
    error_message = "Resource group should be created with the given name and location."
  }

  assert {
    condition     = azurerm_virtual_network.vnet.name == "vnet-custom"
    error_message = "vnet_name should override the generated name."
  }

  assert {
    condition     = azurerm_virtual_network.vnet.location == "norwayeast"
    error_message = "VNet should use the given location."
  }
}

run "subnets_with_default_nsgs" {
  command = apply

  variables {
    subnets = {
      app = {
        address_prefixes  = ["10.10.1.0/24"]
        service_endpoints = ["Microsoft.Storage"]
      }
      data = {
        address_prefixes = ["10.10.2.0/24"]
        custom_rules = [
          {
            name                       = "AllowAppToData"
            priority                   = 200
            direction                  = "Inbound"
            access                     = "Allow"
            source_address_prefix      = "app"
            destination_address_prefix = "data"
            destination_port_range     = "1433"
          }
        ]
      }
    }
  }

  assert {
    condition     = toset(keys(azurerm_subnet.subnet)) == toset(["app", "data"])
    error_message = "All subnets should be created."
  }

  assert {
    condition     = azurerm_subnet.subnet["app"].address_prefixes == tolist(["10.10.1.0/24"])
    error_message = "Subnet address prefixes should be passed through."
  }

  assert {
    condition     = azurerm_subnet.subnet["app"].default_outbound_access_enabled == false
    error_message = "Default outbound access should be disabled by default."
  }

  assert {
    condition     = azurerm_subnet.subnet["app"].private_endpoint_network_policies == "Enabled"
    error_message = "Private endpoint network policies should be enabled."
  }

  assert {
    condition     = [for se in azurerm_subnet.subnet["app"].service_endpoint : se.service] == ["Microsoft.Storage"]
    error_message = "Service endpoints should be passed through."
  }

  assert {
    condition     = toset(keys(module.nsgs)) == toset(["app", "data"])
    error_message = "An NSG should be created for every subnet by default."
  }

  assert {
    condition     = module.nsgs["app"].network_security_group_name == "rg-test-vnet-app-nsg"
    error_message = "NSG name should default to '<vnet>-<subnet>-nsg'."
  }

  assert {
    condition     = toset(keys(azurerm_subnet_network_security_group_association.nsg_assoc)) == toset(["app", "data"])
    error_message = "Each NSG should be associated with its subnet."
  }

  assert {
    condition     = length(module.group_member) == 0
    error_message = "No role assignments should be created without identity_delegations."
  }
}

run "custom_rule_source_port_defaults_and_explicit_values" {
  command = apply

  variables {
    subnets = {
      app = {
        address_prefixes = ["192.0.2.0/24"]
        custom_rules = [
          {
            name                       = "OmittedSourcePort"
            priority                   = 200
            direction                  = "Inbound"
            source_address_prefix      = "*"
            destination_address_prefix = "*"
            destination_port_range     = "443"
          },
          {
            name                       = "NullSourcePort"
            priority                   = 201
            direction                  = "Inbound"
            source_port_range          = null
            source_address_prefix      = "*"
            destination_address_prefix = "*"
            destination_port_range     = "443"
          },
          {
            name                       = "WildcardSourcePort"
            priority                   = 202
            direction                  = "Inbound"
            source_port_range          = "*"
            source_address_prefix      = "*"
            destination_address_prefix = "*"
            destination_port_range     = "443"
          },
          {
            name                       = "SingleSourcePort"
            priority                   = 203
            direction                  = "Inbound"
            source_port_range          = "1024-2048"
            source_address_prefix      = "*"
            destination_address_prefix = "*"
            destination_port_range     = "443"
          },
          {
            name                         = "MultipleSourcePorts"
            priority                     = 204
            direction                    = "Inbound"
            source_port_range            = "1024, 2048-4096"
            source_address_prefixes      = ["192.0.2.0/25", "192.0.2.128/25"]
            destination_address_prefixes = ["198.51.100.0/24"]
            destination_port_ranges      = ["80", "443"]
          }
        ]
      }
    }
  }

  assert {
    condition     = alltrue([for rule in slice(var.subnets["app"].custom_rules, 0, 3) : rule.source_port_range == "*"])
    error_message = "Omitted, null and explicit wildcard source ports must all use '*'."
  }

  assert {
    condition     = var.subnets["app"].custom_rules[3].source_port_range == "1024-2048" && var.subnets["app"].custom_rules[4].source_port_range == "1024, 2048-4096"
    error_message = "Explicit source port ranges and comma-separated ports must remain unchanged."
  }

  assert {
    condition     = var.subnets["app"].custom_rules[4].destination_port_range == null && tolist(var.subnets["app"].custom_rules[4].destination_port_ranges) == tolist(["80", "443"])
    error_message = "Plural destination ports must remain unchanged without adding a singular destination port."
  }

  assert {
    condition     = tolist(var.subnets["app"].custom_rules[4].source_address_prefixes) == tolist(["192.0.2.0/25", "192.0.2.128/25"]) && tolist(var.subnets["app"].custom_rules[4].destination_address_prefixes) == tolist(["198.51.100.0/24"])
    error_message = "Plural address prefixes must remain unchanged."
  }

  assert {
    condition     = module.nsgs["app"].network_security_group_name == "rg-test-vnet-app-nsg"
    error_message = "Custom rules must apply through the real registry NSG module with only Azure mocked."
  }
}

run "nsg_can_be_skipped_and_named" {
  command = apply

  variables {
    subnets = {
      nonsg = {
        address_prefixes = ["10.10.3.0/24"]
        create_nsg       = false
      }
      named = {
        address_prefixes            = ["10.10.4.0/24"]
        network_security_group_name = "nsg-explicit"
      }
    }
  }

  assert {
    condition     = tolist(keys(module.nsgs)) == tolist(["named"])
    error_message = "No NSG should be created when create_nsg = false."
  }

  assert {
    condition     = module.nsgs["named"].network_security_group_name == "nsg-explicit"
    error_message = "network_security_group_name should override the generated NSG name."
  }
}

run "delegation_and_role_assignments" {
  command = apply

  variables {
    subnets = {
      delegated = {
        address_prefixes     = ["10.10.5.0/24"]
        identity_delegations = ["00000000-0000-0000-0000-000000000001"]
        delegation = {
          containers = {
            name    = "Microsoft.ContainerInstance/containerGroups"
            actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
          }
        }
      }
    }
  }

  assert {
    condition     = azurerm_subnet.subnet["delegated"].delegation[0].service_delegation[0].name == "Microsoft.ContainerInstance/containerGroups"
    error_message = "Subnet delegation should be configured."
  }

  assert {
    condition     = tolist(keys(local.rbac_map)) == tolist(["delegated"])
    error_message = "Only subnets with configured identities should receive role assignments."
  }
}

run "route_table_association" {
  command = apply

  variables {
    subnets = {
      app = {
        address_prefixes = ["10.10.1.0/24"]
      }
    }
    route_tables_ids = {
      app = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/routeTables/rt-test"
    }
  }

  assert {
    condition     = azurerm_subnet_route_table_association.vnet["app"].subnet_id == azurerm_subnet.subnet["app"].id
    error_message = "Route table should be associated with the named subnet."
  }
}

run "ipam_pools" {
  command = plan

  variables {
    address_space   = []
    ipam_pool_v4_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-ipam/providers/Microsoft.Network/networkManagers/nm-test/ipamPools/pool-v4"
    subnets = {
      app = {}
    }
  }

  assert {
    condition     = azurerm_virtual_network.vnet.ip_address_pool[0].number_of_ip_addresses == "256"
    error_message = "VNet should request 256 IPv4 addresses from the IPAM pool by default."
  }

  assert {
    condition     = azurerm_subnet.subnet["app"].ip_address_pool[0].number_of_ip_addresses == "32"
    error_message = "Subnets should request 32 IPv4 addresses from the IPAM pool by default."
  }

  assert {
    condition     = azurerm_subnet.subnet["app"].address_prefixes == null
    error_message = "Static address prefixes should not be used with IPAM pools."
  }
}
