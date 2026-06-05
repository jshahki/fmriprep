#!/bin/bash

set -euo pipefail

# ----------------------------
# Paths
# ----------------------------
SCRATCH_DIR="/scratch/st-toddwood-1/$USER"
REPO_DIR="$SCRATCH_DIR/fmriprep"

FMRIPREP_IMAGE="$REPO_DIR/fmriprep-20.2.7.sif"

SPM_DIR="$REPO_DIR/tools/spm-25.01.02"
SPM_ZIP="$REPO_DIR/tools/spm25.zip"
SPM_URL="https://github.com/spm/spm/archive/refs/tags/25.01.02.zip"

LOG_DIR="$REPO_DIR/logs"
STATUS_DIR="$LOG_DIR/status"

mkdir -p "$LOG_DIR" "$STATUS_DIR" "$REPO_DIR/tools"

LOG_FILE="$LOG_DIR/setup_login_$(date +%Y%m%d_%H%M%S).log"

# Redirect ALL output to log while still showing in terminal
exec > >(tee -a "$LOG_FILE") 2>&1

echo "======================================"
echo "fMRIPrep SETUP (LOGIN NODE)"
echo "User: $USER"
echo "Host: $(hostname)"
echo "Start: $(date)"
echo "======================================"

# ----------------------------
# Load modules (login node only)
# ----------------------------
module purge
module load gcc/9.4.0
module load apptainer/1.3.1

echo ""
echo "Modules loaded:"
module list

# ----------------------------
# fMRIPrep container
# ----------------------------
echo ""
echo "Checking fMRIPrep container..."

FMRIPREP_STATUS="SUCCESS"

if [ -f "$FMRIPREP_IMAGE" ]; then
    echo "✔ fMRIPrep already exists: $FMRIPREP_IMAGE"
else
    echo "Downloading fMRIPrep container..."

    if apptainer pull "$FMRIPREP_IMAGE" docker://nipreps/fmriprep:20.2.7; then
        echo "✔ fMRIPrep download SUCCESS"
    else
        echo "✘ fMRIPrep download FAILED"
        FMRIPREP_STATUS="FAILED"
    fi
fi

# ----------------------------
# SPM download + extraction
# ----------------------------
echo ""
echo "Checking SPM25..."

SPM_STATUS="SUCCESS"

if [ -d "$SPM_DIR" ]; then
    echo "✔ SPM already exists: $SPM_DIR"
else
    echo "Downloading SPM25..."

    if wget -O "$SPM_ZIP" "$SPM_URL"; then
        echo "✔ Downloaded SPM zip"
    else
        echo "✘ SPM download FAILED"
        SPM_STATUS="FAILED"
    fi

    if [ "$SPM_STATUS" = "SUCCESS" ]; then
        echo "Extracting SPM..."

        if unzip -q "$SPM_ZIP" -d "$REPO_DIR/tools/"; then
            rm -f "$SPM_ZIP"
            echo "✔ SPM extraction SUCCESS"
        else
            echo "✘ SPM extraction FAILED"
            SPM_STATUS="FAILED"
        fi
    fi
fi

# ----------------------------
# Final report
# ----------------------------
echo ""
echo "======================================"
echo "FINAL STATUS REPORT"
echo "======================================"

echo "fMRIPrep: $FMRIPREP_STATUS"
echo "SPM25:    $SPM_STATUS"

if [[ "$FMRIPREP_STATUS" == "FAILED" || "$SPM_STATUS" == "FAILED" ]]; then
    FINAL_STATUS="FAILED"
else
    FINAL_STATUS="SUCCESS"
fi

echo "Overall:  $FINAL_STATUS"
echo "End:      $(date)"
echo "Log file: $LOG_FILE"

# Save machine-readable status file
mkdir -p "$STATUS_DIR"

{
  echo "Final Status: $FINAL_STATUS"
  echo "fMRIPrep: $FMRIPREP_STATUS"
  echo "SPM25: $SPM_STATUS"
  echo "User: $USER"
  echo "Host: $(hostname)"
  echo "Date: $(date)"
} > "$STATUS_DIR/setup_status.txt"
