#!/bin/bash
#SBATCH --job-name=fmriprep
#SBATCH --time=10:00:00
#SBATCH --nodes=1
#SBATCH --cpus-per-task=16
#SBATCH --mem=120G
#SBATCH --account=st-toddwood-1
#SBATCH --output=logs/fmriprep_%A_%a.out
#SBATCH --error=logs/fmriprep_%A_%a.err

module purge
module load gcc/9.4.0
module load apptainer/1.3.1

REPO_DIR="/scratch/st-toddwood-1/$USER/START-fmri"
BIDS_DIR="$REPO_DIR/data"
OUTPUT_DIR="$REPO_DIR/derivatives"
WORK_DIR="$SLURM_TMPDIR/work"
FS_LICENSE="$REPO_DIR/tools/license.txt"
SUBJECTS_FILE="$BIDS_DIR/participants.tsv"
FMRIPREP_IMAGE="$REPO_DIR/tools/fmriprep-20.2.7.sif"

: "${SLURM_ARRAY_TASK_ID:=0}"

mapfile -t SUBJECTS < <(tail -n +2 "$SUBJECTS_FILE" | cut -f1 | tr -d '\r' | sed '/^$/d')

SUBJECT="${SUBJECTS[$SLURM_ARRAY_TASK_ID]}"
if [ -z "$SUBJECT" ]; then
  echo "No subject for index $SLURM_ARRAY_TASK_ID"
  exit 1
fi

FS_SUBJECTS_DIR="$WORK_DIR/freesurfer_subjects_${SUBJECT}"
mkdir -p "$FS_SUBJECTS_DIR"

export MPLBACKEND=Agg
export APPTAINERENV_MPLBACKEND=Agg
export APPTAINERENV_FS_LICENSE=/fs/license.txt

CACHE_DIR="$REPO_DIR/cache"

mkdir -p "$CACHE_DIR/templateflow"
mkdir -p "$CACHE_DIR/apptainer"

export XDG_CACHE_HOME="$CACHE_DIR"

# IMPORTANT: pass TemplateFlow cache INTO container (required because --cleanenv is used)
export TEMPLATEFLOW_HOME="$CACHE_DIR/templateflow"
export APPTAINERENV_TEMPLATEFLOW_HOME="$CACHE_DIR/templateflow"

# Also ensure XDG cache propagates inside container
export APPTAINERENV_XDG_CACHE_HOME="$CACHE_DIR"

export APPTAINER_CACHEDIR="$CACHE_DIR/apptainer"

apptainer run --cleanenv \
  -B "$BIDS_DIR":/data \
  -B "$OUTPUT_DIR":/out \
  -B "$WORK_DIR":/work \
  -B "$FS_LICENSE":/fs/license.txt \
  "$FMRIPREP_IMAGE" \
  /data /out participant \
  --participant-label "${SUBJECT#sub-}" \
  --fs-license-file /fs/license.txt \
  --fs-subjects-dir /work/freesurfer_subjects_${SUBJECT} \
  --skip-bids-validation \
  --output-spaces MNI152NLin2009cAsym T1w \
  --nthreads 16 \
  --omp-nthreads 8 \
  --mem_mb 120000 \
  --work-dir /work \
  --fs-no-reconall

EXIT_CODE=$?

# --- Post-run validation ---
STATUS="FAILED"
FAIL_REASON=""

ANAT_DIR="$OUTPUT_DIR/fmriprep/${SUBJECT}/anat"
FUNC_DIR="$OUTPUT_DIR/fmriprep/${SUBJECT}/func"

# Paths to log files
LOG_ERR="$REPO_DIR/logs/fmriprep_${SLURM_ARRAY_JOB_ID}_${SLURM_ARRAY_TASK_ID}.err"
LOG_OUT="$REPO_DIR/logs/fmriprep_${SLURM_ARRAY_JOB_ID}_${SLURM_ARRAY_TASK_ID}.out"

# Print full paths for troubleshooting
echo "---------- LOG FILES ----------"
echo "stderr file: $LOG_ERR"
echo "stdout file: $LOG_OUT"
echo "-------------------------------"

while [ ! -s "$LOG_ERR" ]; do
    sleep 1
done
sleep 1

# Inspect logs for known failure messages
if grep -q "Exception: No T1w images found for participant .*\. All workflows require T1w images\." "$LOG_ERR" 2>/dev/null; then
    FAIL_REASON="FAILED_NO_T1W"
elif grep -q "RuntimeError: No BOLD images found for participant .* and task .*\. All workflows require BOLD images\." "$LOG_ERR" 2>/dev/null; then
    FAIL_REASON="FAILED_NO_BOLD_SCANS"
elif grep -q "KeyError: \"Metadata term 'RepetitionTime' unavailable for file" "$LOG_ERR" 2>/dev/null; then
    FAIL_REASON="FAILED_NEED_JSON_BOLD_REPETITION_TIME"
elif [ $EXIT_CODE -ne 0 ]; then
    FAIL_REASON="FAILED_EXITCODE_${EXIT_CODE}"
elif [ -d "$ANAT_DIR" ] && ls "$ANAT_DIR"/*desc-preproc_T1w.nii.gz >/dev/null 2>&1; then
    STATUS="SUCCESS"
else
    FAIL_REASON="FAILED_OUTPUT_MISSING"
fi

# Additional safeguard: downgrade SUCCESS if outputs missing
if [ "$STATUS" == "SUCCESS" ] && [ -z "$(ls "$ANAT_DIR"/*desc-preproc_T1w.nii* 2>/dev/null)" ]; then
  STATUS="FAILED_NO_T1W"
fi

STATUS_DIR="$REPO_DIR/logs/status"
mkdir -p "$STATUS_DIR"

if [ "$STATUS" = "SUCCESS" ]; then
  STATUS_FILE="$STATUS_DIR/${SUBJECT}_fmriprep_SUCCESS.txt"
else
  STATUS_FILE="$STATUS_DIR/${SUBJECT}_fmriprep_${FAIL_REASON:-FAILED}.txt"
fi

{
  echo "Status: $STATUS"
  echo "Exit Code: $EXIT_CODE"
  echo "Subject: $SUBJECT"
  echo "Job ID: $SLURM_JOB_ID"
  echo "Finished: $(date)"
} > "$STATUS_FILE"
