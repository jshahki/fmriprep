#!/bin/bash

set -euo pipefail

# ----------------------------
# Paths
# ----------------------------
SCRATCH_DIR="/scratch/st-toddwood-1/$USER"
REPO_DIR="$SCRATCH_DIR/START-fmri"

FMRIPREP_IMAGE="$REPO_DIR/tools/fmriprep-20.2.7.sif"

SPM_DIR="$REPO_DIR/tools/spm-25.01.02"
SPM_ZIP="$REPO_DIR/tools/spm25.zip"
SPM_URL="https://github.com/spm/spm/archive/refs/tags/25.01.02.zip"

LOG_DIR="$REPO_DIR/logs"
STATUS_DIR="$LOG_DIR/status"
DERIVATIVES_DIR="$REPO_DIR/derivatives"
CACHE_DIR="$REPO_DIR/cache"

mkdir -p "$LOG_DIR" "$STATUS_DIR" "$REPO_DIR/tools" "$DERIVATIVES_DIR" "$CACHE_DIR"

LOG_FILE="$LOG_DIR/setup_login_$(date +%Y%m%d_%H%M%S).log"

exec > >(tee -a "$LOG_FILE") 2>&1

echo "======================================"
echo "START-fmri SETUP (LOGIN NODE)"
echo "User: $USER"
echo "Host: $(hostname)"
echo "Start: $(date)"
echo "======================================"

module purge
module load gcc/9.4.0
module load apptainer/1.3.1

echo ""
echo "Modules loaded:"
module list

# ============================================================
# fMRIPREP CONTAINER
# ============================================================
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

# ============================================================
# SPM DOWNLOAD + EXTRACTION
# ============================================================
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

# ============================================================
# TEMPLATEFLOW CACHE + PRE-DOWNLOAD (FIXED PROPER VERSION)
# ============================================================

echo ""
echo "Checking TemplateFlow cache..."

TF_DIR="$CACHE_DIR/templateflow"
mkdir -p "$TF_DIR"

export TEMPLATEFLOW_HOME="$TF_DIR"
export APPTAINERENV_TEMPLATEFLOW_HOME="$TF_DIR"

TF_STATUS="SUCCESS"

echo "✔ TemplateFlow cache directory ready"

echo ""
echo "Pre-downloading required TemplateFlow templates using container..."

apptainer exec "$FMRIPREP_IMAGE" python -c "
from templateflow import api
api.get('OASIS30ANTs')
api.get('MNI152NLin2009cAsym')
" || TF_STATUS="FAILED"

if [ "$TF_STATUS" = "SUCCESS" ]; then
    echo "✔ TemplateFlow templates pre-downloaded successfully"
else
    echo "✘ TemplateFlow download FAILED (check network or cache permissions)"
fi

# ============================================================
# FINAL REPORT
# ============================================================
echo ""
echo "======================================"
echo "FINAL STATUS REPORT"
echo "======================================"

echo "fMRIPREP: $FMRIPREP_STATUS"
echo "SPM25:    $SPM_STATUS"
echo "TemplateFlow: $TF_STATUS"

if [[ "$FMRIPREP_STATUS" == "FAILED" || "$SPM_STATUS" == "FAILED" || "$TF_STATUS" == "FAILED" ]]; then
    FINAL_STATUS="FAILED"
else
    FINAL_STATUS="SUCCESS"
fi

echo "Overall:  $FINAL_STATUS"
echo "End:      $(date)"
echo "Log file: $LOG_FILE"

mkdir -p "$STATUS_DIR"

{
  echo "Final Status: $FINAL_STATUS"
  echo "fMRIPREP: $FMRIPREP_STATUS"
  echo "SPM25: $SPM_STATUS"
  echo "TemplateFlow: $TF_STATUS"
  echo "User: $USER"
  echo "Host: $(hostname)"
  echo "Date: $(date)"
} > "$STATUS_DIR/setup_status.txt"
