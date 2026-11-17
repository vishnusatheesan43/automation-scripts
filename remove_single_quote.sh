#!/bin/bash

#set -x

File_name=$1

declare  -A file_data

count=0

while IFS= read -r line; do
    file_data["$count"]=$line
    ((count++))
done <  $File_name

declare -A parased_data

for line in "${file_data[@]}"; do
    parsed_line=$(echo "$line" |  sed "s/'//g" )	
    parsed_data[$count]="$parsed_line"
    ((count++))
done

final_file_name="parsed_file_$(date +%H%M%S)"

echo $final_file_name

touch $final_file_name

echo "${parsed_data[@]}" > $final_file_name

	


