#!/usr/bin/env bash
#SBATCH --ntasks=1 --cpus-per-task=7
#SBATCH --time=01:00:00
#SBATCH --job-name=run_fastp
***REMOVED***
***REMOVED***
#SBATCH --mail-type=BEGIN,END,FAIL

#this script takes as input a read1 and optionally a read2 fastq file and clean them using fastp. 
#It can also be used in slurm arrays by providing a file list (tsv format)

set -euo pipefail
IFS=$'\n\t'

usage() {
  cat <<EOF
Usage: sbatch run_fastp.sh [options]

Options:
  -1 <read1>         Read 1 file (required unless -l provided)
  -2 <read2>         Read 2 file (optional; if present script runs paired mode)
  -s <sample>        Sample name (optional; if omitted it is inferred from read1 filename)
  -o <output_dir>    Output directory (required)
  -t <threads>       Threads (optional, integer, max 16). Default: 16
  -l <listfile>      Use listfile (overrides -1 -2 -s). Each line: SAMPLE[TAB]READ1 for SE or SAMPLE[TAB]READ1[TAB]READ2 for PE
                     If running as a SLURM array, the array index selects the line.
  -h                 Show this help
EOF
  exit 1
}

# defaults
N_THREADS=8

# parse options (note new -l)
while getopts ":1:2:s:o:t:l:h" opt; do
  case "$opt" in
    1) READ1="$OPTARG" ;;
    2) READ2="$OPTARG" ;;
    s) SAMPLE="$OPTARG" ;;
    o) OUTPUTS_DIR="$OPTARG" ;;
    t) N_THREADS="$OPTARG" ;;
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
if [[ ! ${OUTPUTS_DIR+x} || ! ${READ1+x} ]]; then
  echo "ERROR: -1 <read1> and -o <output_dir> are required." >&2
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
echo "    Output directory: $OUTPUTS_DIR"
echo "    Threads:     $N_THREADS"
echo

#Cap threads to max 16
if (( N_THREADS > 16 )); then
    echo "⚠️  Requested $N_THREADS threads, but fastp supports a maximum of 16."
    N_THREADS=16
fi

#get the modules
module --force purge
module load calcua/2023a calcua/all
module load fastp

#run fastqc
mkdir -p "$OUTPUTS_DIR"

start_time=$(date +%s)

#if sample is not set, infer it from the name of read 1
if [[ -z "${SAMPLE:-}" ]]; then
    echo "Sample name was not provided, inferring it from READ1 file name..."
    base="$(basename -- "$READ1")"
    base="${base%%.*}" 
    SAMPLE="$(printf '%s' "$base" | sed -E 's/([_.-])[Rr]?([12])$//')"
    echo "Sample name defined as: ${SAMPLE}"
fi

#if both reads were provided (PE reads)...
if [[ ${READ2+x} ]]; then
    fastp -i "$READ1" \
          -I "$READ2" \
          -o "${OUTPUTS_DIR}/${SAMPLE}_R1_clean.fastq.gz" \
          -O "${OUTPUTS_DIR}/${SAMPLE}_R2_clean.fastq.gz" \
          --html "${OUTPUTS_DIR}/${SAMPLE}_report.html" \
          --json "${OUTPUTS_DIR}/${SAMPLE}_report.json" \
          --dedup --dup_calc_accuracy 6 --thread "$N_THREADS"
else
    fastp -i "$READ1" \
          -o "${OUTPUTS_DIR}/${SAMPLE}_R1_clean.fastq.gz" \
          --html "${OUTPUTS_DIR}/${SAMPLE}_report.html" \
          --json "${OUTPUTS_DIR}/${SAMPLE}_report.json" \
          --dedup --dup_calc_accuracy 6 --thread "$N_THREADS"
fi


end_time=$(date +%s)
echo "Job completed in $(( (end_time - start_time)/60 )) minutes."