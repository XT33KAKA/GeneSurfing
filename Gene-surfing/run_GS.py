#!/usr/bin/env python3
import argparse
import subprocess
import os
import sys

def main():
    parser = argparse.ArgumentParser(description='GeneSurfing Pipeline')
    parser.add_argument('-q', '--query', required=True, help='Path to query.fasta file')
    parser.add_argument('-s', '--samples', required=True, help='Path to sample directory')
    parser.add_argument('-c', '--cores', type=int, default=1, help='Number of threads to use (default: 1)')
    
    args = parser.parse_args()
    
    # Validate paths
    if not os.path.isfile(args.query):
        sys.exit(f"Error: Query file {args.query} not found!")
    if not os.path.isdir(args.samples):
        sys.exit(f"Error: Sample directory {args.samples} not found!")
    if args.cores <= 0:
        sys.exit("Error: Number of cores must be a positive integer!")

    # Construct Snakemake command
    cmd = [
        "snakemake",
        "-s", "workflow/workflow.smk",
        "--use-conda",
        "--cores", str(args.cores),  # Use user-specified cores
        "--config",
        f"query_path={os.path.abspath(args.query)}",
        f"samples_path={os.path.abspath(args.samples)}"
    ]
    
    try:
        subprocess.run(cmd, check=True)
    except subprocess.CalledProcessError as e:
        sys.exit(f"Pipeline failed with error code {e.returncode}")

if __name__ == "__main__":
    main()
