# Code Walkthrough Script
## Jenkinsfile and Supporting Scripts

**Duration:** 8-10 minutes  
**Purpose:** Explain the pipeline architecture and implementation

---

## Introduction (0:00 - 0:30)

**What to Say:**
> "I'll walk through the Jenkinsfile that implements our CI/CD pipeline. This pipeline analyzes code quality with SonarQube and conditionally executes a Hadoop MapReduce job based on blocker issues. Let me start with the overall structure."

**What to Show:**
- [ ] Open Jenkinsfile in editor
- [ ] Show the file structure (462 lines)
- [ ] Explain: "This is a declarative Jenkins pipeline with multiple stages"

---

## Part 1: Pipeline Structure & Environment Variables (0:30 - 2:00)

### Lines 1-13: Pipeline Declaration & Environment

**What to Say:**
> "The pipeline starts with the pipeline block and defines environment variables that are used throughout. These come from the Kubernetes deployment configuration."

**What to Show:**
```groovy
pipeline {
    agent any
    
    environment {
        GCP_PROJECT_ID = "${env.GCP_PROJECT_ID}"
        HADOOP_CLUSTER_NAME = "${env.HADOOP_CLUSTER_NAME}"
        HADOOP_REGION = "${env.HADOOP_REGION}"
        SONARQUBE_URL = "${env.SONARQUBE_URL}"
        SONARQUBE_TOKEN = "${env.SONARQUBE_TOKEN ?: ''}"
        OUTPUT_BUCKET = "${env.OUTPUT_BUCKET}"
        STAGING_BUCKET = "${env.STAGING_BUCKET}"
        REPO_GCS_PATH = "gs://${OUTPUT_BUCKET}/repo-code"
    }
```

**Key Points:**
- `agent any` - Runs on any available Jenkins agent
- Environment variables are injected from Kubernetes
- `REPO_GCS_PATH` is constructed from `OUTPUT_BUCKET`
- `SONARQUBE_TOKEN` uses Groovy's `?:` operator for default empty string

---

## Part 2: Stage 1 - Checkout (2:00 - 2:30)

### Lines 16-21: Checkout Stage

**What to Say:**
> "The first stage checks out the code from GitHub. This uses the SCM configuration from the Jenkins job."

**What to Show:**
```groovy
stage('Checkout') {
    steps {
        echo 'Checking out code from GitHub...'
        checkout scm
    }
}
```

**Key Points:**
- `checkout scm` uses the repository URL configured in Jenkins job
- This gets the latest code including the Jenkinsfile itself

---

## Part 3: Stage 2 - Setup GCloud SDK (2:30 - 4:00)

### Lines 23-78: GCloud SDK Setup

**What to Say:**
> "This stage ensures the Google Cloud SDK is installed and authenticated. It uses Workload Identity for secure authentication without service account keys."

**What to Show:**
```groovy
stage('Setup GCloud SDK') {
    steps {
        script {
            // Check if gcloud is installed
            def gcloudInstalled = sh(script: 'command -v gcloud || echo "not_found"', returnStdout: true).trim()
            
            if (gcloudInstalled == 'not_found') {
                // Install gcloud SDK
                // ... installation script ...
            }
            
            // Configure and authenticate
            gcloud config set project ${GCP_PROJECT_ID}
            gcloud auth application-default print-access-token
        }
    }
}
```

**Key Points:**
- Checks for existing installation to avoid re-downloading
- Downloads and installs gcloud SDK if needed
- Uses `gcloud auth application-default` for Workload Identity
- Adds gcloud to PATH for subsequent stages

---

## Part 4: Stage 3 - SonarQube Analysis (4:00 - 5:00)

### Lines 80-115: SonarQube Analysis

**What to Say:**
> "This stage runs SonarQube code analysis. It downloads the SonarQube scanner and runs it against our codebase."

