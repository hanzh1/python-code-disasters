# GCP Service Account for Jenkins with Workload Identity
# This allows Jenkins running in GKE to authenticate to GCP services

# Create a GCP service account for Jenkins
resource "google_service_account" "jenkins_sa" {
  account_id   = "jenkins-workload-identity"
  display_name = "Jenkins Workload Identity Service Account"
  description  = "Service account for Jenkins to access GCS, Dataproc, and other GCP services"
  project      = var.project_id
}

# Grant Storage Object Admin role (for GCS bucket access)
resource "google_project_iam_member" "jenkins_storage_admin" {
  project = var.project_id
  role    = "roles/storage.objectAdmin"
  member  = "serviceAccount:${google_service_account.jenkins_sa.email}"
}

# Grant Dataproc Job Submitter role (for submitting Hadoop jobs)
resource "google_project_iam_member" "jenkins_dataproc_job_submitter" {
  project = var.project_id
  role    = "roles/dataproc.worker"
  member  = "serviceAccount:${google_service_account.jenkins_sa.email}"
}

# Grant Dataproc Editor role (for full Dataproc access)
resource "google_project_iam_member" "jenkins_dataproc_editor" {
  project = var.project_id
  role    = "roles/dataproc.editor"
  member  = "serviceAccount:${google_service_account.jenkins_sa.email}"
}

# Grant Service Account User role (required for Dataproc)
resource "google_project_iam_member" "jenkins_sa_user" {
  project = var.project_id
  role    = "roles/iam.serviceAccountUser"
  member  = "serviceAccount:${google_service_account.jenkins_sa.email}"
}

# Bind the Kubernetes service account to the GCP service account (Workload Identity)
resource "google_service_account_iam_member" "jenkins_workload_identity_binding" {
  service_account_id = google_service_account.jenkins_sa.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[jenkins/jenkins]"
}

# Output the service account email for reference
output "jenkins_gcp_service_account_email" {
  value       = google_service_account.jenkins_sa.email
  description = "Email of the GCP service account for Jenkins"
}

