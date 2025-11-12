#!/bin/bash
# Complete deployment script
# This script automates the entire deployment process

set -e

echo "========================================="
echo "Cloud Infrastructure Deployment Script"
echo "========================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_info() {
    echo -e "${NC}ℹ $1${NC}"
}

# Get project ID from terraform.tfvars if available
if [ -f "../terraform/terraform.tfvars" ]; then
    PROJECT_ID=$(grep 'project_id' ../terraform/terraform.tfvars | cut -d'"' -f2 | head -1)
    if [ -z "$PROJECT_ID" ]; then
        PROJECT_ID=$(grep '^project_id' ../terraform/terraform.tfvars | cut -d'=' -f2 | tr -d ' "' | head -1)
    fi
else
    PROJECT_ID="${GCP_PROJECT_ID:-}"
    if [ -z "$PROJECT_ID" ]; then
        print_error "Project ID not found. Please set GCP_PROJECT_ID or configure terraform.tfvars"
        exit 1
    fi
fi

ZONE="${GCP_ZONE:-us-central1-a}"
REGION="${GCP_REGION:-us-central1}"
CLUSTER_NAME="jenkins-sonarqube-cluster"

echo "📋 Configuration:"
echo "   Project: $PROJECT_ID"
echo "   Zone: $ZONE"
echo "   Region: $REGION"
echo "   Cluster: $CLUSTER_NAME"
echo ""

# Step 1: Authenticate with GCP
echo "Step 1: Authenticating with GCP..."
echo "────────────────────────────────────────────────────────────"
if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
    print_warning "No active GCP authentication found"
    print_info "Please run: gcloud auth login"
    exit 1
fi
print_success "GCP authentication verified"

# Step 2: Set project
echo ""
echo "Step 2: Setting GCP project..."
echo "────────────────────────────────────────────────────────────"
gcloud config set project $PROJECT_ID
print_success "Project set to $PROJECT_ID"

# Step 3: Enable required APIs
echo ""
echo "Step 3: Enabling required GCP APIs..."
echo "────────────────────────────────────────────────────────────"
APIS=(
    "compute.googleapis.com"
    "container.googleapis.com"
    "dataproc.googleapis.com"
    "storage.googleapis.com"
)

for API in "${APIS[@]}"; do
    if gcloud services list --enabled --filter="name:$API" --format="value(name)" | grep -q "$API"; then
        print_info "$API is already enabled"
    else
        print_info "Enabling $API..."
        gcloud services enable $API
        print_success "$API enabled"
    fi
done

# Step 4: Deploy with Terraform
echo ""
echo "Step 4: Deploying infrastructure with Terraform..."
echo "────────────────────────────────────────────────────────────"
cd "$(dirname "$0")/../terraform"

if [ ! -f "terraform.tfvars" ]; then
    print_error "terraform.tfvars not found!"
    print_info "Please create terraform.tfvars from terraform.tfvars.example"
    exit 1
fi

print_info "Initializing Terraform..."
terraform init

print_info "Planning Terraform deployment..."
terraform plan -out=tfplan

echo ""
read -p "Review the plan above. Apply changes? (yes/no): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
    print_warning "Deployment cancelled by user"
    exit 0
fi

print_info "Applying Terraform configuration..."
terraform apply tfplan
print_success "Terraform deployment completed"

# Step 5: Configure kubectl
echo ""
echo "Step 5: Configuring kubectl..."
echo "────────────────────────────────────────────────────────────"
gcloud container clusters get-credentials $CLUSTER_NAME \
    --zone $ZONE \
    --project $PROJECT_ID
print_success "kubectl configured"

# Step 6: Wait for services
echo ""
echo "Step 6: Waiting for services to be ready..."
echo "────────────────────────────────────────────────────────────"
print_info "Waiting for Jenkins deployment..."
if kubectl wait --for=condition=available --timeout=600s deployment/jenkins -n jenkins 2>/dev/null; then
    print_success "Jenkins is ready"
else
    print_warning "Jenkins may need more time (check with: kubectl get pods -n jenkins)"
fi

print_info "Waiting for SonarQube deployment..."
if kubectl wait --for=condition=available --timeout=600s deployment/sonarqube -n sonarqube 2>/dev/null; then
    print_success "SonarQube is ready"
else
    print_warning "SonarQube may need more time (check with: kubectl get pods -n sonarqube)"
fi

# Step 7: Wait for LoadBalancer IPs
echo ""
echo "Step 7: Waiting for LoadBalancer IPs..."
echo "────────────────────────────────────────────────────────────"
print_info "Waiting for Jenkins LoadBalancer IP (this may take 2-3 minutes)..."
JENKINS_IP=""
for i in {1..30}; do
    JENKINS_IP=$(kubectl get svc jenkins-service -n jenkins -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
    if [ -n "$JENKINS_IP" ]; then
        print_success "Jenkins IP: $JENKINS_IP"
        break
    fi
    echo -n "."
    sleep 10
done

if [ -z "$JENKINS_IP" ]; then
    print_warning "Jenkins LoadBalancer IP not assigned yet (check later with: kubectl get svc -n jenkins)"
fi

print_info "Waiting for SonarQube LoadBalancer IP..."
SONARQUBE_IP=""
for i in {1..30}; do
    SONARQUBE_IP=$(kubectl get svc sonarqube-service -n sonarqube -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
    if [ -n "$SONARQUBE_IP" ]; then
        print_success "SonarQube IP: $SONARQUBE_IP"
        break
    fi
    echo -n "."
    sleep 10
done

if [ -z "$SONARQUBE_IP" ]; then
    print_warning "SonarQube LoadBalancer IP not assigned yet (check later with: kubectl get svc -n sonarqube)"
fi

# Step 8: Display service URLs
echo ""
echo "========================================="
echo "Service URLs"
echo "========================================="
if [ -n "$JENKINS_IP" ]; then
    echo "Jenkins: http://${JENKINS_IP}:8080/jenkins"
    echo "  (Note: Jenkins uses /jenkins prefix)"
else
    echo "Jenkins: (IP not assigned yet)"
fi

if [ -n "$SONARQUBE_IP" ]; then
    echo "SonarQube: http://${SONARQUBE_IP}:9000"
else
    echo "SonarQube: (IP not assigned yet)"
fi

# Step 9: Run automated setup
echo ""
echo "========================================="
echo "Next Steps"
echo "========================================="
echo ""
echo "1. Wait 2-5 minutes for services to fully start"
echo ""
echo "2. Token is already configured in Terraform (no manual steps needed)"
echo ""
echo "3. Configure Jenkins pipeline job (one-time manual step)"
echo ""
echo "4. (Optional) Configure GitHub webhook:"
if [ -n "$JENKINS_IP" ]; then
    echo "   URL: http://${JENKINS_IP}:8080/github-webhook/"
fi
echo ""
echo "========================================="
echo "✅ Deployment Complete!"
echo "========================================="
echo ""
echo "Check service status:"
echo "  kubectl get pods -n jenkins"
echo "  kubectl get pods -n sonarqube"
echo ""

