terraform {
  required_version = ">= 1.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# Configure kubernetes provider after GKE cluster is created
provider "kubernetes" {
  host                   = "https://${google_container_cluster.jenkins_sonarqube_cluster.endpoint}"
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(google_container_cluster.jenkins_sonarqube_cluster.master_auth[0].cluster_ca_certificate)
}

data "google_client_config" "default" {}


