#!/bin/bash
#SBATCH --job-name=split_bold
#SBATCH --account=st-toddwood-1
#SBATCH --nodes=1
#SBATCH --time=02:00:00
#SBATCH --cpus-per-task=8
#SBATCH --mem-per-cpu=5000
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
echo "CPUs: $SLURM_CPUS_PER_TASK"
echo "====================================="

# ==========================
# FIND ALL BOLD FILES
# ==========================

mapfile -t all_bold_files < <(
    find "$in_subj_dir" -type f -name "*_space-MNI152NLin2009cAsym_desc-preproc_bold.nii.gz"
)

echo "Searching in: $in_subj_dir"
echo "Found BOLD files:"
printf '%s\n' "${all_bold_files[@]:-NONE}"
echo "Count: ${#all_bold_files[@]}"

if [ "${#all_bold_files[@]}" -eq 0 ]; then
    echo "ERROR: No BOLD files found"
    exit 1
fi

# ==========================
# LABEL DETECTION
# ==========================

mapfile -t task_list < <(printf "%s\n" "${all_bold_files[@]}" | grep -oE "task-[^_/]+" | sort -u)

multi_task=false
if [ "${#task_list[@]}" -gt 1 ]; then
    multi_task=true
fi

echo "Tasks found: ${task_list[*]}"

# ==========================
# PROCESS FUNCTION (FIXED)
# ==========================

process_bold_file() {
    local bold_file="$1"

    local fname
    fname=$(basename "$bold_file")

    local ses task acq echoe run

    ses=$(echo "$fname"  | grep -oE "ses-[^_/]+" || true)
    task=$(echo "$fname" | grep -oE "task-[^_/]+" || true)
    acq=$(echo "$fname"  | grep -oE "acq-[^_/]+" || true)
    echoe=$(echo "$fname" | grep -oE "echo-[^_/]+" || true)
    run=$(echo "$fname"  | grep -oE "run-[0-9]+"  || true)

    # --------------------------
    # BUILD OUTPUT NAME
    # --------------------------

    local out_name=""

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

    local out_dir="$out_subj_dir/$out_name"
    mkdir -p "$out_dir"

    # ==========================
    # COPY FILE (FIX #3 SAFE CHECK)
    # ==========================

    local base_name
    base_name=$(basename "$bold_file" .nii.gz)

    cp "$bold_file" "$out_dir/"

    if [ ! -f "$out_dir/$base_name.nii.gz" ]; then
        echo "ERROR: missing copied file for $fname" >&2
        return 1
    fi

    echo "START SPLIT: $fname -> $out_name"

    # ==========================
    # FSLSPLIT (FIX #2 LOGGING)
    # ==========================

    apptainer exec "$FMRIPREP_IMAGE" fslsplit \
        "$out_dir/$base_name.nii.gz" \
        "$out_dir/${base_name}_tmp_" -t \
        >>"$out_dir/split_stdout.log" \
        2>>"$out_dir/split_stderr.log"

    if ! ls "$out_dir/${base_name}_tmp_"*.nii.gz >/dev/null 2>&1; then
        echo "ERROR: fslsplit failed for $fname" >&2
        return 1
    fi

    # ==========================
    # RENAME VOLUMES
    # ==========================

    local i=1
    for f in "$out_dir/${base_name}_tmp_"*.nii.gz; do
        local suffix
        suffix=$(printf "%04d" "$i")

        mv "$f" "$out_dir/${base_name}_${suffix}.nii.gz"
        gunzip -f "$out_dir/${base_name}_${suffix}.nii.gz"

        ((i++))
    done

    rm -f "$out_dir/$base_name.nii.gz"

    echo "FINISHED: $fname"
}

export -f process_bold_file
export FMRIPREP_IMAGE
export out_subj_dir
export multi_task

# ==========================
# PARALLEL EXECUTION (FIX #4 SAFE BASH PARALLELISM)
# ==========================

N_JOBS="$SLURM_CPUS_PER_TASK"

echo "Running with $N_JOBS parallel workers"

job_count=0

for f in "${all_bold_files[@]}"; do
    process_bold_file "$f" \
        >"$out_subj_dir/job_${job_count}.out" \
        2>&1 &

    ((job_count++))

    if (( job_count >= N_JOBS )); then
        wait
        job_count=0
    fi
done

wait

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
