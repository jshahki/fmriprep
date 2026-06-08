#!/bin/bash
#SBATCH --job-name=masked_tSNR_calculations
#SBATCH --time=01:30:00
#SBATCH --cpus-per-task=6
#SBATCH --mem=8000
#SBATCH --account=def-woodward
#SBATCH --output=logs/tSNR_masked_%j.out
#SBATCH --error=logs/tSNR_masked_%j.err

module load matlab/2024b.1
export MATLAB_PREFDIR="$SLURM_TMPDIR/matlab_prefs"

# Define paths
REPO_DIR="/scratch/$USER/fmriprep"
INPUT_DIR="$REPO_DIR/smoothed"
RESLICED_MASK_DIR="$REPO_DIR/resliced_bold_masks"
OUTPUT_DIR="$REPO_DIR/tsnr_output_masked"
LOG_DIR="$REPO_DIR/logs/status"

# Create output and log directories if needed
mkdir -p "$OUTPUT_DIR"
mkdir -p "$LOG_DIR"

# Run MATLAB
matlab -nodisplay -nosplash -r "try, run_masked_tSNR_calculations('$INPUT_DIR', '$RESLICED_MASK_DIR', '$OUTPUT_DIR'); catch ME, disp(getReport(ME)); exit(1); end; exit(0);"
EXIT_CODE=$?

# Set status
if [ $EXIT_CODE -eq 0 ]; then
  STATUS="SUCCESS"
else
  STATUS="FAILED"
fi

STATUS_FILE="$LOG_DIR/tSNR_masked_${SLURM_JOB_ID}_${STATUS}.txt"

{
  echo "Job ID: $SLURM_JOB_ID"
  echo "Exit Code: $EXIT_CODE"
  echo "Status: $STATUS"
  echo "Finished: $(date)"
  echo "Input Dir: $INPUT_DIR"
  echo "Mask Dir: $MASK_DIR"
  echo "Output Dir: $OUTPUT_DIR"
} > "$STATUS_FILE"

