# Kubernetes resources for SonarQube deployment

# SonarQube Namespace
resource "kubernetes_namespace" "sonarqube" {
  metadata {
    name = "sonarqube"
  }
  depends_on = [google_container_node_pool.jenkins_sonarqube_nodes]
}

# SonarQube PersistentVolumeClaim
resource "kubernetes_persistent_volume_claim" "sonarqube_pvc" {
  wait_until_bound = false
  metadata {
    name      = "sonarqube-pvc"
    namespace = kubernetes_namespace.sonarqube.metadata[0].name
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

# PostgreSQL PersistentVolumeClaim (SonarQube dependency)
resource "kubernetes_persistent_volume_claim" "postgres_pvc" {
  wait_until_bound = false
  metadata {
    name      = "postgres-pvc"
    namespace = kubernetes_namespace.sonarqube.metadata[0].name
  }
  spec {
    access_modes = ["ReadWriteOnce"]
    storage_class_name = "standard"
    resources {
      requests = {
        storage = "10Gi"
      }
    }
  }
}

# PostgreSQL Deployment
resource "kubernetes_deployment" "postgres" {
  metadata {
    name      = "postgres"
    namespace = kubernetes_namespace.sonarqube.metadata[0].name
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "postgres"
      }
    }

    template {
      metadata {
        labels = {
          app = "postgres"
        }
      }

      spec {
        container {
          name  = "postgres"
          image = "postgres:13"

      env {
        name  = "POSTGRES_USER"
        value = "sonar"
      }

      env {
        name  = "POSTGRES_PASSWORD"
        value = "sonar"
      }

      env {
        name  = "POSTGRES_DB"
        value = "sonarqube"
      }

      env {
        name  = "PGDATA"
        value = "/var/lib/postgresql/data/pgdata"
      }

          port {
            container_port = 5432
          }

          resources {
            limits = {
              memory = "1Gi"
              cpu    = "500m"
            }
            requests = {
              memory = "512Mi"
              cpu    = "250m"
            }
          }

          volume_mount {
            name       = "postgres-storage"
            mount_path = "/var/lib/postgresql/data"
          }
        }

        volume {
          name = "postgres-storage"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.postgres_pvc.metadata[0].name
          }
        }
      }
    }
  }
}

# PostgreSQL Service
resource "kubernetes_service" "postgres_service" {
  metadata {
    name      = "postgres-service"
    namespace = kubernetes_namespace.sonarqube.metadata[0].name
  }

  spec {
    selector = {
      app = "postgres"
    }

    port {
      port        = 5432
      target_port = 5432
    }

    type = "ClusterIP"
  }
}

# SonarQube Deployment
resource "kubernetes_deployment" "sonarqube" {
  metadata {
    name      = "sonarqube"
    namespace = kubernetes_namespace.sonarqube.metadata[0].name
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "sonarqube"
      }
    }

    template {
      metadata {
        labels = {
          app = "sonarqube"
        }
      }

      spec {
        security_context {
          fs_group = 1000
        }

        init_container {
          name  = "init-sysctl"
          image = "busybox:1.32"
          command = [
            "sh",
            "-c",
            "sysctl -w vm.max_map_count=524288 && sysctl -w fs.file-max=131072"
          ]
          security_context {
            privileged = true
          }
        }

        container {
          name  = "sonarqube"
          image = "sonarqube:community"

          env {
            name  = "SONAR_JDBC_URL"
            value = "jdbc:postgresql://postgres-service:5432/sonarqube"
          }

          env {
            name  = "SONAR_JDBC_USERNAME"
            value = "sonar"
          }

          env {
            name  = "SONAR_JDBC_PASSWORD"
            value = "sonar"
          }

          port {
            container_port = 9000
          }

          resources {
            limits = {
              memory = "3Gi"
              cpu    = "2000m"
            }
            requests = {
              memory = "2Gi"
              cpu    = "1000m"
            }
          }

          volume_mount {
            name       = "sonarqube-data"
            mount_path = "/opt/sonarqube/data"
          }

          volume_mount {
            name       = "sonarqube-logs"
            mount_path = "/opt/sonarqube/logs"
          }

          volume_mount {
            name       = "sonarqube-extensions"
            mount_path = "/opt/sonarqube/extensions"
          }

          liveness_probe {
            http_get {
              path = "/api/system/status"
              port = 9000
            }
            initial_delay_seconds = 120
            period_seconds        = 10
            timeout_seconds       = 5
            failure_threshold     = 6
          }

          readiness_probe {
            http_get {
              path = "/api/system/status"
              port = 9000
            }
            initial_delay_seconds = 120
            period_seconds        = 10
            timeout_seconds       = 5
            failure_threshold     = 6
          }
        }

        volume {
          name = "sonarqube-data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.sonarqube_pvc.metadata[0].name
          }
        }

        volume {
          name = "sonarqube-logs"
          empty_dir {}
        }

        volume {
          name = "sonarqube-extensions"
          empty_dir {}
        }
      }
    }
  }

  depends_on = [kubernetes_deployment.postgres]
}

# SonarQube Service
resource "kubernetes_service" "sonarqube_service" {
  metadata {
    name      = "sonarqube-service"
    namespace = kubernetes_namespace.sonarqube.metadata[0].name
  }

  spec {
    type = "LoadBalancer"

    selector = {
      app = "sonarqube"
    }

    port {
      port        = 9000
      target_port = 9000
      protocol    = "TCP"
    }
  }
}

