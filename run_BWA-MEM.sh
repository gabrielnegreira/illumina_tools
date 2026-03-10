#!/bin/bash

#SBATCH --ntasks=1 
#SBATCH --cpus-per-task=4
#SBATCH --time=01:00:00
#SBATCH --job-name=BWA-MEM
#SBATCH --mail-type=BEGIN,END,FAIL

#this is a simple bash script to run BWA-MEM in the Vlaams supercomputer.

#parameters

set -euo pipefail
IFS=$'\n\t'

#set usage helper
usage() {
  cat <<EOF
Usage: sbatch run_BWA-MEM.sh [options]

Options:
  -1 <read1>              Read 1 file (required unless -l provided)
  -2 <read2>              Read 2 file (optional; if present script runs paired mode)
  -r <reference genome>   path to reference genome file (fasta)
  -s <sample>             Sample name (optional; if omitted it is inferred from read1 filename)
  -o <output_dir>         Output directory (required)
  -l <listfile>           Use listfile (overrides -1 -2 -s). Each line: SAMPLE[TAB]READ1 for SE or SAMPLE[TAB]READ1[TAB]READ2 for PE
                          If running as a SLURM array, the array index selects the line.
  -h                      Show this help
EOF
  exit 1
}

# parse options (note new -l)
while getopts ":1:2:r:s:o:l:h" opt; do
  case "$opt" in
    1) READ1="$OPTARG" ;;
    2) READ2="$OPTARG" ;;
    r) REF_GENOME="$OPTARG" ;;
    s) SAMPLE="$OPTARG" ;;
    o) OUTPUTS_DIR="$OPTARG" ;;
    l) LISTFILE="$OPTARG" ;;
    h) usage ;;
    \?) echo "Invalid option -$OPTARG" >&2; usage ;;
    :)  echo "Option -$OPTARG requires an argument." >&2; usage ;;
  esac
done

# If -l provided, ignore -1 -2 -s (explicit)
if [[ ${LISTFILE+x} ]]; then
    if [[ ! ${SLURM_ARRAY_TASK_ID+x} ]]; then
        echo "[ERROR] Option \`-l\` is meant to be used with slurm arrays only!" >&2
        usage
    else
        unset READ1 READ2 SAMPLE >/dev/null 2>&1 || true
        LINE=$(sed -n "${SLURM_ARRAY_TASK_ID}p" "$LISTFILE") #tells wich line of the tsv file to read based on the SLURM_ARRAY_TASK_ID
        SAMPLE=$(echo "$LINE" | cut -f1)
        READ1=$(echo "$LINE" | cut -f2)
        READ2=$(echo "$LINE" | cut -f3)
    fi
fi

# Basic validation
if [[ ! ${OUTPUTS_DIR+x} || ! ${READ1+x} || ! ${REF_GENOME+x} ]]; then
  echo "ERROR: -1 <read1> -r <REF_GENOME> and -o <output_dir> are required." >&2
  usage
fi

echo ">>> Parameters:"
echo "    READ1 file:  $READ1"
if [[ ${READ2+x} ]]; then
    echo "    READ2 file:  $READ2"
fi
if [[ ${SAMPLE+x} ]]; then
    echo "    sample name:  $SAMPLE"
fi
echo "    Reference genome: $REF_GENOME"
echo "    Output directory: $OUTPUTS_DIR"
echo


#internal variables
threads=${SLURM_CPUS_PER_TASK:-1}


#get the modules
module --force purge
module load calcua/2025a calcua/all
module load BWA/0.7.19-GCCcore-14.2.0 SAMtools/1.22.1-GCC-14.2.0

#store the time the run started
start_time=$(date +%s)

#create output directory
mkdir -p "$OUTPUTS_DIR"

#test if the reference genome was indexed by bwa. If not, task 1 will index it while the other tasks wait
#to make sure indexing was finished, task 1 will create a `.index_bwa_done` dummy file to signal the conclusion of indexing. 
index_done="${REF_GENOME}.index_bwa_done"

if [[ ! -f "$index_done" ]]; then
  if (( SLURM_ARRAY_TASK_ID == 1 )); then
    echo "[INFO] Index not found. Task 1 (this task) will build it..."
    bwa index "$REF_GENOME"
    touch "$index_done"                # marker created only when bwa index finishes
    echo "[INFO] Index built."
  else
    echo "[INFO] Waiting for index to finish..."
    while [[ ! -f "$index_done" ]]; do
      sleep 20
    done
    echo "[INFO] Index detected."
  fi
fi

#finally we map the reads
printf "mapping reads of sample %s:\nread1: %s\nread2: %s\nUsing %s threads.\n" "$SAMPLE" "$READ1" "$READ2" "$threads"
temp_prefix="temp_${SLURM_ARRAY_TASK_ID}_$$"
bwa mem -t "$threads" \
  -R "@RG\tID:${SAMPLE}\tSM:${SAMPLE}\tPL:ILLUMINA" \
  "$REF_GENOME" "$READ1" "$READ2" \
| samtools sort -@ "$threads" -T $temp_prefix -n -O BAM - \
| samtools fixmate -m - - \
| samtools sort -@ "$threads" -T $temp_prefix -O BAM - \
| samtools markdup -@ "$threads" -s - "$OUTPUTS_DIR/${SAMPLE}.bam"

#display how long the run took
end_time=$(date +%s)
echo "Job completed in $(( (end_time - start_time)/60 )) minutes."