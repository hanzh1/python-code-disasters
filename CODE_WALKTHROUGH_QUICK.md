# Code Walkthrough Quick Reference

## Structure Overview

```
Jenkinsfile (462 lines)
├── Environment Variables (lines 4-13)
├── Stage 1: Checkout (16-21)
├── Stage 2: Setup GCloud SDK (23-78)
├── Stage 3: SonarQube Analysis (80-115)
├── Stage 4: Blocker Check & Decision (117-273) ⭐ CRITICAL
├── Stage 5: Upload to GCS (275-314)
├── Stage 6: Execute Hadoop (316-401) ⭐ CRITICAL
├── Stage 7: Display Results (403-429)
└── Stage 8: Summary (431-447)
```

---

## Key Sections to Highlight

### 1. Environment Variables (Lines 4-13)
**Say:** "These variables come from Kubernetes deployment"
**Show:** All 8 environment variables

### 2. Blocker Check Logic (Lines 206-244) ⭐
**Say:** "This queries SonarQube API for blocker issues"
**Show:** 
- API endpoint: `/api/issues/search?severities=BLOCKER`
- Regex parsing: `/"total"\s*:\s*(\d+)/`
- Retry logic (5 attempts)

### 3. Decision Logic (Lines 249-267) ⭐
**Say:** "This is the core decision - only blocker count matters"
**Show:**
```groovy
if (blockerCount == 'UNKNOWN') → SKIP
else if (blockerCount != '0') → SKIP  
else → RUN Hadoop
```

### 4. Hadoop Job Script (Lines 343-381) ⭐
**Say:** "PySpark script that counts lines in all files"
**Show:**
- `wholeTextFiles()` - reads entire files
- `/*` and `/**/*` patterns - root + subdirs
- `splitlines()` - counts lines
- Format: `f'"{filename}": {count}'`

### 5. Conditional Stages (Lines 276-278, 317-319, 404-406)
**Say:** "These stages only run if RUN_HADOOP_JOB == 'true'"
**Show:** `when { environment name: 'RUN_HADOOP_JOB', value: 'true' }`

---

## Talking Points by Section

### Environment (0:30)
- Variables injected from K8s
- `REPO_GCS_PATH` constructed dynamically
- Token uses default empty string

### Checkout (1:00)
- Simple SCM checkout
- Gets latest code including Jenkinsfile

### GCloud Setup (1:30)
- Checks for existing installation
- Downloads if needed
- Uses Workload Identity (no keys)

### SonarQube (2:30)
- Downloads scanner dynamically
- Token or admin:admin auth
- `qualitygate.wait=false` - we check separately

### Blocker Check (4:00) ⭐
- Waits for SonarQube processing (up to 5 min)
- Polls API every 10 seconds
- Queries ONLY blocker severity
- Retries 5 times on failure

### Decision (5:00) ⭐
- **Three outcomes:**
  - UNKNOWN → Skip (fail-safe)
  - > 0 → Skip (blockers found)
  - = 0 → Run (clean code)
- Sets `RUN_HADOOP_JOB` env var

### Upload (6:00)
- Only runs if blockers = 0
- Excludes .git, .terraform, etc.
- Preserves directory structure

### Hadoop (7:00) ⭐
- Creates PySpark script inline
- Reads root + subdir files
- Counts lines with `splitlines()`
- Formats as `"filename": count`
- Submits to Dataproc

### Results (8:00)
- Fetches from GCS
- Displays in console
- Shows GCS path

---

## Code Snippets to Show

### Snippet 1: Blocker API Query
```groovy
curl -s -u ${SONAR_AUTH} \
'${SONARQUBE_URL}/api/issues/search?componentKeys=Python-Code-Disasters&severities=BLOCKER&resolved=false'
```

### Snippet 2: Decision Logic
```groovy
if (blockerCount != '0') {
    env.RUN_HADOOP_JOB = 'false'
} else {
    env.RUN_HADOOP_JOB = 'true'
}
```

### Snippet 3: File Reading
```python
root_files = sc.wholeTextFiles(input_path + "/*")
subdir_files = sc.wholeTextFiles(input_path + "/**/*")
files_rdd = root_files.union(subdir_files).distinct()
```

### Snippet 4: Line Counting
```python
line_count = len(content.splitlines())
return (relative_path, line_count)
```

### Snippet 5: Output Formatting
```python
return f'"{filename}": {count}'
```

---

## Visual Flow Diagram

```
GitHub Push
    ↓
Webhook Trigger
    ↓
Jenkins Pipeline
    ↓
[Checkout] → [GCloud Setup] → [SonarQube Analysis]
    ↓
[Wait for Processing]
    ↓
[Check Blocker Count]
    ↓
    ├─→ Blockers > 0 → SKIP Hadoop → [Summary]
    │
    └─→ Blockers = 0 → [Upload to GCS] → [Hadoop Job] → [Display Results] → [Summary]
```

---

## Recording Tips

1. **Start with overview** - Show full file structure
2. **Zoom on critical sections** - Blocker check, decision logic, Hadoop script
3. **Explain data flow** - How variables move between stages
4. **Show actual values** - Example: `blockerCount = "0"` → `RUN_HADOOP_JOB = 'true'`
5. **Highlight patterns** - Regex, RDD operations, conditional execution
6. **Pause for complex parts** - API parsing, file processing logic

---

## Time Allocation

- Introduction: 0:30
- Environment & Setup: 2:00
- SonarQube Analysis: 1:30
- **Blocker Check (CRITICAL): 2:00**
- **Decision Logic (CRITICAL): 1:00**
- Upload & Hadoop: 2:00
- Results & Summary: 1:00
- **Total: ~10 minutes**

---

## Key Emphasize Points

✅ **Blocker count is the ONLY decision factor**  
✅ **Quality gate is NOT checked**  
✅ **Hadoop runs ONLY when blockers = 0**  
✅ **Results format: `"filename": line_count`**  
✅ **Uses Workload Identity (no service account keys)**  
✅ **Fully automated via webhooks**

