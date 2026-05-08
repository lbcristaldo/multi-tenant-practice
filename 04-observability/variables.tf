variable "environment" {
    type    = string
    default = "production"
}

variable "alert_email" {
    type    = string
    default = "ops@taxidancers.com"
}

variable "slack_webhook_url" {
    type      = string
    sensitive = true
    default   = ""
}