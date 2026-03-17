#!/bin/bash

#This is a simple script that takes as input a directory and outputs a tsv file with sample, read1 and read2 fastq file paths.
#This is meant to generate a file list to be used with slurm arrays later. 

#parameters
#INPUTS_DIR= #path to inputs directory
#OUTPUT_FILE= #path to output file
READ1_ID="_R1"
READ2_ID="_R2"
FILE_EXTENSION=".fastq.gz"

usage() {
  echo "Usage: write_file_tsv.sh -i <input_dir> -o <output_dir>"
  exit 1
}

while getopts ":i:o:h" opt; do
  case $opt in
    i) INPUTS_DIR="$OPTARG" ;;
    o) OUTPUT_FILE="$OPTARG" ;;
    h) usage ;;
    \?) echo "Invalid option -$OPTARG" >&2; usage ;;
    :)  echo "Option -$OPTARG requires an argument." >&2; usage ;;
  esac
done

# Validate mandatory parameters
if [[ -z "$INPUTS_DIR" || -z "$OUTPUT_FILE" ]]; then
  echo "ERROR: -i and -o are mandatory."
  usage
fi

echo ">>> Parameters:"
echo "    Input directory:  $INPUTS_DIR"
echo "    Output file: $OUTPUT_FILE"
echo


#find read1 files
read1_files=$(find "$INPUTS_DIR" -mindepth 1 -maxdepth 1 -type f -iname "*${READ1_ID}*${FILE_EXTENSION}")
read1_files=($read1_files) #convert to array
echo found ${#read1_files[@]} samples
{
    # Loop over all R1 files (non-recursive)
    for r1 in ${read1_files[@]}; do
        #define the sample name (anything left to `READ1_ID`)
        filename=$(basename "$r1")
        sample=${filename%%${READ1_ID}*} 

        #find the read 2 file
        r2=$(find "$INPUTS_DIR" -mindepth 1 -maxdepth 1 -type f -iname "*${sample}${READ2_ID}*${FILE_EXTENSION}")
        r2=($r2)
        #check if only 1 read2 file was found
        if [ ${#r2[@]} -gt 1 ]; then
        echo "[ERROR]: found ${#r2[@]} files for read2."
        exit 1
        fi
       printf "%s\t%s\t%s\n" "$sample" "$r1" "$r2" #`%s` mean `string`
    done
} > "${OUTPUT_FILE}"
echo file stored in "${OUTPUT_FILE}"