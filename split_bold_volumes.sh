#!/bin/bash
#SBATCH --job-name=split_bold
#SBATCH --account=def-woodward
#SBATCH --time=15:00:00
#SBATCH --cpus-per-task=1
#SBATCH --mem-per-cpu=30000
#SBATCH --output=logs/split_%A_%a.out
#SBATCH --error=logs/split_%A_%a.err

module load StdEnv/2023 fsl/6.0.7.7

# ==========================
# PATH SETUP
# ==========================
REPO_DIR="/scratch/$USER/START-fmri"
FMRIPREP_DIR="$REPO_DIR/derivatives/fmriprep"
SPLIT_DIR="$REPO_DIR/split_reslice_inputs"
PARTICIPANTS="$REPO_DIR/data/participants.tsv"

mapfile -t SUBJECTS < <(tail -n +2 "$PARTICIPANTS" | cut -f1 | sed 's/\r//')
SUBJECT="${SUBJECTS[$SLURM_ARRAY_TASK_ID]}"

if [ -z "$SUBJECT" ]; then
    echo "No subject found for index $SLURM_ARRAY_TASK_ID"
    exit 1
fi

in_subj_dir="$FMRIPREP_DIR/$SUBJECT"
out_subj_dir="$SPLIT_DIR/$SUBJECT"

# Detect session directories (e.g., ses-01, ses-pre, etc.)
ses_dirs=($(find "$in_subj_dir" -maxdepth 1 -type d -name "ses-*"))
has_sessions=false
if [ ${#ses_dirs[@]} -gt 0 ]; then
    has_sessions=true
fi

mkdir -p "$out_subj_dir"

echo "====================================="
echo "Processing subject: $SUBJECT"
echo "Has session folders: $has_sessions"
echo "====================================="

# ==========================
# FUNCTION DEFINITIONS
# ==========================

# Function to split a single BOLD file into volumes
process_bold_file() {
    local bold_file="$1"
    local output_dir="$2"

    mkdir -p "$output_dir"
    echo "Copying $(basename "$bold_file") to $output_dir"
    cp "$bold_file" "$output_dir"

    cd "$output_dir" || exit 1
    local base_name
    base_name=$(basename "$bold_file" .nii.gz)

    echo "Splitting $base_name.nii.gz ..."
    fslsplit "$base_name.nii.gz" "${base_name}_tmp_" -t

    i=1
    for f in ${base_name}_tmp_*.nii.gz; do
        suffix=$(printf "%04d" $i)
        new_name="${base_name}_${suffix}.nii.gz"
        mv "$f" "$new_name"
        gunzip -f "$new_name"
        ((i++))
    done

    rm -f "$base_name.nii.gz"
    echo "Finished splitting $base_name"
}

# ==========================
# MAIN LOGIC
# ==========================

if [ "$has_sessions" = false ]; then
    # Case 1: No explicit ses-* directories
    bold_files=($(find "$in_subj_dir" -type f -name "*space-MNI152NLin2009cAsym_desc-preproc_bold.nii.gz"))

    if [ ${#bold_files[@]} -eq 0 ]; then
        echo "No fMRI files found for $SUBJECT"
        exit 1
    fi

    # Try detecting sessions from filenames (e.g., ses-pre, ses-01)
    session_labels=($(printf "%s\n" "${bold_files[@]}" | grep -o "ses-[A-Za-z0-9]\+" | sort -u))
    if [ ${#session_labels[@]} -gt 0 ]; then
        echo "Detected session labels in filenames: ${session_labels[*]}"
        has_sessions=true
    fi
fi

if [ "$has_sessions" = true ]; then
    # Multi-session (either real folders or from filenames)
    echo "Detected multiple or named sessions for $SUBJECT"

    if [ ${#ses_dirs[@]} -eq 0 ]; then
        # No actual session directories — build from filenames instead
        ses_dirs=("${session_labels[@]}")
    fi

    for ses_entry in "${ses_dirs[@]}"; do
        # Determine whether it's a directory or just a session label
        if [ -d "$ses_entry" ]; then
            ses_label=$(basename "$ses_entry")
            ses_bold_files=($(find "$ses_entry" -type f -name "*space-MNI152NLin2009cAsym_desc-preproc_bold.nii.gz"))
        else
            ses_label="$ses_entry"
            ses_bold_files=($(find "$in_subj_dir" -type f -name "*${ses_label}_*space-MNI152NLin2009cAsym_desc-preproc_bold.nii.gz"))
        fi

        if [ ${#ses_bold_files[@]} -eq 0 ]; then
            echo "No fMRI files found for $SUBJECT $ses_label"
            continue
        fi

        # Detect runs
        run_labels=($(printf "%s\n" "${ses_bold_files[@]}" | grep -o "run-[0-9]\+" | sed 's/run-0*/run-/' | sort -u))
        if [ ${#run_labels[@]} -eq 0 ]; then
            echo "Detected single run for $ses_label"
            for f in "${ses_bold_files[@]}"; do
                out_dir_ses="$out_subj_dir/$ses_label"
                process_bold_file "$f" "$out_dir_ses"
            done
        else
            echo "Detected runs for $ses_label: ${run_labels[*]}"
            for f in "${ses_bold_files[@]}"; do
                run_label=$(basename "$f" | grep -o "run-[0-9]\+" | sed 's/run-0*/run-/')
                ses_run_dir="${ses_label}_${run_label}"
                out_dir_ses_run="$out_subj_dir/$ses_run_dir"
                process_bold_file "$f" "$out_dir_ses_run"
            done
        fi
    done

else
    # Case 2: Truly no sessions at all
    echo "Detected single-session structure for $SUBJECT"
    bold_files=($(find "$in_subj_dir" -type f -name "*space-MNI152NLin2009cAsym_desc-preproc_bold.nii.gz"))

    run_labels=($(printf "%s\n" "${bold_files[@]}" | grep -o "run-[0-9]\+" | sed 's/run-0*/run-/' | sort -u))
    if [ ${#run_labels[@]} -eq 0 ]; then
        echo "Detected single run, single session"
        for f in "${bold_files[@]}"; do
            process_bold_file "$f" "$out_subj_dir"
        done
    else
        echo "Detected runs for $SUBJECT: ${run_labels[*]}"
        for f in "${bold_files[@]}"; do
            run_label=$(basename "$f" | grep -o "run-[0-9]\+" | sed 's/run-0*/run-/')
            out_dir_run="$out_subj_dir/$run_label"
            process_bold_file "$f" "$out_dir_run"
        done
    fi
fi

# ==========================
# LOGGING SUCCESS
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

