variable "config" {
  description = "Resolved client config from scripts/config.py. Only the fields this stack uses are declared; extra fields are ignored."
  type = object({
    client_id   = string
    environment = string
    account_id  = string
    region      = string
    vpc_cidr    = string
    tags        = optional(map(string), {})

    network = object({
      az_count         = number
      exclude_zone_ids = optional(list(string), [])
    })
  })
}
