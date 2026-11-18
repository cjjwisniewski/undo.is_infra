# undo.is_infra Backlog

Running backlog for edge security, Cloudflare Worker hardening, and Azure/Terraform configuration in `/home/cwisniewski/undo.is_infra`.

## Status Legend
- `[ ]` Planned
- `[~]` In Progress
- `[x]` Done

---

## 1. Cloudflare Edge & Zone Security (`cloudflare.tf`)
- [ ] **Switch Cloudflare zone SSL mode from `"full"` to `"strict"`**: update `cloudflare_zone_settings_override.undois_settings` (`ssl = "strict"`) so Cloudflare enforces strict origin TLS certificate validation on Azure Storage (`www.undo.is`) and homelab endpoints
- [ ] **Extend security response headers ruleset to `status.undo.is`**: update `cloudflare_ruleset.security_headers` expression from `(http.host eq "www.undo.is")` to cover `status.undo.is` responses as well

## 2. Status API Worker Hardening (`workers/status.js`)
- [ ] **Use constant-time comparison for `HEARTBEAT_TOKEN`**: replace string inequality (`auth !== ...`) with `crypto.subtle.timingSafeEqual` over UTF-8 byte buffers (or fixed-length SHA-256 digests)
- [ ] **Validate and filter `payload.hosts` before writing to Workers KV**: filter incoming `payload.hosts` keys to `EXPECTED_HOSTS` (`intelligence-1`, `glados-core-1`, `adventure-2`, `adventure-1`), validate `status` (`"online"` / `"offline"`) and numeric `uptime`, and cap request body size before calling `env.STATUS_KV.put("latest", ...)`
- [ ] **Restrict heartbeat ingestion route & add rate limiting**: accept `POST` heartbeats only on `status.undo.is/api/heartbeat` (remove `/api/status/heartbeat` on `www.undo.is`) and add Cloudflare rate limiting on failed `401` attempts

## 3. Azure Storage & CI/CD Hardening (`storage.tf`, `.github/workflows/deploy.yml`)
- [ ] **Harden `undoissite` Azure Storage Account (`storage.tf`)**: explicitly set `allow_nested_items_to_be_public = false` and `min_tls_version = "TLS1_2"` on `azurerm_storage_account.static_site`, and enable blob versioning + soft delete to protect `tfstate`
- [ ] **Switch Terraform backend auth in CI from storage account keys to Azure AD OIDC**: replace `az storage account keys list` (`ARM_ACCESS_KEY`) in `.github/workflows/deploy.yml` with `use_azuread_auth = true` (`ARM_USE_AZUREAD=true`) and assign `Storage Blob Data Contributor` on the `tfstate` container
- [ ] **Pin third-party GitHub Actions to full commit SHAs**: pin `actions/checkout`, `hashicorp/setup-terraform`, and `azure/login` in `.github/workflows/deploy.yml` to immutable commit SHAs
