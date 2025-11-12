variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "region" {
  description = "GCP Region"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "GCP Zone"
  type        = string
  default     = "us-central1-a"
}

variable "github_repo_url" {
  description = "Forked GitHub repository URL"
  type        = string
}

variable "github_webhook_secret" {
  description = "GitHub webhook secret for Jenkins"
  type        = string
  sensitive   = true
}


