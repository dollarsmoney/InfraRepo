variable "cluster_name" {
  description = "Name of the DOKS cluster"
  type        = string
  default     = "marketplace"
}

variable "region" {
  description = "DigitalOcean region slug (e.g. lon1, fra1, nyc3)"
  type        = string
  default     = "lon1"
}

variable "kubernetes_version_prefix" {
  description = "Match the newest patch release of this minor version"
  type        = string
  default     = "1.34."
}

variable "node_size" {
  description = "Droplet size for worker nodes"
  type        = string
  default     = "s-2vcpu-4gb"
}

variable "node_count" {
  description = "Starting node count"
  type        = number
  default     = 2
}

variable "node_min" {
  description = "Autoscaler minimum"
  type        = number
  default     = 2
}

variable "node_max" {
  description = "Autoscaler maximum"
  type        = number
  default     = 4
}

variable "environments" {
  description = "Namespaces to create, each with its own scoped deploy credential"
  type        = list(string)
  default     = ["dev", "demo", "production"]
}

variable "domain" {
  description = "Registered domain. Its nameservers must be delegated to DigitalOcean."
  type        = string
  default     = "kmdndd.name.ng"
}

variable "manage_dns" {
  description = "Create the DigitalOcean DNS zone and records. Turn off if DNS stays at your registrar."
  type        = bool
  default     = true
}

variable "acme_email" {
  description = "Let's Encrypt account contact for expiry notices"
  type        = string
  default     = "itojedollars3@gmail.com"
}
