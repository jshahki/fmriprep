#!/bin/bash
#SBATCH --job-name=fmriprep
#SBATCH --time=12:00:00
#SBATCH --cpus-per-task=20
#SBATCH --mem-per-cpu=10000
#SBATCH --account=def-woodward
#SBATCH --output=logs/fmriprep_%A_%a.out
#SBATCH --error=logs/fmriprep_%A_%a.err

module load StdEnv/2023
module load apptainer

REPO_DIR="/scratch/$USER/fmriprep"
BIDS_DIR="$REPO_DIR/data"
OUTPUT_DIR="$REPO_DIR/derivatives"
WORK_DIR="$REPO_DIR/work"
FS_LICENSE="$REPO_DIR/freesurfer/license.txt"
SUBJECTS_FILE="$BIDS_DIR/participants.tsv"
FMRIPREP_IMAGE="$REPO_DIR/fmriprep-20.2.7.sif"

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
export SINGULARITYENV_MPLBACKEND=Agg
export SINGULARITYENV_FS_LICENSE=/fs/license.txt

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
  --nthreads 8 \
  --omp-nthreads 8 \
  --mem_mb 32000 \
  --work-dir /work

STATUS_DIR="$REPO_DIR/logs/status"
mkdir -p "$STATUS_DIR"

EXIT_CODE=$?
if [ $EXIT_CODE -eq 0 ]; then
  STATUS="SUCCESS"
else
  STATUS="FAILED"
fi

STATUS_FILE="$STATUS_DIR/${SUBJECT}_${STATUS}.txt"

{
  echo "Status: $STATUS"
  echo "Exit Code: $EXIT_CODE"
  echo "Subject: $SUBJECT"
  echo "Job ID: $SLURM_JOB_ID"
  echo "Finished: $(date)"
} > "$STATUS_FILE"

