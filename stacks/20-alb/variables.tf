variable "config" {
  description = "Resolved config from scripts/config.py. Only the fields this stack uses are declared."
  type = object({
    client_id   = string
    environment = string
    profile     = string
    account_id  = string
    region      = string
    tags        = optional(map(string), {})

    alb = object({
      target_port         = number
      deletion_protection = bool
    })
  })
}