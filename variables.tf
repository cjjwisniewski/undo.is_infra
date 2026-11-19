variable "cloudflare_email_api_token" {
  description = "Cloudflare API token with Email Sending permission for undois-contact-api Worker"
  type        = string
  default     = ""
  sensitive   = true
}
