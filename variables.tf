variable "resend_api_key" {
  description = "Resend API key for undois-contact-api email delivery to cameron@undo.is"
  type        = string
  default     = ""
  sensitive   = true
}

variable "discord_contact_webhook_url" {
  description = "Discord webhook URL for instant contact form notifications"
  type        = string
  default     = ""
  sensitive   = true
}
