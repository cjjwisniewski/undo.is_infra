# undo.is Infrastructure

This repository contains the Terraform configuration for managing the infrastructure of the `undo.is` static website.

## Architecture

The infrastructure sets up the following components natively using Terraform:
- **Azure Storage Account (`undoissite`)**: Hosts the static site assets via the `$web` container.
- **Azure Backend State**: The Terraform `.tfstate` is saved synchronously inside a private `tfstate` blob container on the identical Storage Account `undoissite`.
- **Cloudflare DNS & Proxy**: Configuration to proxy custom domains `www.undo.is` to the Azure Storage primary web endpoint. Validates custom domains to Azure using a direct `asverify` CNAME bypass in order to secure frontend HTTPS automatically. Also manages the `undo.is` -> `www.undo.is` redirect configuration as a forwarding page rule. 
- **GitHub Actions OIDC**: A custom Azure AD Application and Service Principal configured with federated identity to enable passwordless `id-token` deployments straight from the underlying `cjjwisniewski/undo.is` source repository seamlessly without secrets in transit.

## Usage

You must pass the Cloudflare API Token locally via your shell in order to run Terraform commands successfully.

```bash
export CLOUDFLARE_API_TOKEN="..."
terraform plan
terraform apply
```

### Outputs
After apply, Terraform provides relevant IDs via `terraform output` that are injected securely into the source code's GitHub Actions Environment Secrets.

- `azure_client_id`
- `azure_subscription_id`
- `azure_tenant_id`
