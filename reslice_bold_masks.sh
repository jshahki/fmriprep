#!/bin/bash
#SBATCH --job-name=reslice_bold_masks
#SBATCH --account=def-woodward
#SBATCH --time=01:00:00
#SBATCH --cpus-per-task=8
#SBATCH --mem=6000
#SBATCH --output=logs/reslice_bold_masks_%A_%a.out
#SBATCH --error=logs/reslice_bold_masks_%A_%a.err

module load StdEnv/2023 matlab/2024b.1
export MATLAB_PREFDIR="$SLURM_TMPDIR/matlab_prefs"

# === PATH SETUP ===
REPO_DIR="/scratch/$USER/fmriprep"
MASK_INPUT_DIR="$REPO_DIR/derivatives/fmriprep"
RESLICE_OUTPUT_DIR="$REPO_DIR/resliced_bold_masks"
SPM_PATH="$REPO_DIR/tools/spm-25.01.02"
REFERENCE_SCAN="$REPO_DIR/tools/3x3x3_reference_scan.hdr"
PARTICIPANTS="$REPO_DIR/data/participants.tsv"

# === SELECT SUBJECT FROM ARRAY ===
mapfile -t SUBJECTS < <(tail -n +2 "$PARTICIPANTS" | cut -f1 | sed 's/\r//')
SUBJECT="${SUBJECTS[$SLURM_ARRAY_TASK_ID]}"

if [ -z "$SUBJECT" ]; then
    echo "No subject found for index $SLURM_ARRAY_TASK_ID"
    exit 1
fi

# === CALL MATLAB SCRIPT TO RESLICE ===
matlab -nodisplay -nosplash -r "addpath('$SPM_PATH'); reslice_subject_mask('$SUBJECT', '$MASK_INPUT_DIR', '$RESLICE_OUTPUT_DIR', '$REFERENCE_SCAN'); exit;"

# === LOG SUCCESS ===
STATUS_FILE="$REPO_DIR/logs/status/${SUBJECT}_reslice_bold_mask_SUCCESS.txt"
mkdir -p "$(dirname "$STATUS_FILE")"
{
  echo "Subject: $SUBJECT"
  echo "Job ID: $SLURM_JOB_ID"
  echo "Completed: $(date)"
} > "$STATUS_FILE"

