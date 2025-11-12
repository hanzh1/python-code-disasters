# python-code-disasters

## Project Overview

This repository contains examples of Python code that demonstrate various anti-patterns and code quality issues. Additionally, this repository has been configured with a complete CI/CD pipeline that demonstrates:

- **Jenkins** and **SonarQube** integration for static code analysis
- **Hadoop MapReduce** job execution based on code quality gates
- **Terraform** infrastructure as code for cloud deployment
- **GKE** (Google Kubernetes Engine) for container orchestration
- **Dataproc** for Hadoop cluster management

## CI/CD Pipeline Architecture

The pipeline implements the following workflow:

1. **Code Change Detection**: GitHub webhook triggers Jenkins on code commits
2. **Static Code Analysis**: SonarQube analyzes the code for quality issues
3. **Quality Gate Check**: Pipeline checks for blocker issues and quality gate status
4. **Conditional Hadoop Execution**: 
   - ✅ If no blocker issues → Run Hadoop MapReduce job
   - ❌ If blocker issues found → Skip Hadoop job
5. **Results Display**: Hadoop job results are displayed and stored in GCS

### Infrastructure Components

- **Jenkins & SonarQube**: Deployed on GKE cluster
- **Hadoop Cluster**: Deployed on Dataproc (1 master, 2 workers)
- **Storage**: GCS buckets for staging and output
- **Authentication**: Workload Identity for secure GCP access

---

## Prerequisites

Before deploying, ensure you have:

1. **Google Cloud Platform Account** with billing enabled
2. **GCP Project** with the following APIs enabled:
   - Compute Engine API
   - Kubernetes Engine API
   - Dataproc API
   - Cloud Storage API
