#!/bin/bash
#SBATCH --job-name=nonmasked_tSNR_calculations
#SBATCH --time=01:30:00
#SBATCH --cpus-per-task=6
#SBATCH --mem=8000
#SBATCH --account=def-woodward
#SBATCH --output=logs/tSNR_nonmasked_%j.out
#SBATCH --error=logs/tSNR_nonmasked_%j.err

module load matlab/2024b.1
export MATLAB_PREFDIR="$SLURM_TMPDIR/matlab_prefs"

# Define paths dynamically using $USER
REPO_DIR="/scratch/$USER/fmriprep"
INPUT_DIR="$REPO_DIR/smoothed"
OUTPUT_DIR="$REPO_DIR/tsnr_output_nonmasked"
LOG_DIR="$REPO_DIR/logs/status"

# Create output directory if it doesn't exist
mkdir -p "$OUTPUT_DIR"
mkdir -p "$LOG_DIR"

# Run MATLAB and capture exit code
matlab -nodisplay -nosplash -r "try, run_nonmasked_tSNR_calculations('$INPUT_DIR', '$OUTPUT_DIR'); catch ME, disp(getReport(ME)); exit(1); end; exit(0);"
EXIT_CODE=$?

# Determine status
if [ $EXIT_CODE -eq 0 ]; then
  STATUS="SUCCESS"
else
  STATUS="FAILED"
fi

# Compose status filename using Job ID and status
STATUS_FILE="$LOG_DIR/tSNR_nonmasked_${SLURM_JOB_ID}_${STATUS}.txt"

{
  echo "Job ID: $SLURM_JOB_ID"
  echo "Exit Code: $EXIT_CODE"
  echo "Status: $STATUS"
  echo "Kernel: $(uname -r)"
  echo "Finished: $(date)"
  echo "Input Dir: $INPUT_DIR"
  echo "Output Dir: $OUTPUT_DIR"
} > "$STATUS_FILE"
