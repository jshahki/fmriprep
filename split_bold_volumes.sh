#!/bin/bash
#SBATCH --job-name=split_bold
#SBATCH --account=st-toddwood-1
#SBATCH --nodes=1
#SBATCH --time=02:00:00
#SBATCH --cpus-per-task=1
#SBATCH --mem-per-cpu=30000
#SBATCH --output=logs/split_%A_%a.out
#SBATCH --error=logs/split_%A_%a.err

set -euo pipefail

module purge
module load gcc/9.4.0
module load apptainer/1.3.1

# ==========================
# PATH SETUP
# ==========================

REPO_DIR="/scratch/st-toddwood-1/$USER/fmriprep"

FMRIPREP_IMAGE="$REPO_DIR/fmriprep-20.2.7.sif"
FMRIPREP_DIR="$REPO_DIR/derivatives/fmriprep"
SPLIT_DIR="$REPO_DIR/split_reslice_inputs"
PARTICIPANTS="$REPO_DIR/data/participants.tsv"

mkdir -p "$SPLIT_DIR"

mapfile -t SUBJECTS < <(tail -n +2 "$PARTICIPANTS" | cut -f1 | sed 's/\r//')
SUBJECT="${SUBJECTS[$SLURM_ARRAY_TASK_ID]}"

if [ -z "${SUBJECT:-}" ]; then
    echo "No subject found for index $SLURM_ARRAY_TASK_ID"
    exit 1
fi

in_subj_dir="$FMRIPREP_DIR/$SUBJECT"
out_subj_dir="$SPLIT_DIR/$SUBJECT"

mkdir -p "$out_subj_dir"

echo "====================================="
echo "Processing subject: $SUBJECT"
echo "====================================="

# ==========================
# COLLECT FILES
# ==========================

all_bold_files=($(find "$in_subj_dir" -type f -name "*space-MNI152NLin2009cAsym_desc-preproc_bold.nii.gz"))

if [ ${#all_bold_files[@]} -eq 0 ]; then
    echo "No fMRI files found for $SUBJECT"
    exit 1
fi

# ==========================
# LABEL DETECTION (GLOBAL)
# ==========================

task_labels=($(printf "%s\n" "${all_bold_files[@]}" | grep -o "task-[A-Za-z0-9_-]\+" | sort -u))
MULTI_TASK=false
[ ${#task_labels[@]} -gt 1 ] && MULTI_TASK=true

ses_labels=($(printf "%s\n" "${all_bold_files[@]}" | grep -o "ses-[A-Za-z0-9_-]\+" | sort -u))
MULTI_SES=false
[ ${#ses_labels[@]} -gt 1 ] && MULTI_SES=true

acq_labels=($(printf "%s\n" "${all_bold_files[@]}" | grep -o "acq-[A-Za-z0-9_-]\+" | sort -u))
MULTI_ACQ=false
[ ${#acq_labels[@]} -gt 1 ] && MULTI_ACQ=true

echo_labels=($(printf "%s\n" "${all_bold_files[@]}" | grep -o "echo-[A-Za-z0-9_-]\+" | sort -u))
MULTI_ECHO=false
[ ${#echo_labels[@]} -gt 1 ] && MULTI_ECHO=true

run_labels=($(printf "%s\n" "${all_bold_files[@]}" | grep -o "run-[0-9]\+" | sed 's/run-0*/run-/' | sort -u))
MULTI_RUN=false
[ ${#run_labels[@]} -gt 1 ] && MULTI_RUN=true

# ==========================
# OUTPUT LABEL BUILDER
# ==========================

build_output_label() {

    local file="$1"
    local base
    base=$(basename "$file")

    local parts=()

    local task_label ses_label acq_label echo_label run_label

    task_label=$(echo "$base" | grep -o "task-[A-Za-z0-9_-]\+" || true)
    ses_label=$(echo "$base" | grep -o "ses-[A-Za-z0-9_-]\+" || true)
    acq_label=$(echo "$base" | grep -o "acq-[A-Za-z0-9_-]\+" || true)
    echo_label=$(echo "$base" | grep -o "echo-[A-Za-z0-9_-]\+" || true)
    run_label=$(echo "$base" | grep -o "run-[0-9]\+" | sed 's/run-0*//' || true)

    # TASK
    if [ "$MULTI_TASK" = true ] && [ -n "$task_label" ]; then
        parts+=("$task_label")
    fi

    # SES
    if [ "$MULTI_SES" = true ] && [ -n "$ses_label" ]; then
        parts+=("$ses_label")
    fi

    # ACQ
    if [ "$MULTI_ACQ" = true ] && [ -n "$acq_label" ]; then
        parts+=("$acq_label")
    fi

    # ECHO
    if [ "$MULTI_ECHO" = true ] && [ -n "$echo_label" ]; then
        parts+=("$echo_label")
    fi

    # RUN
    if [ "$MULTI_RUN" = true ] && [ -n "$run_label" ]; then
        parts+=("run-$run_label")
    fi

    # JOIN
    local out=""
    for p in "${parts[@]}"; do
        if [ -z "$out" ]; then
            out="$p"
        else
            out="${out}_${p}"
        fi
    done

    echo "$out"
}

# ==========================
# PROCESS FUNCTION
# ==========================

process_bold_file() {

    local bold_file="$1"
    local output_dir="$2"

    mkdir -p "$output_dir"

    echo "Processing: $(basename "$bold_file")"
    echo "Output dir: $output_dir"

    cp "$bold_file" "$output_dir"
    cd "$output_dir"

    local base_name
    base_name=$(basename "$bold_file" .nii.gz)

    apptainer exec "$FMRIPREP_IMAGE" fslsplit \
        "$base_name.nii.gz" \
        "${base_name}_tmp_" \
        -t

    if ! ls ${base_name}_tmp_*.nii.gz >/dev/null 2>&1; then
        echo "ERROR: fslsplit failed for $base_name"
        return 1
    fi

    i=1
    for f in ${base_name}_tmp_*.nii.gz; do
        suffix=$(printf "%04d" "$i")
        new_name="${base_name}_${suffix}.nii.gz"

        mv "$f" "$new_name"
        gunzip -f "$new_name"

        ((i++))
    done

    rm -f "$base_name.nii.gz"
    rm -f ${base_name}_tmp_*.nii.gz 2>/dev/null || true

    echo "Finished: $base_name"
}

# ==========================
# MAIN LOOP
# ==========================

for f in "${all_bold_files[@]}"; do

    out_dir="$out_subj_dir/$(build_output_label "$f")"

    process_bold_file "$f" "$out_dir"
done

# ==========================
# LOG SUCCESS
# ==========================

STATUS_FILE="$REPO_DIR/logs/status/${SUBJECT}_split_SUCCESS.txt"
mkdir -p "$(dirname "$STATUS_FILE")"

{
    echo "Subject: $SUBJECT"
    echo "Job ID: $SLURM_JOB_ID"
    echo "Completed: $(date)"
} > "$STATUS_FILE"

echo "Finished processing $SUBJECT"
echo "====================================="
