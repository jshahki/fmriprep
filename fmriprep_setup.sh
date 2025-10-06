#!/bin/bash

#SBATCH --job-name=fmriprep_setup
#SBATCH --time=02:00:00
#SBATCH --cpus-per-task=10
#SBATCH --mem-per-cpu=6000
#SBATCH --account=def-woodward
#SBATCH --output=logs/fmriprep_setup_%A_%a.out
#SBATCH --error=logs/fmriprep_setup_%A_%a.err

# ----------- Basic Environment Setup -----------

echo "SLURM job started at $(date)"
echo "Running on host: $(hostname)"
echo "User: $USER"

# Ensure SLURM output directory exists (relative to submission location)
mkdir -p logs

# Define paths
REPO_DIR="/scratch/$USER/fmriprep"
FMRIPREP_IMAGE="$REPO_DIR/fmriprep-20.2.7.sif"
SPM_DIR="$REPO_DIR/tools/spm-25.01.02"  # <- Keep original name
SPM_ZIP="$REPO_DIR/tools/spm25.zip"
SPM_URL="https://github.com/spm/spm/archive/refs/tags/25.01.02.zip"
STATUS_DIR="$REPO_DIR/logs/status"

# Load required modules
module load StdEnv/2023
module load apptainer

# Create required directories
export APPTAINER_CACHEDIR="$REPO_DIR/apptainer_cache"
mkdir -p "$APPTAINER_CACHEDIR"
mkdir -p "$REPO_DIR"/{data,derivatives,work,logs,tools}
mkdir -p "$STATUS_DIR"

# ----------- Setup fMRIPrep -----------

FMRIPREP_STATUS="SKIPPED"
if [ ! -f "$FMRIPREP_IMAGE" ]; then
  echo "fMRIPrep not found. Downloading..."
  apptainer pull "$FMRIPREP_IMAGE" docker://nipreps/fmriprep:20.2.7
  if [ $? -eq 0 ]; then
    FMRIPREP_STATUS="SUCCESS"
    echo "fMRIPrep setup complete."
  else
    FMRIPREP_STATUS="FAILED"
    echo "fMRIPrep setup FAILED."
  fi
else
  echo "fMRIPrep already exists at $FMRIPREP_IMAGE — skipping download."
fi

# ----------- Setup SPM25 (keep folder name) -----------

SPM_STATUS="SKIPPED"
if [ ! -d "$SPM_DIR" ]; then
  echo "SPM25 not found. Downloading..."
  wget -O "$SPM_ZIP" "$SPM_URL"
  if [ $? -ne 0 ]; then
    SPM_STATUS="FAILED"
    echo "SPM25 download failed."
  else
    echo "Extracting SPM..."
    unzip "$SPM_ZIP" -d "$REPO_DIR/tools/"
    if [ $? -eq 0 ]; then
      rm -f "$SPM_ZIP"
      SPM_STATUS="SUCCESS"
      echo "SPM25 setup complete at $SPM_DIR"
    else
      SPM_STATUS="FAILED"
      echo "SPM25 extraction failed."
    fi
  fi
else
  echo "SPM25 already exists at $SPM_DIR — skipping setup."
fi

# ----------- Status Reporting -----------

# Determine final status
if [[ "$FMRIPREP_STATUS" == "FAILED" || "$SPM_STATUS" == "FAILED" ]]; then
  FINAL_STATUS="FAILED"
else
  FINAL_STATUS="SUCCESS"
fi

STATUS_FILE="$STATUS_DIR/setup_${FINAL_STATUS}.txt"

{
  echo "Final Status: $FINAL_STATUS"
  echo "fMRIPrep Status: $FMRIPREP_STATUS"
  echo "SPM25 Status: $SPM_STATUS"
  echo "Job ID: $SLURM_JOB_ID"
  echo "Finished: $(date)"
  echo "User: $USER"
  echo "Host: $(hostname)"
} > "$STATUS_FILE"

