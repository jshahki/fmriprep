#!/bin/bash
#SBATCH --job-name=split_bold
#SBATCH --account=st-toddwood-1
#SBATCH --nodes=1
#SBATCH --time=02:00:00
#SBATCH --cpus-per-task=2
#SBATCH --mem=100G
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
SPLIT_DIR="$REPO_DIR/derivatives/split"
PARTICIPANTS="$REPO_DIR/data/participants.tsv"

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
echo "Input dir: $in_subj_dir"
echo "Output dir: $out_subj_dir"
echo "====================================="

# ==========================
# FIND ALL BOLD FILES (FIXED CORE BUG)
# ==========================

mapfile -t all_bold_files < <(
    find "$in_subj_dir" -type f -name "*_space-MNI152NLin2009cAsym_desc-preproc_bold.nii.gz"
)

# DEBUG BLOCK (YOU ASKED FOR THIS)
echo "Searching in: $in_subj_dir"
echo "Found BOLD files:"
printf '%s\n' "${all_bold_files[@]:-NONE}"
echo "Count: ${#all_bold_files[@]}"

if [ "${#all_bold_files[@]}" -eq 0 ]; then
    echo "ERROR: No BOLD files found"
    exit 1
fi

# ==========================
# DETECT GLOBAL LABEL CONDITIONS
# ==========================

mapfile -t task_list < <(printf "%s\n" "${all_bold_files[@]}" | grep -oE "task-[^_/]+" | sort -u)
mapfile -t ses_list  < <(printf "%s\n" "${all_bold_files[@]}" | grep -oE "ses-[^_/]+"  | sort -u)
mapfile -t acq_list  < <(printf "%s\n" "${all_bold_files[@]}" | grep -oE "acq-[^_/]+"  | sort -u)
mapfile -t echo_list < <(printf "%s\n" "${all_bold_files[@]}" | grep -oE "echo-[^_/]+" | sort -u)
mapfile -t run_list  < <(printf "%s\n" "${all_bold_files[@]}" | grep -oE "run-[0-9]+"  | sort -u)

multi_task=false
if [ "${#task_list[@]}" -gt 1 ]; then
    multi_task=true
fi

echo "Tasks found: ${task_list[*]:-none}"
echo "Sessions found: ${ses_list[*]:-none}"
echo "Acq found: ${acq_list[*]:-none}"
echo "Echo found: ${echo_list[*]:-none}"
echo "Runs found: ${run_list[*]:-none}"

# ==========================
# SPLIT FUNCTION
# ==========================

process_bold_file() {
    local bold_file="$1"
    local output_dir="$2"

    mkdir -p "$output_dir"
    cp "$bold_file" "$output_dir"

    cd "$output_dir" || exit 1

    local base_name
    base_name=$(basename "$bold_file" .nii.gz)

    echo "Splitting: $base_name"

    apptainer exec "$FMRIPREP_IMAGE" fslsplit \
        "$base_name.nii.gz" "${base_name}_tmp_" -t

    if ! ls ${base_name}_tmp_*.nii.gz >/dev/null 2>&1; then
        echo "ERROR: fslsplit failed for $base_name"
        return 1
    fi

    i=1
    for f in ${base_name}_tmp_*.nii.gz; do
        suffix=$(printf "%04d" "$i")
        mv "$f" "${base_name}_${suffix}.nii.gz"
        gunzip -f "${base_name}_${suffix}.nii.gz"
        ((i++))
    done

    rm -f "$base_name.nii.gz"
}

# ==========================
# MAIN LOOP
# ==========================

for f in "${all_bold_files[@]}"; do

    fname=$(basename "$f")

    ses=$(echo "$fname"  | grep -oE "ses-[^_/]+" || true)
    task=$(echo "$fname" | grep -oE "task-[^_/]+" || true)
    acq=$(echo "$fname"  | grep -oE "acq-[^_/]+" || true)
    echoe=$(echo "$fname" | grep -oE "echo-[^_/]+" || true)
    run=$(echo "$fname"  | grep -oE "run-[0-9]+"  || true)

    # --------------------------
    # BUILD OUTPUT NAME
    # --------------------------

    out_name=""

    if [ -n "$ses" ]; then
        out_name="${ses}"
    fi

    if [ "$multi_task" = true ] && [ -n "$task" ]; then
        [ -n "$out_name" ] && out_name="${out_name}_"
        out_name="${out_name}${task}"
    fi

    if [ -n "$acq" ]; then
        [ -n "$out_name" ] && out_name="${out_name}_"
        out_name="${out_name}${acq}"
    fi

    if [ -n "$echoe" ]; then
        [ -n "$out_name" ] && out_name="${out_name}_"
        out_name="${out_name}${echoe}"
    fi

    if [ -n "$run" ]; then
        [ -n "$out_name" ] && out_name="${out_name}_"
        out_name="${out_name}${run}"
    fi

    out_dir="$out_subj_dir/$out_name"

    echo "-------------------------------------"
    echo "File: $fname"
    echo "Output folder: $out_dir"
    echo "-------------------------------------"

    process_bold_file "$f" "$out_dir" || {
        echo "FAILED: $fname"
        continue
    }

done

# ==========================
# STATUS LOG
# ==========================

STATUS_FILE="$REPO_DIR/logs/status/${SUBJECT}_split_SUCCESS.txt"
mkdir -p "$(dirname "$STATUS_FILE")"

{
echo "Subject: $SUBJECT"
echo "Job ID: $SLURM_JOB_ID"
echo "Completed: $(date)"
echo "Files processed: ${#all_bold_files[@]}"
} > "$STATUS_FILE"

echo "Finished processing $SUBJECT"
echo "====================================="
