#!/bin/bash
#SBATCH --job-name=reslice_bold
#SBATCH --account=def-woodward
#SBATCH --time=01:00:00
#SBATCH --cpus-per-task=8
#SBATCH --mem=6000
#SBATCH --output=logs/reslice_%A_%a.out
#SBATCH --error=logs/reslice_%A_%a.err

module load StdEnv/2023 matlab/2024b.1

SPLIT_INPUT_DIR="/scratch/$USER/fmriprep/split_reslice_inputs"
RESLICE_OUTPUT_DIR="/scratch/$USER/fmriprep/split_reslice_outputs"
SPM_PATH="/scratch/$USER/fmriprep/tools/spm_25.01.02/spm"
REFERENCE_SCAN="/scratch/$USER/fmriprep/tools/3x3x3_reference_scan.hdr"
PARTICIPANTS="/scratch/$USER/fmriprep/data/participants.tsv"

mapfile -t SUBJECTS < <(tail -n +2 "$PARTICIPANTS" | cut -f1 | sed 's/\r//')
SUBJECT="${SUBJECTS[$SLURM_ARRAY_TASK_ID]}"

if [ -z "$SUBJECT" ]; then
    echo "No subject found for index $SLURM_ARRAY_TASK_ID"
    exit 1
fi

matlab -nodisplay -r "addpath('$SPM_PATH'); spm('Defaults','fMRI'); spm_jobman('initcfg'); subj_dir = fullfile('$SPLIT_INPUT_DIR', '$SUBJECT'); out_dir = fullfile('$RESLICE_OUTPUT_DIR', '$SUBJECT'); ref = '$REFERENCE_SCAN'; mkdir(out_dir); files = dir(fullfile(subj_dir, '*bold_*.nii')); for i = 1:length(files); src = fullfile(subj_dir, files(i).name); spm_reslice({ref, src}, struct('which',1,'interp',4,'wrap',[0 0 0],'mask',0,'mean',0)); movefile(fullfile(subj_dir, ['r' files(i).name]), fullfile(out_dir, ['r_' files(i).name])); end; exit;"

STATUS_FILE="/scratch/$USER/fmriprep/logs/status/${SUBJECT}_reslice_SUCCESS.txt"
mkdir -p "$(dirname "$STATUS_FILE")"
echo "Subject: $SUBJECT" > "$STATUS_FILE"
echo "Job ID: $SLURM_JOB_ID" >> "$STATUS_FILE"
echo "Completed: $(date)" >> "$STATUS_FILE"

