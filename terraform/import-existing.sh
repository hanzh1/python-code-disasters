#!/bin/bash
# Script to import existing GCP resources into Terraform state
# Run this if resources already exist in your GCP project

set -e

PROJECT_ID="caramel-era-471823-c8"

echo "Importing existing GCP resources into Terraform state..."
echo "Project: $PROJECT_ID"
echo ""

# Import storage buckets
echo "1. Importing storage buckets..."
terraform import google_storage_bucket.dataproc_staging ${PROJECT_ID}-dataproc-staging || echo "Bucket may already be imported"
terraform import google_storage_bucket.hadoop_output ${PROJECT_ID}-hadoop-output || echo "Bucket may already be imported"

# Import service accounts
echo "2. Importing service accounts..."
terraform import google_service_account.hadoop_sa projects/${PROJECT_ID}/serviceAccounts/hadoop-cluster-sa@${PROJECT_ID}.iam.gserviceaccount.com || echo "Service account may already be imported"
terraform import google_service_account.jenkins_sa projects/${PROJECT_ID}/serviceAccounts/jenkins-workload-identity@${PROJECT_ID}.iam.gserviceaccount.com || echo "Service account may already be imported"

# Import network
echo "3. Importing network..."
terraform import google_compute_network.vpc_network projects/${PROJECT_ID}/global/networks/jenkins-sonarqube-network || echo "Network may already be imported"

echo ""
echo "Import complete! Run 'terraform plan' to see what else needs to be created."

