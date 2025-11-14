# Kubernetes resources for Jenkins deployment

# Jenkins Namespace
resource "kubernetes_namespace" "jenkins" {
  metadata {
    name = "jenkins"
  }
  depends_on = [google_container_node_pool.jenkins_sonarqube_nodes]
}

# Jenkins PersistentVolumeClaim
resource "kubernetes_persistent_volume_claim" "jenkins_pvc" {
  wait_until_bound = false
  metadata {
    name      = "jenkins-pvc"
    namespace = kubernetes_namespace.jenkins.metadata[0].name
  }
  spec {
    access_modes = ["ReadWriteOnce"]
    storage_class_name = "standard"
    resources {
      requests = {
        storage = "20Gi"
      }
    }
  }
}

# Jenkins ServiceAccount with Workload Identity annotation
resource "kubernetes_service_account" "jenkins_sa" {
  metadata {
    name      = "jenkins"
    namespace = kubernetes_namespace.jenkins.metadata[0].name
    annotations = {
      "iam.gke.io/gcp-service-account" = google_service_account.jenkins_sa.email
    }
  }
  depends_on = [google_service_account.jenkins_sa]
}

# Jenkins Deployment
resource "kubernetes_deployment" "jenkins" {
  metadata {
    name      = "jenkins"
    namespace = kubernetes_namespace.jenkins.metadata[0].name
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "jenkins"
      }
    }

    template {
      metadata {
        labels = {
          app = "jenkins"
        }
      }

      spec {
        service_account_name = kubernetes_service_account.jenkins_sa.metadata[0].name

        security_context {
          fs_group = 1000
        }

        container {
          name  = "jenkins"
          image = "jenkins/jenkins:lts"

          port {
            container_port = 8080
            name           = "http"
          }

          port {
            container_port = 50000
            name           = "agent"
          }

          env {
            name  = "JENKINS_OPTS"
            value = "--prefix=/jenkins"
          }

          env {
            name  = "JAVA_OPTS"
            value = "-Djenkins.install.runSetupWizard=false -Dhudson.model.DirectoryBrowserSupport.CSP="
          }

          env {
            name  = "SONARQUBE_URL"
            value = "http://sonarqube-service.sonarqube.svc.cluster.local:9000"
          }

          env {
            name  = "GCP_PROJECT_ID"
            value = var.project_id
          }

          env {
            name  = "HADOOP_CLUSTER_NAME"
            value = google_dataproc_cluster.hadoop_cluster.name
          }

          env {
            name  = "HADOOP_REGION"
            value = var.region
          }

          env {
            name  = "OUTPUT_BUCKET"
            value = google_storage_bucket.hadoop_output.name
          }

          env {
            name  = "STAGING_BUCKET"
            value = google_storage_bucket.dataproc_staging.name
          }

          resources {
            limits = {
              memory = "2Gi"
              cpu    = "1000m"
            }
            requests = {
              memory = "1Gi"
              cpu    = "500m"
            }
          }

          volume_mount {
            name       = "jenkins-home"
            mount_path = "/var/jenkins_home"
          }

          liveness_probe {
            http_get {
              path = "/jenkins/login"
              port = 8080
            }
            initial_delay_seconds = 90
            period_seconds        = 10
            timeout_seconds       = 5
            failure_threshold     = 5
          }

          readiness_probe {
            http_get {
              path = "/jenkins/login"
              port = 8080
            }
            initial_delay_seconds = 60
            period_seconds        = 10
            timeout_seconds       = 5
            failure_threshold     = 3
          }
        }

        volume {
          name = "jenkins-home"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.jenkins_pvc.metadata[0].name
          }
        }
      }
    }
  }
}

# Jenkins Service
resource "kubernetes_service" "jenkins_service" {
  metadata {
    name      = "jenkins-service"
    namespace = kubernetes_namespace.jenkins.metadata[0].name
  }

  spec {
    type = "LoadBalancer"

    selector = {
      app = "jenkins"
    }

    port {
      name        = "http"
      port        = 8080
      target_port = 8080
      protocol    = "TCP"
    }

    port {
      name        = "agent"
      port        = 50000
      target_port = 50000
      protocol    = "TCP"
    }
  }
}

