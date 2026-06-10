#!/bin/bash
#SBATCH --job-name=smoothing_summary
#SBATCH --time=01:00:00
#SBATCH --nodes=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=4G
#SBATCH --account=st-toddwood-1
#SBATCH --output=logs/smoothing_summary.out
#SBATCH --error=logs/smoothing_summary.err

set -euo pipefail

REPO_DIR="/scratch/st-toddwood-1/$USER/START-fmri"

PARTICIPANTS="$REPO_DIR/data/participants.tsv"
SMOOTH_DIR="$REPO_DIR/derivatives/smoothed"
OUTPUT_CSV="$REPO_DIR/derivatives/final_smoothed_data_summary.csv"

mkdir -p "$REPO_DIR/logs"

echo "subject_ID,run_folder_name,number_of_smoothed_volumes" > "$OUTPUT_CSV"

# Read all subject IDs from participants.tsv
mapfile -t SUBJECTS < <(
    tail -n +2 "$PARTICIPANTS" |
    cut -f1 |
    tr -d '\r' |
    sed '/^$/d'
)

for SUBJECT in "${SUBJECTS[@]}"; do

    SUBJECT_DIR="$SMOOTH_DIR/$SUBJECT"

    # Subject has no output directory at all
    if [ ! -d "$SUBJECT_DIR" ]; then
        echo "$SUBJECT,," >> "$OUTPUT_CSV"
        continue
    fi

    # Find immediate subdirectories (potential run folders)
    mapfile -t RUN_DIRS < <(
        find "$SUBJECT_DIR" \
            -mindepth 1 \
            -maxdepth 1 \
            -type d | sort
    )

    # Case 1: subject contains run folders
    if [ ${#RUN_DIRS[@]} -gt 0 ]; then

        FOUND_ANY=0

        for RUN_DIR in "${RUN_DIRS[@]}"; do

            RUN_NAME=$(basename "$RUN_DIR")

            COUNT=$(find "$RUN_DIR" \
                -maxdepth 1 \
                -type f \
                -name "sr*.nii" | wc -l)

            if [ "$COUNT" -gt 0 ]; then
                echo "$SUBJECT,$RUN_NAME,$COUNT" >> "$OUTPUT_CSV"
                FOUND_ANY=1
            fi
        done

        # Run folders existed but none contained sr*.nii files
        if [ "$FOUND_ANY" -eq 0 ]; then
            echo "$SUBJECT,," >> "$OUTPUT_CSV"
        fi

    # Case 2: no run folders; count files directly under subject folder
    else

        COUNT=$(find "$SUBJECT_DIR" \
            -maxdepth 1 \
            -type f \
            -name "sr*.nii" | wc -l)

        if [ "$COUNT" -gt 0 ]; then
            echo "$SUBJECT,,$COUNT" >> "$OUTPUT_CSV"
        else
            echo "$SUBJECT,," >> "$OUTPUT_CSV"
        fi
    fi

done

echo "Finished."
echo "Summary written to:"
echo "$OUTPUT_CSV"
