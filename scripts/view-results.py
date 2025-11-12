#!/usr/bin/env python3
"""
Script to view Hadoop MapReduce job results
Usage: ./view-results.py [output_path]
If no path provided, shows the latest results
"""

import sys
import re
import subprocess
import os

# Colors for output
GREEN = '\033[0;32m'
YELLOW = '\033[1;33m'
BLUE = '\033[0;34m'
NC = '\033[0m'  # No Color

# Get project ID from terraform.tfvars if available
PROJECT_ID = None
if os.path.exists('../terraform/terraform.tfvars'):
    with open('../terraform/terraform.tfvars', 'r') as f:
        for line in f:
            if 'project_id' in line:
                match = re.search(r'project_id\s*=\s*"([^"]+)"', line)
                if match:
                    PROJECT_ID = match.group(1)
                    break

if not PROJECT_ID:
    PROJECT_ID = os.environ.get('GCP_PROJECT_ID', '')

OUTPUT_BUCKET = f"{PROJECT_ID}-hadoop-output"

# Determine output path
if len(sys.argv) > 1:
    output_path = sys.argv[1]
    if not output_path.startswith('gs://'):
        output_path = f"gs://{OUTPUT_BUCKET}/{output_path}"
else:
    # Get the latest results directory
    print(f"{BLUE}Finding latest results...{NC}")
    try:
        # List all directories in results/
        result = subprocess.run(
            ['gsutil', 'ls', f'gs://{OUTPUT_BUCKET}/results/'],
            capture_output=True,
            text=True
        )
        if result.returncode != 0:
            print(f"{YELLOW}No results found. Listing all available results:{NC}")
            print(result.stderr)
            sys.exit(1)
        
        lines = [line.strip() for line in result.stdout.strip().split('\n') if line.strip()]
        # Filter to only directories (end with /)
        directories = [line for line in lines if line.endswith('/')]
        
        if not directories:
            print(f"{YELLOW}No results found. Listing all available results:{NC}")
            for line in lines:
                print(line)
            sys.exit(1)
        
        # Sort directories by name (timestamp format: YYYYMMDD_HHMMSS)
        directories.sort(reverse=True)
        latest = directories[0]
        output_path = latest.rstrip('/')  # Remove trailing slash
    except Exception as e:
        print(f"Error finding latest results: {e}")
        print(f"{YELLOW}Trying to list all available results:{NC}")
        try:
            subprocess.run(['gsutil', 'ls', f'gs://{OUTPUT_BUCKET}/results/'])
        except:
            pass
        sys.exit(1)

print("")
print(f"{GREEN}{'='*62}{NC}")
print(f"{GREEN}          Hadoop MapReduce Job Results{NC}")
print(f"{GREEN}{'='*62}{NC}")
print("")
print(f"{BLUE}Results Path: {output_path}{NC}")
print("")

# Fetch results
print(f"{YELLOW}Line counts for all files:{NC}")
print("")

# Get all part files - need to quote the pattern to prevent shell expansion
try:
    # Use shell=True with proper quoting to handle the glob pattern
    cmd = f"gsutil ls '{output_path}/part-*'"
    result = subprocess.run(
        cmd,
        shell=True,
        capture_output=True,
        text=True
    )
    part_files = [line.strip() for line in result.stdout.strip().split('\n') if line.strip() and line.strip().endswith('part-') == False]
    if not part_files:
        # Try listing the directory and filtering
        result = subprocess.run(
            ['gsutil', 'ls', output_path],
            capture_output=True,
            text=True
        )
        part_files = [line.strip() for line in result.stdout.strip().split('\n') 
                     if line.strip() and 'part-' in line and not line.strip().endswith('/')]
except Exception as e:
    print(f"Error listing part files: {e}")
    # Fallback: list directory and filter
    try:
        result = subprocess.run(
            ['gsutil', 'ls', output_path],
            capture_output=True,
            text=True
        )
        part_files = [line.strip() for line in result.stdout.strip().split('\n') 
                     if line.strip() and 'part-' in line and not line.strip().endswith('/')]
    except:
        sys.exit(1)

# Collect all results
results = []
for part_file in part_files:
    try:
        result = subprocess.run(
            ['gsutil', 'cat', part_file],
            capture_output=True,
            text=True
        )
        for line in result.stdout.strip().split('\n'):
            line = line.strip()
            if not line:
                continue
            # Match format: "filename": count
            match = re.match(r'^"(.+)":\s*(\d+)$', line)
            if match:
                filename = match.group(1)
                count = int(match.group(2))
                results.append((filename, count))
            else:
                # Fallback: Try Python tuple format: ('filename.py', count)
                match = re.match(r"^\('(.+)',\s*(\d+)\)$", line)
                if match:
                    filename = match.group(1)
                    count = int(match.group(2))
                    results.append((filename, count))
    except Exception as e:
        print(f"Error reading {part_file}: {e}")

# Sort by count descending
results.sort(key=lambda x: x[1], reverse=True)

# Display formatted results
print(f"{BLUE}Formatted Results:{NC}")
print("")
print(f"{'Filename':<50} {'Lines':>10}")
print("=" * 62)
for filename, count in results:
    print(f"{filename:<50} {count:>10} lines")

print("")
print(f"{GREEN}{'='*62}{NC}")
print(f"{GREEN}Full results available at: {output_path}{NC}")
print(f"{GREEN}{'='*62}{NC}")
print("")
