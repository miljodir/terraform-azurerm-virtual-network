variable "vnet_name" {
  description = "Name of the vnet to create"
  type        = string
  default     = null
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
}

variable "create_resource_group" {
  type        = bool
  description = "Create resource group for network resources automatically? Defaults to false."
  default     = false
}

variable "address_space" {
  type        = list(string)
  description = "The address space that is used by the virtual network. This value must be provided"
  default     = []
}

variable "ipam_pool_v4_id" {
  description = "The ID of the Azure Network Manager IPv4 IPAM pool to associate with the virtual network."
  type        = string
  default     = null
}

variable "ipam_pool_v6_id" {
  description = "The ID of the Azure Network Manager IPv6 IPAM pool to associate with the virtual network."
  type        = string
  default     = null
}

variable "address_range_ipv4_cidr" {
  description = "The CIDR block to use for the address range of the virtual network."
  type        = list(string)
  default     = []
}

variable "address_range_ipv6_cidr" {
  description = "The CIDR block to use for the address range of the virtual network."
  type        = list(string)
  default     = []
}

# If no values specified, this defaults to Azure DNS 
variable "dns_servers" {
  description = "The DNS servers to be used with vNet."
  type        = list(string)
  default     = ["172.26.1.4"] # defaults to Azure Firewall
}

variable "subnets" {
  description = "A map of subnets that should be created"
  type = map(object({
    address_prefixes                = list(string)
    service_endpoints               = optional(list(string))
    default_outbound_access_enabled = optional(bool, false)
    identity_delegations            = optional(list(string), [""])
    delegation = optional(map(object({
      name    = string
      actions = optional(list(string))
    })))
    create_nsg                  = optional(bool, true)
    network_security_group_name = optional(string, null)
    custom_rules = optional(list(object({
      name                                       = optional(string, "custom_rule_name")
      description                                = optional(string)
      priority                                   = number
      direction                                  = optional(string, "Any")
      access                                     = optional(string, "Deny")
      protocol                                   = optional(string, "*")
      source_port_range                          = optional(any)
      destination_port_range                     = optional(string, null)
      destination_port_ranges                    = optional(list(string), null)
      source_address_prefix                      = optional(string, null)
      source_address_prefixes                    = optional(list(string), null)
      destination_address_prefix                 = optional(string, null)
      destination_address_prefixes               = optional(list(string), null)
      source_application_security_group_ids      = optional(list(string), null)
      destination_application_security_group_ids = optional(list(string), null)
    })), [])
  }))
  default = {}
}

variable "route_tables_ids" {
  description = "A map of subnet name to Route table ids"
  type        = map(string)
  default     = {}
}

variable "tags" {
  description = "The tags to associate with your network and subnets."
  type        = map(string)

  default = null
}

variable "location" {
  description = "The location for virtual network resource. Defaults to resource group location if existing. If you want to create a resource group you must provide a location."
  type        = string
  default     = null
}

variable "disable_microsegmentation" {
  type        = bool
  default     = false
  description = "Disable microsegmentation between subnets? Should only be used if necessary. Defaults to false."
}

variable "nsg_use_for_each" {
  type        = bool
  default     = true
  description = "Obsolete variable, left in place for backwards compatibility."
}