**What to Show:**
```groovy
stage('SonarQube Analysis') {
    steps {
        script {
            // Download SonarQube Scanner
            SCAN_VERSION="5.0.1.3006"
            curl -L -s -o scanner.zip https://binaries.sonarsource.com/...
            unzip scanner.zip
            
            // Build scanner command
            SCANNER_CMD="./sonar-scanner-.../bin/sonar-scanner \
                -Dsonar.projectKey=Python-Code-Disasters \
                -Dsonar.sources=. \
                -Dsonar.host.url=${SONARQUBE_URL} \
                -Dsonar.qualitygate.wait=false"
            
            // Add authentication (token or admin:admin)
            if [ -n "${SONARQUBE_TOKEN:-}" ]; then
                SCANNER_CMD="${SCANNER_CMD} -Dsonar.login=${SONARQUBE_TOKEN}"
            else
                SCANNER_CMD="${SCANNER_CMD} -Dsonar.login=admin -Dsonar.password=admin"
            fi
            
            // Run analysis
            ${SCANNER_CMD}
        }
    }
}
```

**Key Points:**
- Downloads scanner dynamically (no pre-installation needed)
- Uses token authentication if available, falls back to admin:admin
- `-Dsonar.qualitygate.wait=false` - doesn't wait for quality gate (we check blockers separately)
- Analysis results are uploaded to SonarQube server

---

## Part 5: Stage 4 - Blocker Check & Decision Logic (5:00 - 7:00)

### Lines 117-273: Wait for Processing & Check Blockers

**What to Say:**
> "This is the critical stage that determines whether to run Hadoop. It waits for SonarQube to process the analysis, then checks for blocker issues."

**What to Show:**

#### A. Task ID Extraction (Lines 122-135)
```groovy
// Get the CE task ID from the report-task.txt file
def taskId = null
def taskReportFile = '.scannerwork/report-task.txt'

try {
    def reportContent = sh(script: "cat ${taskReportFile}", returnStdout: true).trim()
    def taskIdMatch = (reportContent =~ /ceTaskId=([^\n]+)/)
    if (taskIdMatch) {
        taskId = taskIdMatch[0][1]
    }
} catch (Exception e) {
    echo "⚠ Could not read task ID from report file"
}
```

**Key Points:**
- Extracts task ID from SonarQube scanner output
- Uses regex to parse the task ID
- This ID is used to check when SonarQube finishes processing

#### B. Authentication Setup (Lines 140-155)
```groovy
def SONAR_AUTH = ""

if (env.SONARQUBE_TOKEN && !env.SONARQUBE_TOKEN.isEmpty()) {
    SONAR_AUTH = "${env.SONARQUBE_TOKEN}:"
} else {
    SONAR_AUTH = "admin:admin"
}
```

**Key Points:**
- Prefers token authentication
- Falls back to admin:admin if token not set
- Token format: `token:` (colon needed for curl basic auth)

#### C. Wait for Processing (Lines 164-204)
```groovy
while (totalWaitTime < maxWaitTime && taskStatus != 'SUCCESS' && taskStatus != 'FAILED') {
    sleep(time: waitInterval, unit: 'SECONDS')
    totalWaitTime += waitInterval
    
    def taskResponse = sh(
        script: """
            curl -s -u ${SONAR_AUTH} \
            '${SONARQUBE_URL}/api/ce/task?id=${taskId}'
        """,
        returnStdout: true
    ).trim()
    
    def statusMatch = (taskResponse =~ /"status":"([^"]+)"/)
    if (statusMatch) {
        taskStatus = statusMatch[0][1]
    }
}
```

**Key Points:**
- Polls SonarQube API every 10 seconds
- Waits up to 5 minutes for processing
- Uses regex to extract status from JSON response
- Only proceeds when status is SUCCESS

#### D. Blocker Count Check (Lines 206-244) - **CRITICAL SECTION**

**What to Say:**
> "This is the core decision logic. We query SonarQube's API for blocker issues and count them."

**What to Show:**
```groovy
echo '📊 Checking Blocker Issues...'

def blockerCount = 'UNKNOWN'
def maxRetries = 5
def retryDelay = 10

for (int i = 0; i < maxRetries; i++) {
    try {
        // Query SonarQube API for blocker issues
        def blockerResponse = sh(
            script: """
                curl -s -u ${SONAR_AUTH} \
                '${SONARQUBE_URL}/api/issues/search?componentKeys=Python-Code-Disasters&severities=BLOCKER&resolved=false'
            """,
            returnStdout: true
        ).trim()
        
        // Parse the JSON response to extract total count
        def blockerMatch = blockerResponse =~ /"total"\s*:\s*(\d+)/
        if (blockerMatch) {
            blockerCount = blockerMatch[0][1]
            break  // Got valid response, exit loop
        }
    } catch (Exception e) {
        // Retry on error
        if (i < maxRetries - 1) {
            sleep(time: retryDelay, unit: 'SECONDS')
        }
    }
}
```

