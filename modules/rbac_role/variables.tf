variable "identities" {
  type        = list(string)
  description = "A list of identities to assign to the network contributor role on the subnet"
}

variable "subnet_id" {
  type        = string
  description = "The subnet id to assign the network contributor role to"
}
