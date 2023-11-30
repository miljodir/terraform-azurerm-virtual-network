# Azurerm Virtual Network

Creates a virtual network with optionally one or more subnets.
By default a NSG will be created and associated with the subnet(s). The NSG will create restrictive rules by default. To override this, set the `disable_microsegmentation = true`.