3. **Required Tools Installed**:
   - `gcloud` CLI ([Installation Guide](https://cloud.google.com/sdk/docs/install))
   - `terraform` (>= 1.0) ([Installation Guide](https://www.terraform.io/downloads))
   - `kubectl` ([Installation Guide](https://kubernetes.io/docs/tasks/tools/))
   - `git`

4. **GitHub Repository**: Fork this repository to your GitHub account

---

## Deployment Instructions

**Note**: This deployment is **fully automated**. After running Terraform, you only need to run **one setup script** to complete the Jenkins-SonarQube pipeline connection (no manual logins or passwords required).

### Step 1: Configure Terraform Variables

1. Copy the example terraform variables file:
   ```bash
   cd terraform
   cp terraform.tfvars.example terraform.tfvars
   ```

2. Edit `terraform.tfvars` with your values:
   ```hcl
   project_id = "your-gcp-project-id"
   region = "us-central1"
   zone = "us-central1-a"
   github_repo_url = "https://github.com/your-username/python-code-disasters"
   github_webhook_secret = "your-secure-random-string-here"
   ```

   **Note for Teams**: 
   - **Each team member with their own GCP account** needs to:
     - Use their own `project_id` (different for each person)
     - Deploy their own infrastructure (separate clusters)
     - Configure their own Jenkins and SonarQube instances
   - **Repository URL options**:
     - **Option A**: All use the same shared fork URL (e.g., one person's fork that everyone pushes to)
     - **Option B**: Each person uses their own fork URL
   - The `github_repo_url` variable is for reference only; the actual repo is configured in Jenkins UI (Step 9)

### Step 2: Authenticate with GCP

```bash
gcloud auth login
gcloud config set project YOUR_PROJECT_ID
gcloud auth application-default login
```

### Step 3: Enable Required APIs

```bash
gcloud services enable compute.googleapis.com
gcloud services enable container.googleapis.com
gcloud services enable dataproc.googleapis.com
gcloud services enable storage.googleapis.com
```

### Step 4: Deploy Infrastructure

**Option A: Automated Deployment Script**

```bash
cd scripts
chmod +x deploy-all.sh
./deploy-all.sh
```


This will create:
- GKE cluster for Jenkins and SonarQube
- Dataproc Hadoop cluster (1 master, 2 workers)
- GCS buckets for staging and output
- Service accounts with appropriate IAM roles
- Network and firewall rules

**Deployment takes approximately 10-15 minutes.**

### Step 5: Configure kubectl

After Terraform completes, configure kubectl:

```bash
gcloud container clusters get-credentials jenkins-sonarqube-cluster \
    --zone us-central1-a \
    --project YOUR_PROJECT_ID
```

### Step 6: Wait for Services to be Ready

Wait for Jenkins and SonarQube to be fully deployed:

```bash
# Check Jenkins
kubectl wait --for=condition=available --timeout=300s deployment/jenkins -n jenkins

# Check SonarQube
kubectl wait --for=condition=available --timeout=300s deployment/sonarqube -n sonarqube

# Wait for LoadBalancer IPs (may take 2-3 minutes)
kubectl get svc -n jenkins
kubectl get svc -n sonarqube
```

### Step 7: Get Service URLs

```bash
# Get Jenkins URL
JENKINS_IP=$(kubectl get svc jenkins-service -n jenkins -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "Jenkins URL: http://${JENKINS_IP}:8080"

# Get SonarQube URL
SONARQUBE_IP=$(kubectl get svc sonarqube-service -n sonarqube -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "SonarQube URL: http://${SONARQUBE_IP}:9000"
```

### Step 8: SonarQube Token Configuration

**Token is configured directly in Terraform:**

The SonarQube API token is hardcoded in `terraform/kubernetes-jenkins.tf` as an environment variable. When you run `terraform apply`, the token is automatically set in Jenkins.

**If you need to update the token:**
1. Generate a new token in SonarQube UI (if needed)
2. Update `terraform/kubernetes-jenkins.tf` with the new token
3. Run `terraform apply` to update Jenkins deployment

**Note**: Password change can be done manually if needed. Token generation and Jenkins configuration are fully automated.

**Note**: For restarting after billing is disabled, see `QUICK_START_AFTER_BILLING.md`.

### Step 9: (Optional) Configure GitHub Webhook for Auto-Trigger

To automatically trigger Jenkins builds on code pushes:

1. In your GitHub repository: **Settings** → **Webhooks** → **Add webhook**
2. Configure:
   - **Payload URL**: `http://${JENKINS_IP}:8080/github-webhook/`
   - **Content type**: `application/json`
   - **Secret**: (get from `terraform/terraform.tfvars` - the `github_webhook_secret` value)
   - **Events**: Select **"Just the push event"**
   - **Active**: ✓
3. Click **"Add webhook"**

### Step 10: Verify Setup

1. **Check SonarQube**:
   - Access: `http://${SONARQUBE_IP}:9000`
   - Login: `admin` / `admin123`
   - Verify project exists: `Python-Code-Disasters`

2. **Check Jenkins**:
   - Access: `http://${JENKINS_IP}:8080`
   - Verify pipeline job exists: `python-code-disasters-pipeline`
   - Verify SonarQube server is configured (Manage Jenkins → Configure System)

3. **Test the Pipeline**:
   - In Jenkins, click **"Build Now"** on the pipeline job
   - Watch the console output to see the pipeline execute

**Note**: All environment variables are set automatically via the Kubernetes deployment. No manual configuration needed.

---

## Testing the Pipeline

### Scenario 1: Code with Blocker Issues (Hadoop Should NOT Run)

1. **Create a Python file with blocker issues**:
   ```python
   # test_blocker.py
   import os
   password = "hardcoded_password_123"  # Security hotspot
   eval(input())  # Code injection vulnerability
   ```

2. **Commit and push**:
   ```bash
   git add test_blocker.py
   git commit -m "Add file with blocker issues"
   git push origin master
   ```

3. **Expected Result**:
   - Jenkins pipeline triggers
   - SonarQube detects blocker issues
   - Pipeline shows: `✗ Blocker Issues Detected`
   - Hadoop job is **SKIPPED**

### Scenario 2: Clean Code (Hadoop Should Run)

1. **Fix blocker issues** or use existing clean files
2. **Commit and push**:
   ```bash
   git add .
   git commit -m "Fix blocker issues"
   git push origin master
   ```

3. **Expected Result**:
   - Jenkins pipeline triggers
   - SonarQube analysis completes
   - Quality Gate: `OK`
   - Blocker Issues: `0`
   - Hadoop job **RUNS**
   - Results displayed in Jenkins console

---

## Viewing Hadoop Job Results

### Method 1: Jenkins Console Output

The pipeline automatically displays results in the Jenkins console during the "Display Hadoop Results" stage.

### Method 2: Command Line Script

Use the provided script to view results:

```bash
cd scripts
python3 scripts/view-results.py [optional_output_path]
```

If no path is provided, it shows the latest results.

### Method 3: Python Script

```bash
cd scripts
python3 view-results.py [optional_output_path]
```

### Method 4: Direct GCS Access

```bash
# List all results
gsutil ls gs://${PROJECT_ID}-hadoop-output/results/

# View latest results
LATEST=$(gsutil ls gs://${PROJECT_ID}-hadoop-output/results/ | tail -1)
gsutil cat ${LATEST}part-*
```

### Method 5: GCP Console

1. Go to [GCP Console](https://console.cloud.google.com)
2. Navigate to "Cloud Storage" → "Buckets"
3. Open `${PROJECT_ID}-hadoop-output`
4. Navigate to `results/` folder
5. Open the latest timestamped folder
6. Download and view `part-*` files

---

## Project Structure

```
python-code-disasters/
├── Jenkinsfile                 # Jenkins pipeline definition
├── sonar-project.properties    # SonarQube configuration
├── terraform/                  # Infrastructure as code
│   ├── provider.tf
│   ├── variables.tf
│   ├── jenkins-sonarqube-cluster.tf
│   ├── hadoop-cluster.tf
│   ├── kubernetes-jenkins.tf
│   ├── kubernetes-sonarqube.tf
│   ├── jenkins-gcp-iam.tf
│   └── outputs.tf
├── scripts/                    # Deployment and utility scripts
│   ├── deploy-all.sh
│   ├── (token configured in Terraform)
│   └── view-results.py
├── hadoop-jobs/               # Hadoop MapReduce jobs
│   └── line_counter.py
└── python/                    # Sample Python code files
    └── ...
```

---

## Troubleshooting

### Jenkins Cannot Connect to SonarQube

- Verify SonarQube service is running: `kubectl get pods -n sonarqube`
- Check service URL in Jenkins configuration
- Verify credentials are set correctly

### Hadoop Job Fails

- Check Dataproc cluster status: `gcloud dataproc clusters describe hadoop-cluster --region=us-central1`
- Verify GCS buckets exist and are accessible
- Check Jenkins service account has proper IAM roles

### Quality Gate Always Fails

- Check SonarQube project settings
- Review quality gate conditions
- Consider adjusting quality gate thresholds for testing

### LoadBalancer IP Not Assigned

- Wait 2-5 minutes after service creation
- Check quota limits for LoadBalancers in your region
- Verify firewall rules allow traffic

---

## Cleanup

To destroy all resources:

```bash
cd terraform
terraform destroy
```

**Warning**: This will delete all infrastructure, including persistent volumes with Jenkins and SonarQube data.

---

## Assumptions

1. **GCP Project**: You have a GCP project with billing enabled
2. **Region**: Default region is `us-central1`, zone is `us-central1-a` (configurable in terraform.tfvars)
3. **Network**: Terraform creates a new VPC network (can be modified to use existing)
4. **SonarQube**: Default credentials are `admin/admin` (change after first login)
5. **Quality Gate**: Pipeline checks for blocker issues; quality gate failures also prevent Hadoop execution
6. **Hadoop Output Format**: Results are stored as `"filename": line_count` in GCS

---

## Important Notes

- **Workload Identity**: Jenkins uses Workload Identity for secure GCP authentication (no service account keys needed)
- **Persistent Storage**: Jenkins and SonarQube data persist in PVCs (20GB each)
- **Cost Considerations**: Running GKE and Dataproc clusters incurs costs. Destroy resources when not in use.
- **Security**: 
  - Change default SonarQube password
  - Use strong GitHub webhook secrets
  - Review IAM roles and permissions

---

## Original Repository Information

### What is it all about?
I am, due to my work, seeing a lot of code written by other developers. Sometimes this code is so bad, that it is worth showing to the outer world.

### Privacy
Privacy is very important. There are two things basically: 

1. Refactor your code to remove anything, that might violate any security requirements, corporate rules or license agreements.
2. It is not a goal of this project to insult or offend anyone, so, please, remove any brand-names, user marks, `__author__` variables and so on.

### Save yourself! 
Do you want to save yourself and your project from a `python` code disaster? 
Then use [`wemake-python-styleguide`](https://github.com/wemake-services/wemake-python-styleguide) which is the strictest `python` linter in existance. 
With this tool all your code will be awesome!

### Contributing
Feel free to contribute. Before contributing, please, double check the [Privacy](#privacy) section.
Refactor your code to remove as much as you can to leave just the most valuable parts. I think that submitting a broken code is not an issue for this project. Moreover, formatting the code is also not required. Sometimes it is even better to leave it's formation untouched.

It is generally a good practice to read through your old files and contribute your own code.

### Keywords
Python bad code examples, Python antipatterns

---

## Team Members

[Add your team member names here]

**Team Setup Notes (Separate GCP Accounts)**:
- **Each team member must deploy their own infrastructure**:
  - Each person has their own GCP project (`project_id` will be different)
  - Each person runs `terraform apply` to create their own:
    - GKE cluster (Jenkins & SonarQube)
    - Dataproc cluster (Hadoop)
    - GCS buckets
  - Each person configures their own Jenkins and SonarQube instances
  
- **Repository options**:
  - **Shared Fork**: All team members use the same `github_repo_url` (one person's fork that everyone pushes to)
    - Each person's Jenkins will independently monitor the same repository
    - Each person can test their own infrastructure with the same codebase
  - **Individual Forks**: Each person uses their own fork URL
    - Each person's Jenkins monitors their own fork
  
- **Important**: The `github_repo_url` in terraform.tfvars is for reference; the actual repository is configured in Jenkins UI (Step 9)

---

## License

[Add license information if applicable]
# Test polling Mon Nov 10 14:31:30 PST 2025
