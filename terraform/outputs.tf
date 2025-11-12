output "hadoop_cluster_name" {
  description = "Name of the Hadoop Dataproc cluster"
  value       = google_dataproc_cluster.hadoop_cluster.name
}

output "hadoop_master_instance_name" {
  description = "Hadoop master instance name"
  value       = google_dataproc_cluster.hadoop_cluster.cluster_config[0].master_config[0].instance_names[0]
}

output "gke_cluster_name" {
  description = "GKE cluster name for Jenkins and SonarQube"
  value       = google_container_cluster.jenkins_sonarqube_cluster.name
}

output "gke_cluster_endpoint" {
  description = "GKE cluster endpoint"
  value       = google_container_cluster.jenkins_sonarqube_cluster.endpoint
  sensitive   = true
}

output "jenkins_url" {
  description = "Jenkins URL (available after kubectl apply)"
  value       = "http://${kubernetes_service.jenkins_service.status[0].load_balancer[0].ingress[0].ip}:8080"
}

output "sonarqube_url" {
  description = "SonarQube URL (available after kubectl apply)"
  value       = "http://${kubernetes_service.sonarqube_service.status[0].load_balancer[0].ingress[0].ip}:9000"
}

output "hadoop_output_bucket" {
  description = "GCS bucket for Hadoop job outputs"
  value       = google_storage_bucket.hadoop_output.url
}

output "dataproc_staging_bucket" {
  description = "GCS bucket for Dataproc staging"
  value       = google_storage_bucket.dataproc_staging.url
}

output "configure_kubectl_command" {
  description = "Command to configure kubectl"
  value       = "gcloud container clusters get-credentials ${google_container_cluster.jenkins_sonarqube_cluster.name} --zone ${var.zone} --project ${var.project_id}"
}


