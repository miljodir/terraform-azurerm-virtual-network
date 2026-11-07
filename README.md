# Azurerm Virtual Network

[![Changelog](https://img.shields.io/badge/changelog-release-green.svg)](https://github.com/miljodir/terraform-azurerm-virtual-network/wiki/main#changelog)
[![TF Registry](https://img.shields.io/badge/terraform-registry-blue.svg)](https://registry.terraform.io/modules/miljodir/virtual-network/azurerm/)

Creates a virtual network with optionally one or more subnets.
By default a NSG will be created and associated with the subnet(s). The NSG will create restrictive rules by default. To override this, set the `disable_microsegmentation = true`.

## Name-based load balancer inbound default

For each subnet with `create_nsg = true` and `disable_microsegmentation = false`, `DenyAllInbound` remains at priority 4096. The module never creates a GatewayManager rule; there is no Application Gateway infrastructure flag.

The per-subnet `allow_azure_load_balancer_inbound` option is nullable:

| Value | AzureLoadBalancer inbound rule at priority 4095 |
| --- | --- |
| Omitted or `null` | Enabled if the effective NSG name starts with lowercase `p`; disabled otherwise. Matching is case-sensitive (`P` in a custom NSG name does not match). |
| `true` | Enabled regardless of NSG name. |
| `false` | Disabled regardless of NSG name. |

The VNet module passes the nullable option unchanged to the NSG module. The effective NSG name is `network_security_group_name` when supplied, otherwise `lower("${local.vnet_name}-${subnet_name}-nsg")`. The effective VNet name is `vnet_name`, or `${resource_group_name}-vnet` when omitted/null. Generated NSG names are lowercased, so production VNet names beginning with `p` infer enabled by default; custom NSG names control inference instead when supplied. Direct NSG consumers use the same NSG-name inference.

```hcl
vnet_name = "p-workloads"
subnets = {
  production-default = {
    address_prefixes = ["10.0.0.0/24"]
  }
  production-null = {
    address_prefixes                 = ["10.0.1.0/24"]
    allow_azure_load_balancer_inbound = null
  }
  private-workloads = {
    address_prefixes                 = ["10.0.2.0/24"]
    allow_azure_load_balancer_inbound = false
  }
  custom-nsg-default = {
    address_prefixes            = ["10.0.3.0/24"]
    network_security_group_name = "custom-nsg"
    # Omitted: disabled because this custom NSG name does not start with p.
  }
}
```

For a non-production VNet, opt in explicitly when probes are needed:

```hcl
vnet_name = "d-workloads"
subnets = {
  load-balanced-backends = {
    address_prefixes                 = ["10.1.0.0/24"]
    allow_azure_load_balancer_inbound = true
  }
}
```

With `disable_microsegmentation = true`, neither the module default `DenyAllInbound` nor the load balancer rule is created, even if the override is true; `custom_rules` remain. Existing WAF and AKS deployments using this setting continue to rely on custom rules and Azure's built-in NSG defaults.

## Custom rule source ports

For each subnet's `custom_rules`, omitted or explicitly null `source_port_range`
defaults to `"*"` (any source port). Explicit values are passed unchanged to the
NSG module: use `"1024-2048"` for a range or `"1024, 2048-4096"` for multiple
ports/ranges. The NSG module converts non-wildcard values into
`source_port_ranges`, splitting comma-separated strings and trimming whitespace.
This default does not change `destination_port_range`, `destination_port_ranges`,
or plural address-prefix lists.

## Application Gateway custom rules

Conventional Application Gateway v2 deployments that require GatewayManager TCP ports 65200-65535 must retain or add appropriate `custom_rules`; the module no longer supplies this rule. GatewayManager is infrastructure traffic to the gateway subnet, not application traffic to backend subnets. Backend traffic needs narrowly scoped custom allows from the gateway subnet to backend ports; client/listener traffic also needs appropriate custom rules.

[Network-isolated private Application Gateway v2](https://learn.microsoft.com/en-us/azure/application-gateway/application-gateway-private-deployment#network-security-group-control) does not need GatewayManager access, but still requires AzureLoadBalancer probe access. Use the name-based default or explicit load balancer override, or retain sufficient narrower custom probe rules. An explicit `false` prevents the broader module probe allow when narrower custom rules suffice.

## Migration warning: minor release, changed defaults

This update is classified as a **minor release**, but changes inbound defaults and requires consumer review before applying. It requires `miljodir/nsg/azurerm ~> 1.4`, excluding older versions that lack the new inputs. The NSG module 1.4.0 release must be published before dependency resolution and Terraform validation can succeed.

**The VNet upgrade is not required for these changes to affect consumers.** Released VNet versions 1.4.1 and 2.0.1 depend on NSG `~> 1.0`, which also permits NSG 1.4. A fresh module installation or dependency upgrade can therefore select the changed NSG defaults while retaining an older VNet version, including consumers pinned to VNet `~> 1.0`. Those versions do not expose the load balancer override and rely on the NSG module's effective-NSG-name inference. Audit these consumers before the NSG release: upgrade to a VNet version exposing the override when appropriate, or retain sufficient custom rules.

When `disable_microsegmentation = false`, the NSG update removes the previously unconditional GatewayManager allow and changes the previously unconditional AzureLoadBalancer allow to a name-based default with explicit overrides. Review required Application Gateway custom rules and probe access before applying. Set the load balancer override to `false` on `p`-prefixed NSGs when no broad probe allow is needed, or `true` on other NSGs when it is needed; review custom NSG names as well as VNet names. Existing custom rules are retained; the module default `DenyAllInbound` remains only when microsegmentation is enabled.

**Migrating custom rules to module defaults requires reviewing both denies and allows.** A custom `DenyAllInbound` at priority 4049 takes precedence over the module's load balancer allow at 4095. Merely enabling microsegmentation and the load balancer rule while retaining that custom deny will not permit probe traffic. The custom deny's Azure rule name also conflicts with the module's `DenyAllInbound`; custom load balancer allows sharing the module rule's name likewise conflict. Migrate the custom deny and any overlapping load balancer allows together before enabling module defaults, preserving the intended deny-all posture and narrower access requirements. Keep required GatewayManager custom rules: there is no module equivalent. The module's load balancer priority 4095 and deny priority 4096 are unchanged.
