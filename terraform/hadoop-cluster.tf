# Week 4: Hadoop Cluster Deployment using Dataproc
# This creates a Hadoop cluster with 1 master and 2 worker nodes

resource "google_dataproc_cluster" "hadoop_cluster" {
  name   = "hadoop-cluster"
  region = var.region

  cluster_config {
    staging_bucket = google_storage_bucket.dataproc_staging.name

    master_config {
      num_instances = 1
      machine_type  = "n1-standard-4"
      disk_config {
        boot_disk_type    = "pd-standard"
        boot_disk_size_gb = 100
      }
    }

    worker_config {
      num_instances = 2
      machine_type  = "n1-standard-4"
      disk_config {
        boot_disk_type    = "pd-standard"
        boot_disk_size_gb = 100
      }
    }

    software_config {
      image_version = "2.1-debian11"
      override_properties = {
        "dataproc:dataproc.allow.zero.workers" = "false"
      }
    }

    gce_cluster_config {
      zone = var.zone
      metadata = {
        "enable-oslogin" = "true"
      }
      tags = ["hadoop-cluster"]
    }

    # Initialize with MapReduce job script
    initialization_action {
      script      = "gs://${google_storage_bucket.dataproc_staging.name}/scripts/init-hadoop.sh"
      timeout_sec = 500
    }
  }

  depends_on = [
    google_storage_bucket_object.init_script,
    google_storage_bucket_object.mapreduce_job
  ]
}

# Storage bucket for Dataproc staging
resource "google_storage_bucket" "dataproc_staging" {
  name          = "${var.project_id}-dataproc-staging"
  location      = var.region
  force_destroy = true

  uniform_bucket_level_access = true

  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "Delete"
    }
  }
}

# Storage bucket for Hadoop job outputs
resource "google_storage_bucket" "hadoop_output" {
  name          = "${var.project_id}-hadoop-output"
  location      = var.region
  force_destroy = true

  uniform_bucket_level_access = true
}

# Upload initialization script
resource "google_storage_bucket_object" "init_script" {
  name   = "scripts/init-hadoop.sh"
  bucket = google_storage_bucket.dataproc_staging.name
  source = "${path.module}/../scripts/init-hadoop.sh"
}

# Upload MapReduce job
resource "google_storage_bucket_object" "mapreduce_job" {
  name   = "jobs/line_counter.py"
  bucket = google_storage_bucket.dataproc_staging.name
  source = "${path.module}/../hadoop-jobs/line_counter.py"
  
  depends_on = [google_storage_bucket.dataproc_staging]
}

# Service account for Hadoop cluster
resource "google_service_account" "hadoop_sa" {
  account_id   = "hadoop-cluster-sa"
  display_name = "Hadoop Cluster Service Account"
}

resource "google_project_iam_member" "hadoop_sa_dataproc_worker" {
  project = var.project_id
  role    = "roles/dataproc.worker"
  member  = "serviceAccount:${google_service_account.hadoop_sa.email}"
}

resource "google_project_iam_member" "hadoop_sa_storage_admin" {
  project = var.project_id
  role    = "roles/storage.admin"
  member  = "serviceAccount:${google_service_account.hadoop_sa.email}"
}


