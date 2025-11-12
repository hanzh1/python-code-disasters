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
    
    stages {
        stage('Checkout') {
            steps {
                echo 'Checking out code from GitHub...'
                checkout scm
            }
        }
        
        stage('Setup GCloud SDK') {
            steps {
                script {
                    echo 'Checking for gcloud SDK...'
                    def gcloudInstalled = sh(script: 'command -v gcloud || echo "not_found"', returnStdout: true).trim()
                    
                    if (gcloudInstalled == 'not_found') {
                        echo 'Installing gcloud SDK (this may take a few minutes on first run)...'
                        sh '''
                            set -e
                            # Install to user directory if not root
                            export CLOUD_SDK_DIR=/var/jenkins_home/google-cloud-sdk
                            
                            if [ ! -d "$CLOUD_SDK_DIR" ]; then
                                echo "Downloading gcloud SDK..."
                                cd /var/jenkins_home
                                curl -O https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-sdk-459.0.0-linux-x86_64.tar.gz
                                tar -xzf google-cloud-sdk-459.0.0-linux-x86_64.tar.gz
                                rm google-cloud-sdk-459.0.0-linux-x86_64.tar.gz
                                
                                echo "Installing gcloud SDK..."
                                ./google-cloud-sdk/install.sh --quiet --usage-reporting=false --path-update=false
                            fi
                            
                            # Add to PATH for this session
                            export PATH=$CLOUD_SDK_DIR/bin:$PATH
                            
                            # Verify installation
                            gcloud version
                            gsutil version
                        '''
                        echo '✓ gcloud SDK installed successfully'
                    } else {
                        echo '✓ gcloud SDK already installed'
                        sh 'gcloud version'
                    }
                    
                    // Add gcloud to PATH for subsequent stages
                    env.PATH = "/var/jenkins_home/google-cloud-sdk/bin:${env.PATH}"
                    
                    // Configure gcloud with project and authenticate with Workload Identity
                    sh """
                        set -e
                        echo "Configuring gcloud SDK..."
                        gcloud config set project ${GCP_PROJECT_ID} > /dev/null 2>&1
                        
                        # Authenticate using Application Default Credentials
                        if gcloud auth application-default print-access-token > /dev/null 2>&1; then
                            echo "✓ GCP authenticated (Workload Identity)"
                        else
                            echo "⚠ GCP auth check failed (will retry when needed)"
                        fi
                    """
                }
            }
        }
        
        stage('SonarQube Analysis') {
            steps {
                script {
                    echo 'Running SonarQube analysis...'
                    
                    // Download and use SonarQube Scanner CLI (no tool configuration needed)
                    sh """
                        set -eu
                        SCAN_VERSION="5.0.1.3006"
                        echo "Downloading scanner..."
                        curl -L -s -o scanner.zip https://binaries.sonarsource.com/Distribution/sonar-scanner-cli/sonar-scanner-cli-\${SCAN_VERSION}-linux.zip
                        unzip -q -o scanner.zip > /dev/null 2>&1
                        
                        # Build scanner command - use token if available, otherwise use admin:admin
                        SCANNER_CMD="./sonar-scanner-\${SCAN_VERSION}-linux/bin/sonar-scanner \
                            -Dsonar.projectKey=Python-Code-Disasters \
                            -Dsonar.sources=. \
                            -Dsonar.host.url=\${SONARQUBE_URL} \
                            -Dsonar.python.version=3.8,3.9,3.10 \
                            -Dsonar.language=py \
                            -Dsonar.qualitygate.wait=false"
                        
                        # Add authentication - prefer token, fallback to username/password
                        if [ -n "\${SONARQUBE_TOKEN:-}" ]; then
                            SCANNER_CMD="\${SCANNER_CMD} -Dsonar.login=\${SONARQUBE_TOKEN}"
                        else
                            SCANNER_CMD="\${SCANNER_CMD} -Dsonar.login=admin -Dsonar.password=admin"
                        fi
                        
                        echo "Running analysis..."
                        \${SCANNER_CMD} > /dev/null 2>&1 || true
                        echo "✓ Analysis completed"
                    """
                }
            }
        }
        
        stage('Wait for SonarQube Processing & Check Quality Gate') {
            steps {
                script {
                    echo '⏳ Processing analysis results...'
                    
                    // Get the CE task ID from the report-task.txt file
                    def taskId = null
                    def taskReportFile = '.scannerwork/report-task.txt'
                    
                    try {
                        def reportContent = sh(script: "cat ${taskReportFile}", returnStdout: true).trim()
                        def taskIdMatch = (reportContent =~ /ceTaskId=([^\n]+)/)
                        if (taskIdMatch) {
                            taskId = taskIdMatch[0][1]
                            echo "✓ Found SonarQube task ID: ${taskId}"
                        }
                    } catch (Exception e) {
                        echo "⚠ Could not read task ID from report file: ${e.message}"
                    }
                    
                    // Define blocker count variable
                    def blockerCount = 'UNKNOWN'
                    
                    // Use SONARQUBE_TOKEN environment variable for authentication
                    // If token is not set, use admin:admin as fallback
                    def SONAR_AUTH = ""
                    
                    if (env.SONARQUBE_TOKEN && !env.SONARQUBE_TOKEN.isEmpty()) {
                        // Use token for authentication (token can be used directly in API calls)
                        SONAR_AUTH = "${env.SONARQUBE_TOKEN}:"
                        echo "Using SONARQUBE_TOKEN for API authentication"
                    } else {
                        // Fallback: use default admin credentials
                        SONAR_AUTH = "admin:admin"
                        echo "⚠ Using default admin credentials (token not set)"
                    }
                    
                    // Store auth string for use in API calls
                    env.SONAR_AUTH = SONAR_AUTH
                    
                    // Process SonarQube results (removed withCredentials wrapper)
                    // Wait for SonarQube to finish processing
                    def taskStatus = 'PENDING'
                    def maxWaitTime = 300  // 5 minutes max wait
                    def waitInterval = 10   // Check every 10 seconds
                    def totalWaitTime = 0
                    
                    if (taskId) {
                        echo "Waiting for SonarQube to process the analysis..."
                        
                        while (totalWaitTime < maxWaitTime && taskStatus != 'SUCCESS' && taskStatus != 'FAILED') {
                            sleep(time: waitInterval, unit: 'SECONDS')
                            totalWaitTime += waitInterval
                            
                                try {
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
                                    if (taskStatus != 'SUCCESS' && taskStatus != 'FAILED') {
                                        echo "  Processing... (${totalWaitTime}s)"
                                    }
                                }
                            } catch (Exception e) {
                                echo "⚠ Error checking task status: ${e.message}"
                            }
                        }
                        
                        if (taskStatus == 'SUCCESS') {
                            echo "✓ Analysis processed"
                            sleep(time: 5, unit: 'SECONDS')
                        } else if (taskStatus == 'FAILED') {
                            echo "✗ Analysis processing failed"
                            env.RUN_HADOOP_JOB = 'false'
                            env.BLOCKER_COUNT = 'ANALYSIS_FAILED'
                            return
                        }
                    } else {
                        echo "⚠ Could not get task ID, waiting 60 seconds as fallback..."
                        sleep(time: 60, unit: 'SECONDS')
                    }
                    
                    echo '📊 Checking Blocker Issues...'
                    
                    // Check blocker count only (quality gate not used for decision)
                    def maxRetries = 5
                    def retryDelay = 10
                    
                    for (int i = 0; i < maxRetries; i++) {
                        try {
                            // Check blocker issues
                            def blockerResponse = sh(
                                script: """
                                    curl -s -u ${SONAR_AUTH} \
                                    '${SONARQUBE_URL}/api/issues/search?componentKeys=Python-Code-Disasters&severities=BLOCKER&resolved=false'
                                """,
                                returnStdout: true
                            ).trim()
                            
                            // Parse blocker count
                            if (blockerResponse && blockerResponse.trim().length() > 0) {
                                try {
                                    def blockerMatch = blockerResponse =~ /"total"\s*:\s*(\d+)/
                                    if (blockerMatch) {
                                        blockerCount = blockerMatch[0][1]
                                        break  // Got valid response, exit loop
                                    }
                                } catch (Exception e) {
                                    // Silent parse error
                                }
                            }
                            
                            if (i < maxRetries - 1) {
                                sleep(time: retryDelay, unit: 'SECONDS')
                            }
                        } catch (Exception e) {
                            if (i < maxRetries - 1) {
                                sleep(time: retryDelay, unit: 'SECONDS')
                            }
                        }
                    }
                    
                    // Store blocker count for reporting
                    env.BLOCKER_COUNT = blockerCount
                    
                    // Decision logic: Only run Hadoop if no blocker issues
                    echo ''
                    echo '═══════════════════════════════════════════════════════════'
                    echo '                    Pipeline Decision                     '
                    echo '═══════════════════════════════════════════════════════════'
                    
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
                    
                    echo '═══════════════════════════════════════════════════════════'
                    echo ''
                }
            }
        }
        
        stage('Upload Code to GCS') {
            when {
                environment name: 'RUN_HADOOP_JOB', value: 'true'
            }
            steps {
                script {
                    echo 'Uploading repository code to GCS for Hadoop processing...'
                    sh """
                        # Create a clean copy of the repository
                        rm -rf /tmp/repo-upload
                        mkdir -p /tmp/repo-upload
                        
                        # Copy all files to upload directory (excluding .git, .terraform, etc.)
                        find . -type f \\
                            ! -path './.git/*' \\
                            ! -path './.terraform/*' \\
                            ! -path './.terraform.lock.hcl' \\
                            ! -path './.scannerwork/*' \\
                            ! -name '*.pyc' \\
                            ! -name '__pycache__' \\
                            -exec cp --parents {} /tmp/repo-upload/ \\;
                        
                        echo ""
                        echo "Uploading to ${REPO_GCS_PATH}..."
                        
                        # Use gcloud storage instead of gsutil (better Workload Identity support)
                        echo "Removing existing files..."
                        gcloud storage rm -r ${REPO_GCS_PATH}/** 2>/dev/null || echo "No existing files to remove"
                        
                        echo "Uploading files..."
                        gcloud storage cp -r /tmp/repo-upload/* ${REPO_GCS_PATH}/
                        
                        echo "✓ Code uploaded successfully"
                        echo ""
                        echo "Uploaded files:"
                        gcloud storage ls ${REPO_GCS_PATH}/ --recursive | head -10
                    """
                }
            }
        }
        
        stage('Execute Hadoop MapReduce Job') {
            when {
                environment name: 'RUN_HADOOP_JOB', value: 'true'
            }
            steps {
                script {
                    def timestamp = sh(script: 'date +%Y%m%d_%H%M%S', returnStdout: true).trim()
                    def outputPath = "gs://${OUTPUT_BUCKET}/results/${timestamp}"
                    
                    echo ''
                    echo '══════════════════════════════════════════════════'
                    echo '    Submitting Hadoop Job to Dataproc Cluster    '
                    echo '══════════════════════════════════════════════════'
                    echo ''
                    
                    sh """
                        echo "📊 Job Configuration:"
                        echo "   - Cluster: ${HADOOP_CLUSTER_NAME}"
                        echo "   - Region: ${HADOOP_REGION}"
                        echo "   - Project: ${GCP_PROJECT_ID}"
                        echo "   - Job: Line Counter (PySpark)"
                        echo "   - Input: ${REPO_GCS_PATH}"
                        echo "   - Output: ${outputPath}"
                        echo ""
                        echo "🚀 Submitting job to Dataproc..."
                        echo ""
                        
                        # Create a simple PySpark line counter script
                        cat > /tmp/line_counter_job.py << 'PYSPARK_SCRIPT'
from pyspark import SparkContext
import sys

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: line_counter_job.py <input_path> <output_path>")
        sys.exit(1)
    
    input_path = sys.argv[1]
    output_path = sys.argv[2]
    
    sc = SparkContext(appName="Repository File Line Counter")
    
    # Read all files from input path (not just Python files)
    # Use glob pattern to ensure all files are read recursively
    # wholeTextFiles with **/* pattern reads all files recursively
    files_rdd = sc.wholeTextFiles(input_path + "/**/*")
    
    # Extract filename and count lines per file
    def process_file(file_tuple):
        filepath, content = file_tuple
        # Extract relative path from input_path to preserve directory structure
        # For GCS paths, extract the part after repo-code/
        if 'repo-code/' in filepath:
            relative_path = filepath.split('repo-code/')[-1]
        else:
            relative_path = filepath.split('/')[-1]
        # Count lines (split by actual newline character)
        # Use splitlines() which handles all line ending types
        line_count = len(content.splitlines())
        return (relative_path, line_count)
    
    # Map to get (filepath, line_count) pairs
    line_counts = files_rdd.map(process_file)
    
    # Don't reduce - keep all files even if they have the same name in different directories
    # This preserves the full file structure
    
    # Format output as "filename": count
    def format_output(filename_count):
        filename, count = filename_count
        return f'"{filename}": {count}'
    
    # Sort by filename, format, and save
    sorted_counts = line_counts.sortByKey()
    formatted_output = sorted_counts.map(format_output)
    formatted_output.saveAsTextFile(output_path)
    
    sc.stop()
PYSPARK_SCRIPT
                        
                        # Upload the job script to GCS
                        gcloud storage cp /tmp/line_counter_job.py gs://${STAGING_BUCKET}/jobs/line_counter_job.py
                        
                        # Submit the PySpark job to Dataproc (uses Workload Identity automatically)
                        gcloud dataproc jobs submit pyspark \\
                            gs://${STAGING_BUCKET}/jobs/line_counter_job.py \\
                            --cluster=${HADOOP_CLUSTER_NAME} \\
                            --region=${HADOOP_REGION} \\
                            --project=${GCP_PROJECT_ID} \\
                            -- ${REPO_GCS_PATH} ${outputPath}
                        
                        echo ""
                        echo "════════════════════════════════════════════════════════════"
                        echo "✓ Hadoop MapReduce job completed successfully!"
                        echo "════════════════════════════════════════════════════════════"
                    """
                    
                    env.HADOOP_OUTPUT_PATH = outputPath
                }
            }
        }
        
        stage('Display Hadoop Results') {
            when {
                environment name: 'RUN_HADOOP_JOB', value: 'true'
            }
            steps {
                script {
                    echo ''
                    echo '══════════════════════════════════════════════════'
                    echo '          Hadoop MapReduce Job Results          '
                    echo '══════════════════════════════════════════════════'
                    echo ''
                    
                    sh """
                        echo "📈 Line counts for Python files:"
                        echo ""
                        
                        # Fetch and display results using gcloud storage
                        gcloud storage cat ${HADOOP_OUTPUT_PATH}/part-* 2>/dev/null || echo "Processing results..."
                        
                        echo ""
                        echo "════════════════════════════════════════════════════════════"
                        echo "Results saved to: ${HADOOP_OUTPUT_PATH}"
                        echo "════════════════════════════════════════════════════════════"
                    """
                }
            }
        }
        
        stage('Results Summary') {
            steps {
                script {
                    echo ''
                    echo '══════════════════════════════════════════════════'
                    echo '                      Summary                     '
                    echo '══════════════════════════════════════════════════'
                    echo "Blockers: ${env.BLOCKER_COUNT ?: 'N/A'}"
                    echo "Hadoop Job: ${env.RUN_HADOOP_JOB == 'true' ? 'EXECUTED' : 'SKIPPED'}"
                    if (env.RUN_HADOOP_JOB == 'true' && env.HADOOP_OUTPUT_PATH) {
                        echo "Output: ${env.HADOOP_OUTPUT_PATH}"
                    }
                    echo '══════════════════════════════════════════════════'
                    echo ''
                }
            }
        }
    }
    
    post {
        always {
            echo 'Pipeline execution completed.'
        }
        success {
            echo 'Pipeline executed successfully!'
        }
        failure {
            echo 'Pipeline failed. Check logs for details.'
        }
    }
}
