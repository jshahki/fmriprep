# fmriprep
This is a pipeline that combines fMRIPrep with SPM25 smoothing for use by the UBC Brain Dynamics Lab.

fMRIPrep: https://fmriprep.org/en/stable/.

Statistical Parametric Mapping (SPM): https://www.fil.ion.ucl.ac.uk/spm/.

# Steps to Run the Pipeline

## Software Setup
Upon logging in to your Compute Canada cluster, please run the following code on Terminal:

```sh
cd /scratch/$USER/fmriprep

sbatch ./fmriprep_setup.sh
```

This will set up the environment for running both fMRIPrep and SPM25 smoothing.

## Running fMRIPrep on your data
After placing your BIDS organized data into the data folder, please run the following code on Terminal:

```sh
cd /scratch/$USER/fmriprep

# Set how many subjects per array task
SUB_SIZE=1

# Set the participants file
PARTICIPANTS_FILE="./data/participants.tsv"

# Check if the file exists
if [ ! -f "$PARTICIPANTS_FILE" ]; then
  echo "Error: File not found: $PARTICIPANTS_FILE"
  exit 1
fi

# Detect delimiter (tab or comma)
DELIM=$(head -n 1 "$PARTICIPANTS_FILE" | grep -o $'\t' | wc -l)
if [ "$DELIM" -ge 1 ]; then
  # It's a TSV
  CUT_CMD="cut -f1"
else
  # Assume CSV
  CUT_CMD="cut -d',' -f1"
fi

# Read subject IDs into array (skip header)
mapfile -t SUBJECTS < <(tail -n +2 "$PARTICIPANTS_FILE" | eval "$CUT_CMD" | sed 's/\r//')

# Count valid subjects
N_SUBJECTS=${#SUBJECTS[@]}

# Compute array length
array_job_length=$(( (N_SUBJECTS + SUB_SIZE - 1) / SUB_SIZE ))

# Echo info
echo "Subjects found: $N_SUBJECTS"
echo "Subjects per task: $SUB_SIZE"
echo "Number of array jobs: $array_job_length"
echo "Loaded subjects: ${SUBJECTS[*]}"

# Submit the array job
sbatch --array=0-$((array_job_length - 1)) ./fmriprep_per_subject.sh
```

## Splitting 4D Volumes into Separate 3D Volumes

This step is required for inputting the fMRI data into SPM25.

```sh
cd /scratch/$USER/fmriprep

PARTICIPANTS_FILE="./data/participants.tsv"
SUB_SIZE=1  # Subjects per job

# Read subject IDs from file (ignore header)
mapfile -t SUBJECTS < <(tail -n +2 "$PARTICIPANTS_FILE" | cut -f1 | tr -d '\r' | sed '/^$/d')

N_SUBJECTS=${#SUBJECTS[@]}
ARRAY_LENGTH=$(( (N_SUBJECTS + SUB_SIZE - 1) / SUB_SIZE ))

echo "Found $N_SUBJECTS subjects. Launching array with $ARRAY_LENGTH jobs."

sbatch --array=0-$((ARRAY_LENGTH - 1)) split_bold_volumes.sh
```

## Resizing Voxels to Reference Scan

This step is required for use of fMRI-CPCA downstream.

```sh
cd /scratch/$USER/fmriprep

PARTICIPANTS_FILE="./data/participants.tsv"
SUB_SIZE=1  # Subjects per job

# Read subject IDs from file (ignore header)
mapfile -t SUBJECTS < <(tail -n +2 "$PARTICIPANTS_FILE" | cut -f1 | tr -d '\r' | sed '/^$/d')

N_SUBJECTS=${#SUBJECTS[@]}
ARRAY_LENGTH=$(( (N_SUBJECTS + SUB_SIZE - 1) / SUB_SIZE ))

echo "Found $N_SUBJECTS subjects. Launching array with $ARRAY_LENGTH jobs."

sbatch --array=0-$((ARRAY_LENGTH - 1)) reslice_bold_volumes.sh
```

## Running SPM25 Smoothing

This step is where SPM25 smoothing is performed on the fMRI data.

```sh
cd /scratch/$USER/fmriprep

PARTICIPANTS_FILE="./data/participants.tsv"
SUB_SIZE=1  # Subjects per job

# Read subject IDs from file (ignore header)
mapfile -t SUBJECTS < <(tail -n +2 "$PARTICIPANTS_FILE" | cut -f1 | tr -d '\r' | sed '/^$/d')

N_SUBJECTS=${#SUBJECTS[@]}
ARRAY_LENGTH=$(( (N_SUBJECTS + SUB_SIZE - 1) / SUB_SIZE ))

echo "Found $N_SUBJECTS subjects. Launching array with $ARRAY_LENGTH jobs."

sbatch --export=KERNEL="8 8 8" --array=0-$((ARRAY_LENGTH - 1)) smoothing_bold_volumes.sh
```
