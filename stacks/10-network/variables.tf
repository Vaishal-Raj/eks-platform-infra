variable "config" {
  description = "Resolved config from scripts/config.py. Only the fields this stack uses are declared; any others are ignored."
  type = object({
    client_id        = string
    environment      = string
    profile          = string
    account_id       = string
    region           = string
    vpc_cidr         = string
    exclude_zone_ids = optional(list(string), [])
    tags             = optional(map(string), {})

    network = object({
      az_count = number
    })

    endpoints = object({
      enabled            = bool
      interface_services = list(string)
      enable_s3_gateway  = bool
    })
  })
}

# - One typed variable instead of about ten separate ones. The shape mirrors your JSON exactly, so it's easy to see which config value goes where.
# - Extra fields are ignored. When you later add an rds section to the profiles, this stack won't complain; Terraform simply drops attributes that aren't declared in the type.
# - optional(…, default) matches the client schema, where exclude_zone_ids and tags are optional.
# - Terraform still checks types. If az_count somehow arrived as "two", plan would fail before touching AWS.