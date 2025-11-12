# Kubernetes resources for Jenkins deployment

# Jenkins Namespace
resource "kubernetes_namespace" "jenkins" {
  metadata {
    name = "jenkins"
  }
  depends_on = [google_container_node_pool.jenkins_sonarqube_nodes]
}

# ConfigMap for Jenkins plugins list
resource "kubernetes_config_map" "jenkins_plugins" {
  metadata {
    name      = "jenkins-plugins"
    namespace = kubernetes_namespace.jenkins.metadata[0].name
  }

  data = {
    "plugins.txt" = file("${path.module}/../scripts/plugins.txt")
  }

  depends_on = [kubernetes_namespace.jenkins]
}

# ConfigMap for Jenkins initialization scripts
resource "kubernetes_config_map" "jenkins_init_scripts" {
  metadata {
    name      = "jenkins-init-scripts"
    namespace = kubernetes_namespace.jenkins.metadata[0].name
  }

  data = {
    "01-configure-sonarqube.groovy" = file("${path.module}/../scripts/jenkins-init-sonarqube.groovy")
  }

  depends_on = [kubernetes_namespace.jenkins]
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

        # Fix DNS resolution for GitHub
        host_aliases {
          ip        = "140.82.121.3"
          hostnames = ["github.com"]
        }
        host_aliases {
          ip        = "140.82.112.3"
          hostnames = ["github.com"]
        }
        
        # Fix DNS resolution for SonarSource binaries
        host_aliases {
          ip        = "13.227.74.109"
          hostnames = ["binaries.sonarsource.com"]
        }
        host_aliases {
          ip        = "13.227.74.28"
          hostnames = ["binaries.sonarsource.com"]
        }
        
        # Fix DNS resolution for SonarQube service
        host_aliases {
          ip        = "34.118.238.107"
          hostnames = ["sonarqube-service", "sonarqube-service.sonarqube", "sonarqube-service.sonarqube.svc.cluster.local"]
        }

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

          env {
            name  = "GITHUB_REPO_URL"
            value = var.github_repo_url
          }

          env {
            name  = "SONARQUBE_TOKEN"
            value = "squ_81d4e790a00037c5f4479ba65f456992d23d9bdd"  # SonarQube API token for Jenkins
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

          volume_mount {
            name       = "init-scripts"
            mount_path = "/usr/share/jenkins/ref/init.groovy.d"
          }

          volume_mount {
            name       = "plugins"
            mount_path = "/usr/share/jenkins/ref/plugins.txt"
            sub_path   = "plugins.txt"
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

        volume {
          name = "init-scripts"
          config_map {
            name = kubernetes_config_map.jenkins_init_scripts.metadata[0].name
          }
        }

        volume {
          name = "plugins"
          config_map {
            name = kubernetes_config_map.jenkins_plugins.metadata[0].name
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

