# Terraform manages the zone contents. Delegating the nameservers to
# ns1/ns2/ns3.digitalocean.com at your registrar is a manual one-off.

locals {
  # "@" is the apex. One cluster means one load balancer, so every name
  # resolves to the same address.
  dns_records = var.manage_dns ? [
    "@",        # kmdndd.name.ng            production frontend
    "api",      # api.kmdndd.name.ng        production API
    "dev",      # dev.kmdndd.name.ng        dev frontend
    "api.dev",  # api.dev.kmdndd.name.ng    dev API
    "demo",     # demo.kmdndd.name.ng       demo frontend
    "api.demo", # api.demo.kmdndd.name.ng   demo API
  ] : []
}

resource "digitalocean_domain" "main" {
  count = var.manage_dns ? 1 : 0
  name  = var.domain
}

resource "digitalocean_record" "app" {
  for_each = toset(local.dns_records)

  domain = digitalocean_domain.main[0].name
  type   = "A"
  name   = each.value
  value  = local.ingress_ip
  ttl    = 300
}
