#!/bin/bash
#  Author : Vishnu Satheesan
#  Date : 03/07/2025 
#  version : 0.0.1
##################################
set -o pipefail
#set -x

Green='\033[0;32m'
Blue='\033[01;34m'
Purple='\033[0;35m'
Red='\033[0;31m'
NO_COLOUR="\033[0m"

list_services(){
    cluster_name=$1
     cluster=$(echo `aws ecs list-services --cluster "$cluster_name"`)
     service=$(echo "$cluster" | jq --arg env "$am_env" .serviceArns[$env])
     declare -a services
     count=0
     while IFS= read -r line; do
         parsed_line=$(echo "$line" | sed 's|.*\/||'| sed 's|"||')
         services[count]="$parsed_line"
         ((count++))
     done < <(echo "$service")
     if [[ "$count" > 0 ]]; then
         echo "Available Services"
         echo "====================="
         for ((i=0; i < count; i++)); do
             echo  "$((i+1)))  ${services[i]}"
         done
         # exit 1
     else
         echo "Cluster not found, please try again" 
         auth_function  "cluster_name"   
     fi    
     read -p "choose the conatiner: " ch_conatiner
    if [[ "$ch_conatiner" =~ ^[0-9]+$ ]]; then
        service_name=${services[ch_conatiner-1]}
        task_arn=$(aws ecs list-tasks --cluster "$cluster_name" --service-name "$service_name" )
        task_num=$(echo "$task_arn" | jq --arg env "$cluster_name" .taskArns["$env"] | sed 's|.*\/||g'| sed 's/"//g' )
        declare -a task_num_array
        count_of_task=0
        while IFS= read -r line; do
            task_num_array[count_of_task]="$line"
            ((count_of_task++))
        done < <(echo "$task_num" )       
        parsed_name=$(echo "$service_name" | sed 's|ecs.*|task-def|g')
        task_def=$(aws ecs describe-task-definition --task-definition "$parsed_name")
        task_name=$(echo $task_def | jq  .taskDefinition.containerDefinitions[0].name | sed 's|"||g')
        
        echo "1) Copy files from ECS to S3 bucket"
        echo "2) Copy files to ECS"
        read -p "Enter the number to proceed: " action
        if [[ "$action" == 2 ]]; then
            read -p "Provide the copy command to execute: " cp_command
            echo -e "The provided copy command is: ${Red} ${cp_command} ${NO_COLOUR}"
            read -p "Verify the copy command and enter 'y' to proceed: " verified
            if [[ "$count_of_task" > 1 && -n "$cp_command" && "$verified" == 'y' ]]; then
                connect_next_task="true"   
                log_file="ecs_copy_$(date +%F_%H-%M-%S).log" 
                while [ "$connect_next_task" == "true" ]; do
                    for ((i=0; i<count_of_task; i++)); do
                         echo "$((i+1))) ${task_name} ${task_num_array[i]}" | tee -a "$log_file"
                         echo -e "execusting the command aws ecs execute-command --cluster ${Red}${cluster_name}${NO_COLOUR} --task ${Red}${task_to_connect}${NO_COLOUR}  --container ${Red}${task_name}${NO_COLOUR}  --command "bash -c ${cp_command}" --interactive ${NO_COLOUR}" 
                         aws ecs execute-command --cluster "$cluster_name" --task "${task_num_array[i]}"  --container "$task_name"   --command "bash -c '${cp_command}'" --interactive | tee -a "$log_file"
                    done 
                    echo "Check  "$log_file" for more info"
                    connect_next_task="false"       

                done  
                echo "Script execution completed."   
            elif [[ -n "$cp_command" && "$verified" == 'y' ]]; then
                echo -e "execusting the command aws ecs execute-command --cluster ${Red} "$cluster_name"${NO_COLOUR} --task ${Red}"$task_num"${NO_COLOUR}  --container ${Red}"$task_name"${NO_COLOUR}   --command "bash -c ${cp_command}" --interactive ${NO_COLOUR}"
                 aws ecs execute-command --cluster "$cluster_name" --task "$task_num"  --container "$task_name"   --command "bash -c '${cp_command}'" --interactive
                echo "Script execution completed."  
            fi
        elif [[  "$action" == 1 ]]; then
            read -p "Enter the source file: " source_path
            file_name=$(echo "$source_path" | sed 's|.*/||g')
            echo $file_name
            bucket_name=$(aws s3 ls | grep -i "$am_env" | grep -v artifacts | grep -v logs | grep -v "app-" | sed -E 's/.*(rm-am.*)/\1/')
            s3_bucket_folder=s3://"$bucket_name"/logs/
            echo "$s3_bucket_folder"
            cp_command="aws s3 cp "$source_path" "$s3_bucket_folder""
            echo -e "The copy command that going to execute is: ${Red} ${cp_command} ${NO_COLOUR}"
            read -p "Verify the copy command and enter 'y' to proceed: " verified
            if [[ "$count_of_task" > 1 && -n "$cp_command" && "$verified" == 'y' ]]; then
                connect_next_task="true"    
                log_file="ecs_copy_$(date +%F_%H-%M-%S).log" 
                while [ "$connect_next_task" == "true" ]; do
                    for ((i=0; i<count_of_task; i++)); do
                         echo "$((i+1))) ${task_name} ${task_num_array[i]}" | tee -a "$log_file"
                         cp_command="aws s3 cp ${source_path} ${s3_bucket_folder}/${file_name}${i}"
                         echo "$cp_command"
                         echo -e "execusting the command aws ecs execute-command --cluster ${Red}${cluster_name}${NO_COLOUR} --task ${Red}${task_to_connect}${NO_COLOUR}  --container ${Red}${task_name}${NO_COLOUR}  --command "bash -c ${cp_command}" --interactive ${NO_COLOUR}" 
                         aws ecs execute-command --cluster "$cluster_name" --task "${task_num_array[i]}"  --container "$task_name"   --command "bash -c '${cp_command}'" --interactive
                    done 
                     connect_next_task="false"       

                done  
                echo "Script execution completed."   
            elif [[ -n "$cp_command" && "$verified" == 'y' ]]; then
                echo -e "execusting the command aws ecs execute-command --cluster ${Red} "$cluster_name"${NO_COLOUR} --task ${Red}"$task_num"${NO_COLOUR}  --container ${Red}"$task_name"${NO_COLOUR}   --command "bash -c ${cp_command}" --interactive ${NO_COLOUR}"
                 aws ecs execute-command --cluster "$cluster_name" --task "$task_num"  --container "$task_name"   --command "bash -c '${cp_command}'" --interactive
                echo "Script execution completed."  
            fi
                
        else 
             echo "Invallid input, try again......"
        fi                
    else
        echo "Invalid input, try again....."
        list_services "$cluster_name" 
    fi
           
}

