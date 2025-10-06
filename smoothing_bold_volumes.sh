#!/bin/bash
#SBATCH --job-name=smoothing
#SBATCH --time=02:00:00
#SBATCH --cpus-per-task=6
#SBATCH --mem=8000
#SBATCH --account=def-woodward
#SBATCH --output=logs/smoothing_%A_%a.out
#SBATCH --error=logs/smoothing_%A_%a.err

# Load modules
module load matlab/2024b.1
export MATLAB_PREFDIR="$SLURM_TMPDIR/matlab_prefs"

# Setup paths
REPO_DIR="/scratch/$USER/fmriprep"
SPM_DIR="$REPO_DIR/tools/spm-25.01.02"
DATA_DIR="$REPO_DIR/split_reslice_outputs"            # Resliced + split input dir
PARTICIPANTS="$REPO_DIR/data/participants.tsv"
SMOOTH_OUTPUT="$REPO_DIR/smoothed"
LOG_DIR="$REPO_DIR/logs/status"

mkdir -p "$LOG_DIR" "$SMOOTH_OUTPUT"

# Get subject from array index
: "${SLURM_ARRAY_TASK_ID:=0}"
mapfile -t SUBJECTS < <(tail -n +2 "$PARTICIPANTS" | cut -f1 | tr -d '\r' | sed '/^$/d')
SUBJECT="${SUBJECTS[$SLURM_ARRAY_TASK_ID]}"

if [ -z "$SUBJECT" ]; then
  echo "No subject found for index $SLURM_ARRAY_TASK_ID"
  exit 1
fi

# Directories
IN_SUBJ_DIR="$DATA_DIR/$SUBJECT"
OUT_SUBJ_DIR="$SMOOTH_OUTPUT/$SUBJECT"
mkdir -p "$OUT_SUBJ_DIR"

# Kernel size from input or default to 8 8 8
KERNEL="${KERNEL:-8 8 8}"
echo "Running smoothing on $SUBJECT with kernel: $KERNEL"

# Run MATLAB
matlab -nodisplay -nosplash -r "addpath('$SPM_DIR'); smoothing_spm_batch('$IN_SUBJ_DIR', '$OUT_SUBJ_DIR', '$SUBJECT', [$KERNEL]); exit"

# Create status file
EXIT_CODE=$?
STATUS_FILE="$LOG_DIR/${SUBJECT}_$( [ $EXIT_CODE -eq 0 ] && echo SUCCESS || echo FAILED ).txt"

{
  echo "Subject: $SUBJECT"
  echo "Kernel: $KERNEL"
  echo "Exit Code: $EXIT_CODE"
  echo "Job ID: $SLURM_JOB_ID"
  echo "Finished: $(date)"
} > "$STATUS_FILE"

