#!/bin/bash

#SBATCH --job-name=fmriprep_setup
#SBATCH --time=02:00:00
#SBATCH --cpus-per-task=10
#SBATCH --mem-per-cpu=6000
#SBATCH --account=def-woodward
#SBATCH --output=logs/fmriprep_setup_%A_%a.out
#SBATCH --error=logs/fmriprep_setup_%A_%a.err

# Ensure log directory exists
mkdir -p /scratch/$USER/fmriprep/logs

module load StdEnv/2023
module load apptainer

REPO_DIR="/scratch/$USER/fmriprep"
export APPTAINER_CACHEDIR="$REPO_DIR/apptainer_cache"
mkdir -p "$APPTAINER_CACHEDIR"
mkdir -p "$REPO_DIR"/{data,derivatives,work,logs}

FMRIPREP_IMAGE="$REPO_DIR/fmriprep-20.2.7.sif"

if [ ! -f "$FMRIPREP_IMAGE" ]; then
  apptainer pull "$FMRIPREP_IMAGE" docker://nipreps/fmriprep:20.2.7
fi

STATUS_DIR="$REPO_DIR/logs/status"
mkdir -p "$STATUS_DIR"

EXIT_CODE=$?
if [ $EXIT_CODE -eq 0 ]; then
  STATUS="SUCCESS"
else
  STATUS="FAILED"
fi

STATUS_FILE="$STATUS_DIR/setup_${STATUS}.txt"

{
  echo "Status: $STATUS"
  echo "Exit Code: $EXIT_CODE"
  echo "Job ID: $SLURM_JOB_ID"
  echo "Finished: $(date)"
  echo "User: $USER"
  echo "Host: $(hostname)"
} > "$STATUS_FILE"

