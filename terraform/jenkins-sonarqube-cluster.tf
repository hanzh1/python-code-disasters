# Week 6: Jenkins and SonarQube Deployment on GKE
# This creates a GKE cluster for Jenkins and SonarQube

resource "google_container_cluster" "jenkins_sonarqube_cluster" {
  name     = "jenkins-sonarqube-cluster"
  location = var.zone

  # We can't create a cluster with no node pool defined, but we want to only use
  # separately managed node pools. So we create the smallest possible default
  # node pool and immediately delete it.
  remove_default_node_pool = true
  initial_node_count       = 1

  network    = google_compute_network.vpc_network.name
  subnetwork = google_compute_subnetwork.subnet.name

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  addons_config {
    http_load_balancing {
      disabled = false
    }
    horizontal_pod_autoscaling {
      disabled = false
    }
  }

  release_channel {
    channel = "REGULAR"
  }
}

resource "google_container_node_pool" "jenkins_sonarqube_nodes" {
  name       = "jenkins-sonarqube-node-pool"
  location   = var.zone
  cluster    = google_container_cluster.jenkins_sonarqube_cluster.name
  node_count = 3

  node_config {
    machine_type = "n1-standard-4"
    disk_size_gb = 100

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    labels = {
      env = "jenkins-sonarqube"
    }

    tags = ["jenkins-sonarqube"]

    metadata = {
      disable-legacy-endpoints = "true"
    }

    workload_metadata_config {
      mode = "GKE_METADATA"
    }
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }
}

# VPC Network
resource "google_compute_network" "vpc_network" {
  name                    = "jenkins-sonarqube-network"
  auto_create_subnetworks = false
}

# Subnet
resource "google_compute_subnetwork" "subnet" {
  name          = "jenkins-sonarqube-subnet"
  ip_cidr_range = "10.0.0.0/24"
  region        = var.region
  network       = google_compute_network.vpc_network.id
}

# Firewall rules
resource "google_compute_firewall" "jenkins_sonarqube_allow" {
  name    = "jenkins-sonarqube-allow"
  network = google_compute_network.vpc_network.name

  allow {
    protocol = "tcp"
    ports    = ["8080", "9000", "443", "80"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["jenkins-sonarqube"]
}


