#!/bin/bash
#SBATCH --job-name=split_bold
#SBATCH --account=def-woodward
#SBATCH --time=01:00:00
#SBATCH --cpus-per-task=6
#SBATCH --mem=6000
#SBATCH --output=logs/split_%A_%a.out
#SBATCH --error=logs/split_%A_%a.err

module load StdEnv/2023 fsl/6.0.7.7

FMRIPREP_DIR="/scratch/$USER/fmriprep/derivatives/fmriprep"
SPLIT_DIR="/scratch/$USER/fmriprep/split_reslice_inputs"
PARTICIPANTS="/scratch/$USER/fmriprep/data/participants.tsv"

mapfile -t SUBJECTS < <(tail -n +2 "$PARTICIPANTS" | cut -f1 | sed 's/\r//')
SUBJECT="${SUBJECTS[$SLURM_ARRAY_TASK_ID]}"

if [ -z "$SUBJECT" ]; then
    echo "No subject found for index $SLURM_ARRAY_TASK_ID"
    exit 1
fi

in_subj_dir="$FMRIPREP_DIR/$SUBJECT"
out_subj_dir="$SPLIT_DIR/$SUBJECT"
mkdir -p "$out_subj_dir"

fmri_file=$(find "$in_subj_dir" -type f -name "*space-MNI152NLin2009cAsym_desc-preproc_bold.nii.gz" | head -n 1)

if [ ! -f "$fmri_file" ]; then
    echo "No fMRI file found for $SUBJECT"
    exit 1
fi

echo "Found fMRI file for $SUBJECT: $(basename "$fmri_file")"
cp "$fmri_file" "$out_subj_dir"

cd "$out_subj_dir" || exit 1

base_name=$(basename "$fmri_file" .nii.gz)

echo "Splitting $base_name.nii.gz"
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

STATUS_FILE="/scratch/$USER/fmriprep/logs/status/${SUBJECT}_split_SUCCESS.txt"
mkdir -p "$(dirname "$STATUS_FILE")"
echo "Subject: $SUBJECT" > "$STATUS_FILE"
echo "Job ID: $SLURM_JOB_ID" >> "$STATUS_FILE"
echo "Completed: $(date)" >> "$STATUS_FILE"

