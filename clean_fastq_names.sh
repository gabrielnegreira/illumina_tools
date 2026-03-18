#!/bin/bash
#This is a simple script that cleans fastq file names to retain only the sample name and the R1 or R2 identifier.
#OBS: It assumes that there is only one read, or one read pair per sample!
#OBS2: It also assumes that samples it names follow this structure: <SAMPLE_NAME>_<UNECESSARY_INFO>_<READ_ID>.<FILE_FORMAT>
#      It will basically merge the first string before the first `_` with the string after the last `_`.
#      It might fail if the fastq file names do not follow this convention. 
set -euo pipefail
IFS=$'\n\t'

# --- preflight --- 
##set usage helper
set -euo pipefail

usage() {
  cat <<EOF
Usage: sbatch $(basename "$0") [options]

Required:
  --fastq_dir <path>        Path to the location where the fastq files are.
  --read1_id <chr>          A string specifying how the Read 1 files are identified. for instance: "_R1".
  --read2_id <chr>          A string specifying how the Read 2 files are identified. for instance: "_R2". If unset, it will be assumed that the library is SE.
  -h|--help                 Shows this message.
EOF
  exit 1
}

# --- arguments ---

# Defaults
FASTQ_DIR=""
READ1_ID=""
READ2_ID=""

# Parse
while [[ $# -gt 0 ]]; do
  case $1 in
    --fastq_dir)
      FASTQ_DIR="$2"
      shift 2
      ;;
    --read1_id)
      READ1_ID="$2"
      shift 2
      ;;
    --read2_id)
      READ2_ID="$2"
      shift 2
      ;;
    -h|--help)
      usage
      ;;
    *)
      echo "ERROR: Unknown option '$1'" >&2
      echo "Use --help for usage information" >&2
      exit 1
      ;;
  esac
done

# Validate
if [[ -z "$FASTQ_DIR" || -z "$READ1_ID" ]]; then
  echo "ERROR: --fastq_dir, and --read1_id are required" >&2
  usage
fi

echo ">>> Parameters:"
echo "    Fastq directory:    $FASTQ_DIR"
echo "    Read1 id string:    $READ1_ID"
echo "    Read2 id string:    $READ2_ID"
echo

#--- actual code ---
#list all files in the directory
mapfile -t fq_files < <( find "$FASTQ_DIR" -maxdepth 1 -type f -regextype posix-extended -regex '.*\.(fastq|fq)(\.gz)?$' | xargs -I {} realpath {})

#now we define the sample names, considering they are the first part of the file name before the first `_` character.
mapfile -t sample_names < <(
    for file in "${fq_files[@]}"; do
        file_name=$(basename "$file")
        echo ${file_name%%_*}
    done | sort -u
)

echo found a total of ${#sample_names[@]} samples in a total of ${#fq_files[@]} files. 

#now for each sample, check how many files we find
for sample_name in ${sample_names[@]}; do
    mapfile -t sample_files < <( find "$FASTQ_DIR" -maxdepth 1 -type f -regextype posix-extended -regex ".*/${sample_name}_.*\.(fastq|fq)(\.gz)?\$" )
    
    if [[ ${#sample_files[@]} -gt 2 ]]; then
        echo "[ERROR] found more than 2 files for sample $sample_name" >&2
        exit 1
    fi
    
    if [[ ${#sample_files[@]} == 0 ]]; then
        echo "[ERROR] could not find any file for sample $sample_name" >&2
        exit 1
    fi
    
    if [[ ${#sample_files[@]} == 1 ]]; then
        echo "[INFO] found only 1 file for sample $sample_name. Assuming SE library:"
    fi
    
    if [[ ${#sample_files[@]} == 2 ]]; then
        echo "[INFO] found 2 files for sample $sample_name. Assuming PE library:"
    fi

    for file in ${sample_files[@]}; do
        file_name=$( basename "$file" )
        file_dir=$(  dirname "$file" )
        read_id_and_ext="${file_name##*_}"
        
        # Add R prefix only if not already present
        if [[ "$read_id_and_ext" =~ ^R ]]; then
            new_file_name="${sample_name}_${read_id_and_ext}"
        else
            new_file_name="${sample_name}_R${read_id_and_ext}"
        fi
        echo "       $file_name -> $new_file_name"
        mv "${file_dir}/${file_name}" "${file_dir}/${new_file_name}"
    done
done