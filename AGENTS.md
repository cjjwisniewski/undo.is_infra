# undo.is_infra — Agent Guidelines & Repository Specifics

This repository contains the Terraform configuration and Cloudflare Worker code for **`undo.is`** (`cjjwisniewski/undo.is_infra`).

## 1. Git, CI/CD & Documentation Continuity
- **Commit & Push**: Use [Conventional Commits](https://www.conventionalcommits.org/) (`feat(scope):`, `fix(scope):`, `chore(scope):`, `docs(scope):`) and push to `origin/main`.
- **Keep BookStack up to date**: Whenever Azure resources, Cloudflare DNS/rules, Worker endpoints/hosts, or OIDC/CI rules change, update the **`undo.is`** book in BookStack (`HomeLab` shelf, via `bookstack-mcp` at `http://127.0.0.1:8002/mcp`).

## 2. Terraform Workflow & Safety Guards
- **Remote State**: Backend is `azurerm` in resource group `undoissite`, storage account `undoissite`, container `tfstate`, key `terraform.tfstate`.
- **No Auto-Apply on Push**: `.github/workflows/deploy.yml` runs `terraform init`, `terraform validate`, and `terraform plan` only on `push` and `pull_request` to `main`.
- **Manual Apply via `workflow_dispatch`**: To apply changes in CI, trigger `workflow_dispatch` with `apply=true` (and optional `untaint_address`).
- **Destructive-Plan Guard**: The CI workflow inspects `terraform show -json tfplan` and **aborts if `DESTROY_COUNT > 0`** (any `delete` or replacement action) to protect stateful resources (`undoissite` storage account, `tfstate` container, KV namespace `homelab_status`). Do not expect CI to apply destructive/replacement plans automatically.
- **Local Runs**: Require `CLOUDFLARE_API_TOKEN` in the environment (`export CLOUDFLARE_API_TOKEN="..."`) and Azure authentication (`az login` / `ARM_ACCESS_KEY`).

## 3. Infrastructure Coupling & Invariants
- **Azure Custom Domain Validation**:
  - `azurerm_storage_account.static_site` (`undoissite`, `eastus2`, `StorageV2`, `Standard_LRS`) binds `www.undo.is` (`use_subdomain = true`) and depends on `cloudflare_record.asverify`.
  - `cloudflare_record.asverify` (`asverify.www` -> `asverify.undoissite.z20.web.core.windows.net`) **must remain `proxied = false`** so Azure can validate the domain.
- **Cloudflare Edge & Redirects**:
  - `www` CNAME -> `undoissite` `primary_web_host` (`proxied = true`).
  - `cloudflare_page_rule.root_to_www` redirects `undo.is/*` -> `https://www.undo.is/$1` (`301`).
  - Zone SSL is `full` with `always_use_https = "on"`, `automatic_https_rewrites = "on"`, `brotli = "on"`, `email_obfuscation = "off"`, and `rocket_loader = "off"`.
  - `cloudflare_ruleset.security_headers` sets CSP, HSTS, `X-Frame-Options: DENY`, `X-Content-Type-Options: nosniff`, `Referrer-Policy`, and `Permissions-Policy` on `www.undo.is`.
- **GitHub Actions OIDC (`github.tf`)**:
  - `undois-github-deploy` Azure AD App/SP has a federated identity credential scoped strictly to `repo:cjjwisniewski/undo.is:ref:refs/heads/main` with `Storage Blob Data Contributor` on `undoissite`.
  - `azuread_application` and `azuread_service_principal` use `lifecycle { ignore_changes = [owners] }`; preserve this to avoid spurious diffs.

## 4. Homelab Status API Worker (`workers/status.js`)
- Deployed via `cloudflare_workers_script.status_api` (`undois-status-api`, `module = true`) with KV namespace `homelab_status` (`STATUS_KV`) and `HEARTBEAT_TOKEN` (`random_password.status_heartbeat_token`, sensitive output `status_heartbeat_token`).
- **Routes**: `www.undo.is/api/status*` and `status.undo.is/*` (non-API requests on `status.undo.is` redirect `302` to `https://www.undo.is/status/`).
- **Host Mapping & Staleness**:
  - `EXPECTED_HOSTS` maps internal `hostId`s (`intelligence-1`, `glados-core-1`, `adventure-2`, `adventure-1`) to public IDs (`docker-host`, `vm-host`, `valheim`, `minecraft`).
  - `minecraft` is excluded from `allCoreOnline` (so `overall` remains `"operational"` if only `minecraft` is offline; if another host goes offline while at least one host is online, `overall` becomes `"degraded"`).
  - `STALE_AFTER_MS` is `11 * 60 * 1000` (11 minutes) to provide >2x buffer over the 5-minute `status-pusher` interval (`288` KV writes/day).
- **CORS**: Allows `https://www.undo.is`, `https://status.undo.is`, and `http://localhost:5173`.
- Changes to `workers/status.js` are only live after `terraform apply` (or `workflow_dispatch` with `apply=true`).
