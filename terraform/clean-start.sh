#!/bin/bash
# Script to clean up and start fresh
# WARNING: This will delete Terraform state and optionally GCP resources

set -e

echo "========================================="
echo "Clean Start Script"
echo "========================================="
echo ""
echo "This script will:"
echo "1. Delete Terraform state files"
echo "2. Optionally delete existing GCP resources"
echo ""
read -p "Do you want to DELETE existing GCP resources? (yes/no): " DELETE_RESOURCES

if [ "$DELETE_RESOURCES" = "yes" ]; then
    echo ""
    echo "Deleting existing GCP resources..."
    
    PROJECT_ID="caramel-era-471823-c8"
    
    # Delete Dataproc cluster if exists
    echo "Checking for Dataproc cluster..."
    if gcloud dataproc clusters describe hadoop-cluster --region=us-central1 --project=$PROJECT_ID &>/dev/null; then
        echo "Deleting Dataproc cluster..."
        gcloud dataproc clusters delete hadoop-cluster --region=us-central1 --project=$PROJECT_ID --quiet || true
    fi
    
    # Delete GKE cluster if exists
    echo "Checking for GKE cluster..."
    if gcloud container clusters describe jenkins-sonarqube-cluster --zone=us-central1-a --project=$PROJECT_ID &>/dev/null; then
        echo "Deleting GKE cluster (this may take 10-15 minutes)..."
        gcloud container clusters delete jenkins-sonarqube-cluster --zone=us-central1-a --project=$PROJECT_ID --quiet || true
    fi
    
    # Delete service accounts
    echo "Deleting service accounts..."
    gcloud iam service-accounts delete jenkins-workload-identity@${PROJECT_ID}.iam.gserviceaccount.com --project=$PROJECT_ID --quiet || true
    gcloud iam service-accounts delete hadoop-cluster-sa@${PROJECT_ID}.iam.gserviceaccount.com --project=$PROJECT_ID --quiet || true
    
    # Delete network (this will fail if resources still exist)
    echo "Deleting network..."
    gcloud compute networks delete jenkins-sonarqube-network --project=$PROJECT_ID --quiet || true
    
    # Delete storage buckets (optional - comment out if you want to keep data)
    echo "Deleting storage buckets..."
    gsutil rm -r gs://${PROJECT_ID}-dataproc-staging || true
    gsutil rm -r gs://${PROJECT_ID}-hadoop-output || true
    
    echo ""
    echo "✓ GCP resources deleted"
else
    echo ""
    echo "Skipping GCP resource deletion"
    echo "Note: You'll need to import existing resources or delete them manually"
fi

echo ""
echo "Deleting Terraform state files..."
rm -f terraform.tfstate terraform.tfstate.backup .terraform.lock.hcl
rm -rf .terraform/

echo ""
echo "✓ State files deleted"
echo ""
echo "Next steps:"
echo "1. Run: terraform init"
echo "2. Run: terraform plan"
echo "3. Run: terraform apply"
echo ""
echo "If resources already exist, you'll get 409 errors."
echo "In that case, either:"
echo "  - Import them: terraform import <resource> <id>"
echo "  - Or delete them from GCP first"
echo ""

