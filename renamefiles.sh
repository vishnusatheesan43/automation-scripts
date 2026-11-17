#!/bin/bash

read -p "Enter the folder path: " folder_path

# -d checks if the directory actually exists, which is safer than just -z
if [[ -z "$folder_path" || ! -d "$folder_path" ]]; then
    echo "Invalid or non-existent path"
    exit 1
fi

read -p "Provide suffix for the file names: " suffix_to_append

# Use a regular array (lowercase 'a'), NOT an associative array (uppercase 'A')
declare -a file_names_array

# Enable nullglob so empty folders don't cause literal '*' errors
shopt -s nullglob

# Crucial: Move the wildcard '*' OUTSIDE the double quotes to allow globbing
for item in "$folder_path"/*; do
   if [[ -f "$item" ]]; then
      file_names_array+=( "${item##*/}" )
   fi
done

# Check if any files were found
if [[ ${#file_names_array[@]} -eq 0 ]]; then
    echo "No files found in the specified directory."
    exit 0
fi

declare -a renamed_files_array

# Loop using indices to safely handle file names with spaces
for i in "${file_names_array[@]}"; do
    # Strip extension, append suffix, re-add extension, and prepend folder path
    filename="${i%.*}"
    extension="${i##*.}"
    
    # If the file had no extension, don't append a stray dot
    if [[ "$filename" == "$extension" ]]; then
        new_file_name="${folder_path}/${filename}_${suffix_to_append}"
    else
        new_file_name="${folder_path}/${filename}_${suffix_to_append}.${extension}"
    fi
    
    # Correct array append syntax
    renamed_files_array+=( "$new_file_name" )
done

echo "New file names are:"
printf '%s\n' "${renamed_files_array[@]}"

