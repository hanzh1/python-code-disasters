#!/usr/bin/env python3
"""
Hadoop MapReduce Job: Line Counter
Counts the total number of lines in each file in the repository.

This script can be run as a PySpark job on Dataproc.
"""

from pyspark import SparkContext
import sys
import os

def count_lines_per_file(sc, input_path):
    """
    Count lines in each file using PySpark.
    
    Args:
        sc: SparkContext
        input_path: GCS path to input files (e.g., gs://bucket/repo-code/**/*)
    
    Returns:
        RDD of (filename, line_count) tuples
    """
    # Read all files using wholeTextFiles to get (filepath, content) pairs
    # wholeTextFiles reads all files recursively from the given path
    # Note: Use the base path, wholeTextFiles will recursively read all files
    files_rdd = sc.wholeTextFiles(input_path)
    
    # Extract filename and count lines
    def process_file(file_tuple):
        filepath, content = file_tuple
        # Extract just the filename from the full path
        filename = os.path.basename(filepath)
        # Count lines (split by newline)
        line_count = len(content.split('\n'))
        return (filename, line_count)
    
    # Map to get (filename, line_count) pairs
    line_counts = files_rdd.map(process_file)
    
    # Reduce by key to handle duplicate filenames (sum their line counts)
    # This handles cases where the same filename appears in different directories
    line_counts = line_counts.reduceByKey(lambda a, b: a + b)
    
    # Sort by filename for consistent output
    sorted_counts = line_counts.sortByKey()
    
    return sorted_counts

def format_output(filename, count):
    """
    Format output as: "File name": # of lines
    """
    return f'"{filename}": {count}'

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: line_counter.py <input_path> <output_path>")
        print("Example: line_counter.py gs://bucket/repo-code gs://bucket/results")
        sys.exit(1)
    
    input_path = sys.argv[1]
    output_path = sys.argv[2]
    
    print(f"Starting line counter job...")
    print(f"Input path: {input_path}")
    print(f"Output path: {output_path}")
    
    # Create SparkContext
    sc = SparkContext(appName="Repository File Line Counter")
    
    try:
        # Count lines per file
        line_counts = count_lines_per_file(sc, input_path)
        
        # Format output and save
        formatted_output = line_counts.map(lambda x: format_output(x[0], x[1]))
        formatted_output.saveAsTextFile(output_path)
        
        print("Job completed successfully!")
        print(f"Results saved to: {output_path}")
        
    except Exception as e:
        print(f"Error during job execution: {e}", file=sys.stderr)
        sys.exit(1)
    finally:
        sc.stop()

