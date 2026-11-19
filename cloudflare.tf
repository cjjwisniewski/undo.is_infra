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
    email_obfuscation        = "off"
    rocket_loader            = "off"
    security_level           = "medium"
    ssl                      = "full"

    security_header {
      enabled            = true
      max_age            = 31536000
      include_subdomains = true
      nosniff            = true
    }
  }
}

# Edge Security Headers for www.undo.is
resource "cloudflare_ruleset" "security_headers" {
  zone_id     = data.cloudflare_zone.undois.id
  name        = "undo.is Security Headers"
  description = "Add CSP, HSTS, and security response headers for www.undo.is"
  kind        = "zone"
  phase       = "http_response_headers_transform"

  rules {
    action      = "rewrite"
    expression  = "(http.host eq \"www.${local.domain_name}\")"
    description = "Set security headers on www.undo.is"
    enabled     = true

    action_parameters {
      headers {
        name      = "Content-Security-Policy"
        operation = "set"
        # 'unsafe-inline' allows SvelteKit static adapter's inline hydration script and scoped styles
        value = "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; font-src 'self' data:; img-src 'self' data:; connect-src 'self' https://status.${local.domain_name}; frame-ancestors 'none'; base-uri 'self'; object-src 'none'"
      }
      headers {
        name      = "Permissions-Policy"
        operation = "set"
        value     = "camera=(), microphone=(), geolocation=()"
      }
      headers {
        name      = "Referrer-Policy"
        operation = "set"
        value     = "strict-origin-when-cross-origin"
      }
      headers {
        name      = "Strict-Transport-Security"
        operation = "set"
        value     = "max-age=31536000; includeSubDomains"
      }
      headers {
        name      = "X-Content-Type-Options"
        operation = "set"
        value     = "nosniff"
      }
      headers {
        name      = "X-Frame-Options"
        operation = "set"
        value     = "DENY"
      }
    }
  }
}

# Redirect root domain to www (modern Redirect Ruleset replacing deprecated Page Rule)
resource "cloudflare_ruleset" "root_to_www" {
  zone_id     = data.cloudflare_zone.undois.id
  name        = "undo.is Root to WWW Redirect"
  description = "301 redirect apex undo.is to https://www.undo.is preserving path and query"
  kind        = "zone"
  phase       = "http_request_dynamic_redirect"

  rules {
    action      = "redirect"
    expression  = "(http.host eq \"${local.domain_name}\")"
    description = "Redirect apex to www"
    enabled     = true

    action_parameters {
      from_value {
        status_code           = 301
        preserve_query_string = true

        target_url {
          expression = "concat(\"https://www.${local.domain_name}\", http.request.uri.path)"
        }
      }
    }
  }
}

# Edge Cache Rules for static HTML & assets on www.undo.is
resource "cloudflare_ruleset" "cache_rules" {
  zone_id     = data.cloudflare_zone.undois.id
  name        = "undo.is Static Site Cache Rules"
  description = "Cache prerendered HTML at Cloudflare edge while bypassing API endpoints"
  kind        = "zone"
  phase       = "http_request_cache_settings"

  rules {
    action      = "set_cache_settings"
    expression  = "(http.host eq \"www.${local.domain_name}\" and not starts_with(http.request.uri.path, \"/api/\"))"
    description = "Cache static HTML and assets on www.undo.is respecting origin Cache-Control"
    enabled     = true

    action_parameters {
      cache = true

      edge_ttl {
        mode = "respect_origin"
      }

      browser_ttl {
        mode = "respect_origin"
      }
    }
  }
}

# DNS CAA records restricting certificate issuance to Cloudflare Universal SSL CAs
locals {
  caa_records = {
    letsencrypt_issue     = { tag = "issue", value = "letsencrypt.org" }
    letsencrypt_issuewild = { tag = "issuewild", value = "letsencrypt.org" }
    google_issue          = { tag = "issue", value = "pki.goog" }
    google_issuewild      = { tag = "issuewild", value = "pki.goog" }
    digicert_issue        = { tag = "issue", value = "digicert.com" }
    digicert_issuewild    = { tag = "issuewild", value = "digicert.com" }
    iodef                 = { tag = "iodef", value = "mailto:cameron@undo.is" }
  }
}

resource "cloudflare_record" "caa" {
  for_each = local.caa_records

  zone_id = data.cloudflare_zone.undois.id
  name    = "@"
  type    = "CAA"

  data {
    flags = "0"
    tag   = each.value.tag
    value = each.value.value
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

# --- Homelab Status API (Cloudflare Worker + KV) ---
resource "cloudflare_record" "status_cname" {
  zone_id = data.cloudflare_zone.undois.id
  name    = "status"
  content = azurerm_storage_account.static_site.primary_web_host
  type    = "CNAME"
  proxied = true
}

resource "cloudflare_workers_kv_namespace" "homelab_status" {
  account_id = data.cloudflare_zone.undois.account_id
  title      = "homelab_status"
}

resource "random_password" "status_heartbeat_token" {
  length  = 48
  special = false
}

resource "cloudflare_workers_script" "status_api" {
  account_id = data.cloudflare_zone.undois.account_id
  name       = "undois-status-api"
  content    = file("${path.module}/workers/status.js")
  module     = true

  kv_namespace_binding {
    name         = "STATUS_KV"
    namespace_id = cloudflare_workers_kv_namespace.homelab_status.id
  }

  secret_text_binding {
    name = "HEARTBEAT_TOKEN"
    text = random_password.status_heartbeat_token.result
  }
}

resource "cloudflare_workers_route" "www_status_api" {
  zone_id     = data.cloudflare_zone.undois.id
  pattern     = "www.${local.domain_name}/api/status*"
  script_name = cloudflare_workers_script.status_api.name
}

resource "cloudflare_workers_route" "status_subdomain" {
  zone_id     = data.cloudflare_zone.undois.id
  pattern     = "status.${local.domain_name}/*"
  script_name = cloudflare_workers_script.status_api.name
}

# --- Contact Form API (Cloudflare Worker + KV Rate Limit + Email Sending) ---
resource "cloudflare_workers_kv_namespace" "contact_ratelimit" {
  account_id = data.cloudflare_zone.undois.account_id
  title      = "undois_contact_ratelimit"
}

resource "cloudflare_workers_script" "contact_api" {
  account_id = data.cloudflare_zone.undois.account_id
  name       = "undois-contact-api"
  content    = file("${path.module}/workers/contact.js")
  module     = true

  kv_namespace_binding {
    name         = "RATE_LIMIT_KV"
    namespace_id = cloudflare_workers_kv_namespace.contact_ratelimit.id
  }

  plain_text_binding {
    name = "CF_ACCOUNT_ID"
    text = data.cloudflare_zone.undois.account_id
  }

  plain_text_binding {
    name = "TO_EMAIL"
    text = "cameron@${local.domain_name}"
  }

  plain_text_binding {
    name = "FROM_EMAIL"
    text = "contact@${local.domain_name}"
  }

  secret_text_binding {
    name = "CF_EMAIL_API_TOKEN"
    text = var.cloudflare_email_api_token
  }
}

resource "cloudflare_workers_route" "www_contact_api" {
  zone_id     = data.cloudflare_zone.undois.id
  pattern     = "www.${local.domain_name}/api/contact*"
  script_name = cloudflare_workers_script.contact_api.name
}
