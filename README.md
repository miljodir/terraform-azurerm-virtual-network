# Azurerm Virtual Network

[![Changelog](https://img.shields.io/badge/changelog-release-green.svg)](https://github.com/miljodir/terraform-azurerm-virtual-network/wiki/main#changelog)
[![TF Registry](https://img.shields.io/badge/terraform-registry-blue.svg)](https://registry.terraform.io/modules/miljodir/virtual-network/azurerm/)

Creates a virtual network with optionally one or more subnets.
By default a NSG will be created and associated with the subnet(s). The NSG will create restrictive rules by default. To override this, set the `disable_microsegmentation = true`.