**Key Points:**
- API endpoint: `/api/issues/search`
- Parameters:
  - `componentKeys=Python-Code-Disasters` - our project
  - `severities=BLOCKER` - only blocker severity
  - `resolved=false` - only unresolved issues
- Uses regex to extract `"total": X` from JSON
- Retries up to 5 times if API call fails

#### E. Decision Logic (Lines 249-267) - **THE CORE LOGIC**

**What to Say:**
> "Here's the decision logic. We ONLY check blocker count - quality gate is ignored. If blockers = 0, we run Hadoop. Otherwise, we skip it."

**What to Show:**
```groovy
// Decision logic: Only run Hadoop if no blocker issues
if (blockerCount == 'UNKNOWN') {
    echo "⚠️  Blockers: ${blockerCount} (unknown)"
    echo "   → SKIP Hadoop (incomplete data)"
    env.RUN_HADOOP_JOB = 'false'
} else if (blockerCount != '0') {
    echo "✗ Blockers: ${blockerCount}"
    echo "   → SKIP Hadoop"
    env.RUN_HADOOP_JOB = 'false'
} else {
    echo "✓ Blockers: ${blockerCount}"
    echo "   → RUN Hadoop"
    env.RUN_HADOOP_JOB = 'true'
}
```

**Key Points:**
- **Three scenarios:**
  1. `UNKNOWN` → Skip (fail-safe)
  2. `> 0` → Skip (blockers present)
  3. `= 0` → Run (no blockers)
- Sets `env.RUN_HADOOP_JOB` environment variable
- This variable controls subsequent stages via `when` conditions
- **Important:** Quality gate status is NOT checked - only blocker count

---

## Part 6: Stage 5 - Upload Code to GCS (7:00 - 7:30)

### Lines 275-314: Upload Stage

**What to Say:**
> "If blockers = 0, we upload the repository code to Google Cloud Storage so Hadoop can process it."

**What to Show:**
```groovy
stage('Upload Code to GCS') {
    when {
        environment name: 'RUN_HADOOP_JOB', value: 'true'
    }
    steps {
        script {
            // Copy all files (excluding .git, .terraform, etc.)
            find . -type f \
                ! -path './.git/*' \
                ! -path './.terraform/*' \
                ! -path './.scannerwork/*' \
                ! -name '*.pyc' \
                -exec cp --parents {} /tmp/repo-upload/ \;
            
            // Upload to GCS
            gcloud storage cp -r /tmp/repo-upload/* ${REPO_GCS_PATH}/
        }
    }
}
```

**Key Points:**
- `when` condition: Only runs if `RUN_HADOOP_JOB == 'true'`
- Excludes unnecessary files (.git, .terraform, .pyc, etc.)
- Uses `--parents` flag to preserve directory structure
- Uploads to: `gs://${OUTPUT_BUCKET}/repo-code`

---

## Part 7: Stage 6 - Execute Hadoop MapReduce Job (7:30 - 9:00)

### Lines 316-401: Hadoop Job Execution

**What to Say:**
> "This stage creates a PySpark script and submits it to Dataproc. The script counts lines in each file."

**What to Show:**

#### A. Job Script Creation (Lines 343-381)

**What to Say:**
> "The PySpark script is embedded in the Jenkinsfile as a heredoc. Let me explain the key parts."

**What to Show:**
```python
from pyspark import SparkContext
import sys

if __name__ == "__main__":
    input_path = sys.argv[1]  # GCS path: gs://bucket/repo-code
    output_path = sys.argv[2]  # GCS path: gs://bucket/results/timestamp
    
    sc = SparkContext(appName="Repository File Line Counter")
    
    # Read root-level and subdirectory files, then union
    root_files = sc.wholeTextFiles(input_path + "/*")
    subdir_files = sc.wholeTextFiles(input_path + "/**/*")
    files_rdd = root_files.union(subdir_files).distinct()
```

