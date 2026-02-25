data "cloudflare_zone" "undois" {
  name = local.domain_name
}



resource "cloudflare_record" "www_cname" {
  zone_id = data.cloudflare_zone.undois.id
  name    = "www"
  content = azurerm_storage_account.static_site.primary_web_host
  type    = "CNAME"
  proxied = true
}

# Best Practices Zone Settings
resource "cloudflare_zone_settings_override" "undois_settings" {
  zone_id = data.cloudflare_zone.undois.id

  settings {
    always_use_https         = "on"
    automatic_https_rewrites = "on"
    brotli                   = "on"
    security_level           = "medium"
    ssl                      = "full"
  }
}

# Redirect root domain to www
resource "cloudflare_page_rule" "root_to_www" {
  zone_id = data.cloudflare_zone.undois.id
  target  = "${local.domain_name}/*"
  status  = "active"

  actions {
    forwarding_url {
      url         = "https://www.undo.is/$1"
      status_code = 301
    }
  }
}

# asverify record to allow Azure to natively validate the custom domain for the Storage Account
resource "cloudflare_record" "asverify" {
  zone_id = data.cloudflare_zone.undois.id
  name    = "asverify.www"
  content = "asverify.undoissite.z20.web.core.windows.net"
  type    = "CNAME"
  proxied = false
}
