# Azurerm Virtual Network

[![Changelog](https://img.shields.io/badge/changelog-release-green.svg)](https://github.com/miljodir/terraform-azurerm-virtual-network/wiki/main#changelog)
[![TF Registry](https://img.shields.io/badge/terraform-registry-blue.svg)](https://registry.terraform.io/modules/miljodir/virtual-network/azurerm/)

Creates a virtual network with optionally one or more subnets.
By default a NSG will be created and associated with the subnet(s). The NSG will create restrictive rules by default. To override this, set the `disable_microsegmentation = true`.

## Opt-in infrastructure inbound rules

Each subnet with `create_nsg = true` defaults to denying inbound traffic unless explicitly allowed. `DenyAllInbound` remains in place; the GatewayManager and AzureLoadBalancer inbound allows are no longer enabled for every subnet.

| Subnet option | Default | Use case |
| --- | --- | --- |
| `allow_application_gateway_infrastructure_inbound` | `false` | A subnet hosting Azure Application Gateway v2. Allows GatewayManager TCP ports 65200-65535 and AzureLoadBalancer health probes. This flag alone is sufficient; the load balancer flag is not also required. |
| `allow_azure_load_balancer_inbound` | `false` | A subnet behind an Azure Load Balancer that needs AzureLoadBalancer health probes, without GatewayManager access. |

These flags apply only to module-managed NSGs. GatewayManager traffic is for the Application Gateway's infrastructure, not application traffic to backend subnets. A backend subnet reachable from Application Gateway needs narrowly scoped `custom_rules` for the gateway subnet and backend listener ports instead. Client/listener traffic into an Application Gateway subnet also requires appropriate `custom_rules`; the infrastructure flag does not allow it.

```hcl
subnets = {
  application-gateway = {
    address_prefixes                                = ["10.0.0.0/24"]
    allow_application_gateway_infrastructure_inbound = true
  }
  load-balanced-backends = {
    address_prefixes                 = ["10.0.1.0/24"]
    allow_azure_load_balancer_inbound = true
  }
  private-workloads = {
    address_prefixes = ["10.0.2.0/24"]
  }
}
```

## Breaking upgrade: NSG module 2.x

This version requires `miljodir/nsg/azurerm ~> 2.0` and depends on the NSG module 2.0 release. Upgrading removes the previously unconditional GatewayManager and AzureLoadBalancer inbound allows. Before applying the upgrade, set `allow_application_gateway_infrastructure_inbound = true` on subnets hosting Application Gateway v2, and set `allow_azure_load_balancer_inbound = true` on other subnets behind an Azure Load Balancer that require health probes. Leaving both flags unset keeps both infrastructure allows disabled. Existing custom rules and the default `DenyAllInbound` behavior are retained.