**Key Points:**
- `wholeTextFiles()` reads entire file contents (not line-by-line)
- Pattern `/*` matches root-level files
- Pattern `/**/*` matches all subdirectory files
- `.union().distinct()` combines both and removes duplicates
- **Why union?** The `**/*` pattern doesn't match root files, so we need both

**What to Show:**
```python
def process_file(file_tuple):
    filepath, content = file_tuple
    # Extract relative path from GCS path
    if 'repo-code/' in filepath:
        relative_path = filepath.split('repo-code/')[-1]
    else:
        relative_path = filepath.split('/')[-1]
    line_count = len(content.splitlines())
    return (relative_path, line_count)
```

**Key Points:**
- `file_tuple` is `(filepath, content)` from `wholeTextFiles()`
- Extracts just the filename (removes GCS path prefix)
- `splitlines()` handles all line ending types (Windows, Unix, Mac)
- Returns `(filename, line_count)` tuple

**What to Show:**
```python
def format_output(filename_count):
    filename, count = filename_count
    return f'"{filename}": {count}'

line_counts = files_rdd.map(process_file)
sorted_counts = line_counts.sortByKey()
formatted_output = sorted_counts.map(format_output)
formatted_output.saveAsTextFile(output_path)
```

**Key Points:**
- `.map(process_file)` - processes each file
- `.sortByKey()` - sorts by filename alphabetically
- `.map(format_output)` - formats as `"filename": count`
- `saveAsTextFile()` - saves to GCS in the required format

#### B. Job Submission (Lines 383-390)
```groovy
gcloud storage cp /tmp/line_counter_job.py gs://${STAGING_BUCKET}/jobs/line_counter_job.py

gcloud dataproc jobs submit pyspark \
    gs://${STAGING_BUCKET}/jobs/line_counter_job.py \
    --cluster=${HADOOP_CLUSTER_NAME} \
    --region=${HADOOP_REGION} \
    --project=${GCP_PROJECT_ID} \
    -- ${REPO_GCS_PATH} ${outputPath}
```

**Key Points:**
- Uploads script to GCS staging bucket
- Submits job to Dataproc cluster
- Passes input and output paths as arguments
- Uses Workload Identity automatically (no service account keys)

---

## Part 8: Stage 7 - Display Results (9:00 - 9:30)

### Lines 403-429: Results Display

**What to Say:**
> "After the Hadoop job completes, we fetch and display the results in the Jenkins console."

**What to Show:**
```groovy
stage('Display Hadoop Results') {
    when {
        environment name: 'RUN_HADOOP_JOB', value: 'true'
    }
    steps {
        script {
            sh """
                echo "📈 Line counts for Python files:"
                echo ""
                
                # Fetch and display results
                gcloud storage cat ${HADOOP_OUTPUT_PATH}/part-* 2>/dev/null
                
                echo ""
                echo "Results saved to: ${HADOOP_OUTPUT_PATH}"
            """
        }
    }
}
```

**Key Points:**
- Reads all `part-*` files from GCS (Hadoop output format)
- Displays in Jenkins console
- Shows GCS path where results are stored
- Results format: `"filename": line_count` (one per line)

---

## Part 9: Stage 8 - Summary (9:30 - 9:45)

### Lines 431-447: Results Summary

**What to Show:**
```groovy
stage('Results Summary') {
    steps {
        script {
            echo "Blockers: ${env.BLOCKER_COUNT ?: 'N/A'}"
            echo "Hadoop Job: ${env.RUN_HADOOP_JOB == 'true' ? 'EXECUTED' : 'SKIPPED'}"
            if (env.RUN_HADOOP_JOB == 'true' && env.HADOOP_OUTPUT_PATH) {
                echo "Output: ${env.HADOOP_OUTPUT_PATH}"
            }
        }
    }
}
```

**Key Points:**
- Always runs (no `when` condition)
- Shows final summary of pipeline execution
- Uses ternary operator for concise output

---

## Part 10: Supporting Scripts (9:45 - 11:00)

### Script 1: deploy-all.sh

**What to Say:**
> "Let me show the deployment script that sets up all infrastructure."