auth_function(){
    cluster_name_for_function=$1
    auth_flag="false"
    auth=y
    while [ "$auth_flag" == "false" ]; do
        if [[ $auth == "y" ]]; then
            ./authenticate_am.sh --role opsnonpii --account "$account" --region "$region"
            if [[ $? == 1 ]]; then
                list_services "$cluster_name_for_function"
            else
                echo "Authenticate failed, please try again"  
                auth_function  "$cluster_name_for_function"
            fi    
            auth_flag="true"
            auth="n"
        fi     
    done
}

config_file="./am_access.json"

enviornment=$( jq '.Databases| keys[]'  "$config_file")

declare -a environment_list

count=0
while IFS= read -r line; do
    parsed_line=$(echo "$line" | sed 's|"||g' )
    environment_list[count]="$parsed_line"
    ((count++))
done < <(echo "$enviornment")
length=$(jq '.Databases| length' "$config_file")
half_length=$((length/2 + length % 2))

echo "Environments"
echo "============="
for (( i=1; i<= half_length; i++ )); do
    printf "%-5d %-20s  %-5d %-20s\n" "$((i))" "${environment_list[i - 1]}" "$((half_length + i))" "${environment_list[(i+ half_length) -1]}"
done 

read -p "Choose the environment: " choosed_number
if [[ "$choosed_number" =~ ^[0-9]+$ ]]; then
    am_env=${environment_list[choosed_number - 1]}

    account=$(jq --arg env "$am_env" '.Databases[$env].Account' am_access.json | sed 's|"||g')
    echo -e "${Green}Account you are trying to connect is: ${Blue}$account"

    region=$(jq --arg env "$am_env" '.Databases[$env].Region' am_access.json | sed 's|"||g')
    echo -e "${Green}Account region is: ${Blue}$region"

    cluster_name="rm-am-"$am_env"-cluster"
    echo -e "${Green}Cluster name is: ${Blue}$cluster_name${NO_COLOUR}"

    #checking authetication required or not
    cluster=$(aws ecs list-services --cluster "$cluster_name"  2>&1)

    if  echo "$cluster" | grep -iq "clusternotfoundexception" || echo "$cluster" | grep -iq "error" ; then
        echo -e "${RED}Cluster not found. Authenication required. Re-authenicating......"
        auth_function "$cluster_name" 
    elif echo "$cluster" | grep -q "serviceArns"; then
        echo -e "${Green}Cluster found. Proceeding......${NO_COLOUR}"
        list_services "$cluster_name" 

    fi
else
    echo "invalid input, try again"
    exit 1
fi    
