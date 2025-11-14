# Python Code Disasters - CI/CD Pipeline

Team Member: Hanzhi Zhu, Roxy He

### [Demo Code Walk through](https://drive.google.com/file/d/1eQSQlrhn3_Czjlo3_KCQQHAMmQ59SeTE/view?usp=sharing)
### [Demo Functionality](https://drive.google.com/file/d/1SETvliIZN7H9ZQPLM50SaF0w4Y7woB7V/view?usp=sharing)

This project implements a CI/CD pipeline using Jenkins, SonarQube, and Hadoop MapReduce on Google Cloud Platform. The pipeline automatically analyzes code quality and, if no blocker issues are found, runs a Hadoop job to count lines in all repository files.

## Prerequisites

- GCP account with billing enabled
- `gcloud`, `terraform`, `kubectl`, and `git` installed
- Fork this repository to your GitHub account

## Steps to Run Application

### Step 1: Configure Terraform Variables

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your values:
```hcl
project_id = "your-gcp-project-id"
region = "us-central1"
zone = "us-central1-a"
github_repo_url = "https://github.com/your-username/python-code-disasters"
github_webhook_secret = "your-secure-random-string-here"
```

### Step 2: Authenticate with GCP

```bash
gcloud auth login
gcloud config set project YOUR_PROJECT_ID
gcloud auth application-default login
```

### Step 3: Deploy Infrastructure

```bash
cd ../scripts
chmod +x deploy-all.sh
./deploy-all.sh
```

**Deployment takes approximately 10-15 minutes.**

### Step 4: Get Service URLs

After deployment completes:

```bash
# Configure kubectl
gcloud container clusters get-credentials jenkins-sonarqube-cluster \
    --zone us-central1-a \
    --project YOUR_PROJECT_ID

# Get Jenkins URL
JENKINS_IP=$(kubectl get svc jenkins-service -n jenkins -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "Jenkins: http://${JENKINS_IP}:8080/jenkins"

# Get SonarQube URL
SONARQUBE_IP=$(kubectl get svc sonarqube-service -n sonarqube -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "SonarQube: http://${SONARQUBE_IP}:9000"
```

### Step 5: Run the Pipeline

1. Access Jenkins: `http://${JENKINS_IP}:8080/jenkins`
2. Click on `python-code-analysis`
3. Click **"Build Now"** to trigger the pipeline
4. View results in the console output

### Step 6: Configure GitHub Webhook

To automatically trigger builds on code push:

1. In GitHub: **Settings** → **Webhooks** → **Add webhook**
2. Configure:
   - **Payload URL**: `http://${JENKINS_IP}:8080/github-webhook/`
   - **Content type**: `application/json`
   - **Events**: "Just the push event"
3. Click **"Add webhook"**

## Viewing Results

### Method 1: Jenkins Console
- Go to pipeline job → Build number → **Console Output**
- Scroll to **"Display Hadoop Results"** stage

### Method 2: Python Script
```bash
cd scripts
python3 view-results.py
```

## Expected Behavior

- **With Blocker Issues**: Pipeline runs, SonarQube detects blockers, Hadoop job is **SKIPPED**
- **No Blocker Issues**: Pipeline runs, SonarQube passes, Hadoop job **RUNS** and displays line counts

## Cleanup

To destroy all resources:
```bash
cd terraform
terraform destroy
```