**What to Show:**
- [ ] Open `scripts/deploy-all.sh`
- [ ] Explain it automates:
  - Terraform apply
  - kubectl configuration
  - Waiting for services
  - Displaying URLs

### Script 2: view-results.py

**What to Say:**
> "This utility script helps view Hadoop results from the command line."

**What to Show:**
- [ ] Open `scripts/view-results.py`
- [ ] Explain it:
  - Lists available results in GCS
  - Downloads and displays latest results
  - Formats output nicely

### Script 3: jenkins-init-sonarqube.groovy

**What to Say:**
> "This Groovy script runs when Jenkins starts to configure SonarQube connection automatically."

**What to Show:**
- [ ] Explain it:
  - Reads `SONARQUBE_TOKEN` from environment
  - Creates Jenkins credential
  - Configures SonarQube server in Jenkins

---

## Part 11: Key Design Decisions (11:00 - 12:00)

**What to Say:**
> "Let me highlight some key design decisions in this pipeline."

### Decision 1: Blocker-Only Check
- **Why:** Requirements specify only blocker count matters
- **Implementation:** Only queries `/api/issues/search` with `severities=BLOCKER`
- **Not checked:** Quality gate status

### Decision 2: Conditional Execution
- **Why:** Cost optimization - Hadoop is expensive
- **Implementation:** Uses `when` conditions based on `RUN_HADOOP_JOB` env var
- **Result:** Stages are skipped if blockers > 0

### Decision 3: Workload Identity
- **Why:** Security best practice - no service account keys
- **Implementation:** Uses `gcloud auth application-default`
- **Benefit:** Automatic authentication via Kubernetes service account

### Decision 4: Dynamic Scanner Download
- **Why:** No pre-installation needed, always latest version
- **Implementation:** Downloads scanner in pipeline stage
- **Benefit:** Self-contained, no Jenkins tool configuration

### Decision 5: Results Format
- **Why:** Requirements specify `"filename": count` format
- **Implementation:** PySpark formats output with f-string
- **Result:** Standardized, parseable output

---

## Part 12: Error Handling & Edge Cases (12:00 - 12:30)

**What to Say:**
> "The pipeline includes several error handling mechanisms."

**What to Show:**

1. **Task Status Polling** (Lines 167-190)
   - Waits up to 5 minutes
   - Handles timeouts gracefully
   - Falls back to 60-second wait if task ID missing

2. **Blocker API Retries** (Lines 212-244)
   - Retries up to 5 times
   - Handles API failures
   - Defaults to `UNKNOWN` if all retries fail

3. **Fail-Safe Mode** (Lines 255-258)
   - If blocker count is `UNKNOWN` → Skip Hadoop
   - Prevents false positives
   - Safe default behavior

---

## Closing (12:30 - 13:00)

**What to Say:**
> "This pipeline demonstrates a production-ready CI/CD solution that intelligently manages compute resources based on code quality. The key innovation is using blocker count as the sole decision factor, which provides a clear, binary decision point for expensive operations."

**Summary Points:**
- ✅ Automated code quality analysis
- ✅ Blocker-based decision logic
- ✅ Conditional Hadoop execution
- ✅ Cloud-native architecture
- ✅ Secure authentication
- ✅ Standardized output format

---

## Code Walkthrough Checklist

- [ ] Jenkinsfile open in editor
- [ ] Terminal ready for commands
- [ ] Browser tabs:
  - [ ] Jenkins (for showing pipeline runs)
  - [ ] SonarQube (for showing analysis)
  - [ ] GitHub (for showing repository)
- [ ] GCS bucket accessible (for showing results)
- [ ] Key sections highlighted:
  - [ ] Environment variables
  - [ ] Blocker check logic
  - [ ] Decision logic
  - [ ] Hadoop job script
  - [ ] Results display

---

## Tips for Recording

1. **Use syntax highlighting** - Makes code easier to follow
2. **Zoom in on critical sections** - Especially the decision logic
3. **Explain the flow** - How data moves between stages
4. **Show examples** - Actual API responses, output formats
5. **Pause at complex parts** - Regex parsing, RDD operations
6. **Highlight key variables** - `RUN_HADOOP_JOB`, `BLOCKER_COUNT`

---

## Expected Duration: 10-12 minutes

