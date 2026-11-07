# Azurerm Virtual Network

[![Changelog](https://img.shields.io/badge/changelog-release-green.svg)](https://github.com/miljodir/terraform-azurerm-virtual-network/wiki/main#changelog)
[![TF Registry](https://img.shields.io/badge/terraform-registry-blue.svg)](https://registry.terraform.io/modules/miljodir/virtual-network/azurerm/)

Creates a virtual network with optionally one or more subnets.
By default a NSG will be created and associated with the subnet(s). The NSG will create restrictive rules by default. To override this, set the `disable_microsegmentation = true`.

## Opt-in infrastructure inbound rules

Each subnet with `create_nsg = true` and `disable_microsegmentation = false` defaults to denying inbound traffic unless explicitly allowed. `DenyAllInbound` remains in place; the GatewayManager and AzureLoadBalancer inbound allows are no longer enabled for every subnet.

| Subnet option | Default | Use case |
| --- | --- | --- |
| `allow_application_gateway_infrastructure_inbound` | `false` | A subnet hosting conventional Azure Application Gateway v2. Allows GatewayManager TCP ports 65200-65535 and AzureLoadBalancer health probes. This flag alone is sufficient for those infrastructure rules; the load balancer flag is not also required. |
| `allow_azure_load_balancer_inbound` | `false` | A subnet behind an Azure Load Balancer, or hosting a network-isolated private Application Gateway v2, that needs AzureLoadBalancer health probes without GatewayManager access. |

These flags apply only to module-managed NSGs. GatewayManager traffic is for the Application Gateway's infrastructure, not application traffic to backend subnets. A backend subnet reachable from Application Gateway needs narrowly scoped `custom_rules` for the gateway subnet and backend listener ports instead. Client/listener traffic into an Application Gateway subnet also requires appropriate `custom_rules`; the infrastructure flag does not allow it.

With `disable_microsegmentation = true`, neither the module default `DenyAllInbound` nor either opt-in infrastructure rule is created, even if a flag is true; `custom_rules` remain. Existing WAF and AKS deployments using this setting therefore continue to rely on their custom rules and Azure's built-in NSG defaults.

[Network-isolated private Application Gateway v2](https://learn.microsoft.com/en-us/azure/application-gateway/application-gateway-private-deployment#network-security-group-control) does not need a GatewayManager inbound allow, but still requires AzureLoadBalancer probe access. Use the load balancer flag only, or retain sufficient existing narrower custom probe rules; do not enable broader infrastructure allows when those rules already satisfy the deployment's requirements.

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

## Migration warning: minor release, changed defaults

This update is classified as a **minor release**, but changes inbound defaults and requires consumer review before applying. It requires `miljodir/nsg/azurerm ~> 1.4`, excluding older versions that lack the new inputs. The NSG module 1.4.0 release must be published before dependency resolution and Terraform validation can succeed.

**The VNet upgrade is not required for these rule removals to affect consumers.** Released VNet versions 1.4.1 and 2.0.1 depend on NSG `~> 1.0`, which also permits NSG 1.4. A fresh module installation or dependency upgrade can therefore select the changed NSG defaults while retaining an older VNet version, including consumers pinned to VNet `~> 1.0`. Those VNet versions do not expose the new flags. Audit these consumers before the NSG release: upgrade to a VNet version exposing the opt-ins when appropriate, or retain sufficient custom rules.

When `disable_microsegmentation = false`, upgrading removes the previously unconditional GatewayManager and AzureLoadBalancer inbound allows. Before applying, enable `allow_application_gateway_infrastructure_inbound` on conventional Application Gateway v2 subnets that need both infrastructure rules. For network-isolated private Application Gateway v2 or other load-balanced subnets, enable `allow_azure_load_balancer_inbound` only if sufficient narrower custom probe rules are not already present. Leaving both flags unset keeps both module infrastructure allows disabled. Existing custom rules are retained; the module default `DenyAllInbound` remains only when microsegmentation is enabled.

**Migrating custom rules to module defaults requires reviewing both denies and allows.** A custom `DenyAllInbound` at priority 4049 takes precedence over the module's infrastructure allows at 4050/4095. Merely enabling microsegmentation and the opt-ins while retaining that custom deny will not permit the intended infrastructure traffic. The custom deny's Azure rule name also conflicts with the module's `DenyAllInbound`; custom allows sharing names with module rules likewise conflict. Migrate the custom deny and any overlapping custom allows together before enabling module defaults, preserving the intended deny-all posture and any narrower access requirements. This is migration guidance only: module priorities and rule behavior are unchanged.
