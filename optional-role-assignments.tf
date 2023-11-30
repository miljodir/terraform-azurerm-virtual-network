### Optional role assignments to subnets ###
locals {
  rbac_map = {
    for key, sub in var.subnets :
    key => sub
    if sub.identity_delegations[0] != ""
  }
}

module "group_member" {
  source   = "./modules/rbac_role"
  for_each = local.rbac_map

  subnet_id  = azurerm_subnet.subnet[each.key].id
  identities = each.value["identity_delegations"]

  depends_on = [azurerm_subnet.subnet]
}
