#/bin/bash
# set -x
#########################################################
#
#This bash script will execute the command provided in each of the selected pod
#
##########################################################
RED='\033[1;91m'
GREEN='\033[1;92m'
YELLOW='\033[1;93m'
BLUE='\033[1;94m'
RESET='\033[0m'

usage(){
    local filename=${0##*/}
    printf "${BLUE}Usage:${RESET} %s [command]\n\n"  "$filename"
    printf "${BLUE}Commands:${RESET}\n\n"
    printf "  update  Update new environment namespaces to the script.\n\n"
    printf "${BLUE}Example:${RESET} \n\n"
    printf "  %s update \n\n" "$filename"
    printf "${BLUE}Note:${RESET} Make sure that you have access to AM-Helm repo.The script will clone\n" 
    printf "the repo to your WSL environment if it does not already exist.\n"
    exit 1

}



update_namespace() {
    local update=$1

    if ! command -v yq &> /dev/null; then
    echo -e "${RED}Error: 'yq' is not installed but is required to parse YAML files.${RESET}" >&2
    echo "Please install it before continue"  >&2
    exit 1
    fi

    
    if [[ -d AM-Helm && $update == "yes" ]]; then
        echo "Deleting the existing AM-Helm repo from local and cloning it again"
        rm -rf AM-Helm/ 
        
        if ! git clone git@ssh.dev.azure.com:v3/rmresults/Assessment%20Master/AM-Helm; then
            echo -e "${RED}Error: Git clone failed. Please check your SSH keys and access permissions.${RESET}" >&2
            exit
        fi    
        
    elif [[ ! -d AM-Helm ]]; then
        echo -e "${RED}AM-Helm repo doesn't exist${RESET}. Cloning the repo to continue"
        
        if ! git clone git@ssh.dev.azure.com:v3/rmresults/Assessment%20Master/AM-Helm; then
            echo -e "${RED}Error: Git clone failed. Please check your SSH keys and access permissions.${RESET}" >&2
            exit
        fi 
        
    fi      

    readarray -t config_path_list < <(find AM-Helm/Helm-config/ -name "*-master-values.yaml")

    if [ ${#config_path_list[@]} -eq 0 ]; then
    echo -e "${RED}Warning: No configuration files found from AM-helm repo. Please check the repo contains the values.yaml files.${RESET}"
    fi

    message="Hold on loading all namespace...   "
    printf "${BLUE}%s${RESET}" "$message"
    spinstr='|/-\'
    if [ -f namespace.var ]; then
        > namespace.var  
    fi    
    printf "\e[?25l"
    for i in ${config_path_list[@]}; do 
         
        temp=${spinstr#?}
        spinstr=$temp${spinstr%"$temp"}
        printf "\b\b\b[%c]" "$spinstr"
        sleep 0.1
        if [[ $i == *dont-use* ]]; then
            continue
        fi 
        namespace=$(yq '.global.namespace' ${i} | sed 's/"//g') 
        if [[ $namespace == am-* ]]; then
            echo "$namespace" >> namespace.var
        fi     
    done 
    printf "\b\b\b \e[?25h\n"

    if [ ! -s namespace.var ]; then   
        printf "${RED}Warning: namespace.var is missing or empty. Try again${RESET}\n"
        exit 1
    else    
        printf "${GREEN}Namespace update completed.${RESET}\n"
    fi
}

aks_auth () {
    echo -e "${BLUE}Executing the azure_auth.sh scipt for cluster access${RESET} "
    output=$(azure-auth.sh aks 2>&1 | tee /dev/tty) 
    if echo "$output" | grep -q "Seting azure subscription"; then 
        echo -e "${GREEN}Authenticated to Cluster${RESET}"
    elif echo "$output" | grep -q "Quiting!"; then
        echo -e "${RED}User choose quit; gracefully stopping the script execution${RESET}"
        exit 1
    else
        echo -e "${RED}Authentication failed. Execute the command again to proceed.${RESET} "
        exit 1
    fi
}


local_to_pods(){
    local -n current_pods=$1
    local local_file_path=$2
    local pod_destination_path=$3
    local namespace=$4
    local container_name=$5
    local permission=$6
    local logfile="podcopy_$(date +%F_%H-%M).log"
    for pod in "${current_pods[@]}"; do
        pod_name=$(echo $pod|awk '{print $1}')
	    pod_status=$(echo $pod|awk '{print $2}')

        if [[ "$pod_status" == "Running" ]]; then  
            echo -e "\n[Info]Copying the file........"
            echo -e "\n[info]command executing is: \nkubectl cp $local_file_path $namespace/$pod_name:$pod_destination_path -c $container_name" | tee -a "$logfile"
            kubectl cp "$local_file_path" "$namespace"/"$pod_name":"$pod_destination_path" -c "$container_name" 2>&1 | tee -a "$logfile"
            if [ $? -eq 0 ]; then
                #stipping the filename from an absolute path and saving to a variable
                file_name=$(basename "$local_file_path")
                final_filepath=${pod_destination_path%/}/${file_name}
                echo -e "\n[Info]Changing the file perimission and ownership"
                kubectl exec -it -n "$namespace" "$pod_name" -c $container_name -- bash -c "chmod ${permission} ${final_filepath} && chown www-data:apache ${final_filepath} && ls -ltr ${final_filepath}"  2>&1 | tee -a "$logfile"
            else
              echo -e "${RED}File copy failed.${RESET} Check the ${RED}${logfile}${RESET} for error details."
            fi    
        else
            echo -e  "${YELLOW}${pod_name}${RESET}status is ${RED}${pod_status}.${RESET}\nTherefore skipping the pod from copying the file" | tee -a "$logfile"
        fi
    done        
}

pods_to_local () {
    local -n current_pods=$1
    local pod_source_path=$2
    local namespace=$3
    local container_name=$4
    local logfile="localcopy_$(date +%F_%H-%M-%S).log"
    for pod in "${current_pods[@]}"; do
        pod_name=$(echo $pod|awk '{print $1}')
	    pod_status=$(echo $pod|awk '{print $2}')
        if [[ "$pod_status" == "Running" ]]; then 
            echo -e "\n[Info]Copying the file........" 
            echo -e "\n[info]command executing is: \nkubectl cp  $namespace/$pod_name:$pod_source_path $pod_name_$(basename $pod_source_path) -c $container_name" | tee -a   "$logfile" 
            kubectl cp  "$namespace"/"$pod_name":"$pod_source_path" "$pod_name"_$(basename "$pod_source_path") -c "$container_name" 2>&1 | grep -v "tar: Removing leading" | tee -a   "$logfile" 
        else
            echo -e  "${YELLOW}${pod_name}${RESET}status is ${RED}${pod_status}.${RESET}\nTherefore skipping the pod from copying the file" | tee -a "$logfile"
        fi
    done     
}

connect_pod (){
    local -n current_pods=$1
    local namespace=$2
    local container_name=$3
    local count
    local choosed_number
    local selected_pod
    local length_of_array=${#current_pods[@]}

    # echo "length =  $length_of_array"   


    if [ "$length_of_array" -gt 1 ]; then
        connect_next="yes"
        while [[ "$connect_next" == "yes" ]]; do
            count=0
            printf "\n${YELLOW}%-5s %-50s %-10s${RESET}\n" "No" "PodName" " Status"
            for pod in "${pods[@]}"; do
                pod_name=$(echo $pod|awk '{print $1}')
                pod_status=$(echo $pod|awk '{print $2}')
                printf "${YELLOW}%-5d${RESET} %-50s  %-10s\n" "${count}" "${pod_name}" "${pod_status}"
                ((count++))
            done

            read -p "Enter the corresponding number to connect: " choosed_number
            if [[ -z "$choosed_number" || ! "$choosed_number" =~ ^[0-8]+$ ]]; then
                echo -e "${RED}Invalid input. Please enter a valid number.${RESET}" >&2
                continue
            fi
            
            selected_pod=$(echo ${current_pods[${choosed_number}]} | awk '{print $1}')
            # echo "selectect pod name is: - $selected_pod"

            if [ -z "$selected_pod" ]; then
                echo -e "${RED}Unable to find the pod name with selected number. Try again${RESET}"
                continue
            fi    

            echo "Executing.................."
            echo "kubectl exec -it -n ${namespace} ${selected_pod} -c ${container_name} -- bash"

            kubectl exec -it -n ${namespace} ${selected_pod} -c ${container_name} -- bash

            echo -e "${GREEN}Do you Want to connect next pods? [y/n]${RESET} " 
            read -r next_pod

            if [[ "${next_pod,,}" == "y" || "${next_pod,,}" == "yes"  ]]; then
                connect_next="yes"
            elif [[ "${next_pod,,}" == "n" || "${next_pod,,}" == "no"  ]]; then
                connect_next="no"
            else
                echo -e  "${RED}Invalid input.Try again.${RESET}" 
                connect_next="no"
                
            fi       


        done    

        

    else
        pod_name=$(echo ${current_pods[0]}|awk '{print $1}')
        pod_status=$(echo ${current_pods[0]}|awk '{print $2}') 
        if [[ "$pod_status" == "Running" ]]; then
            echo "Executing.................."
            echo "kubectl exec -it -n ${namespace} ${pod_name} -c ${container_name} -- bash"
            kubectl exec -it -n ${namespace} ${pod_name} -c ${container_name} -- bash
        else
           echo -e  "${YELLOW}${pod_name}${RESET}status is ${RED}${pod_status}.${RESET}\n."
        fi   
    fi            

}

main () {
    #list all namespace for selection
    readarray -t namespace_list < <(cat namespace.var)
    length="${#namespace_list[@]}"
    half_length=$((length/2 + length % 2))
    read -r -p "Filter by environment (Enter for all): " environment
    if [ -n "$environment" ]; then
        for (( i=0; i<"$length"; i++ )); do
            if [[ ${namespace_list[$i]} == am-"$environment"* ]]; then
                printf "${YELLOW}%-5d${RESET} %-20s\n" "$i" "${namespace_list[$i]}"
            fi
        done
    else         
        for (( i=0; i<"$half_length"; i++ )); do
            if [[ ${namespace_list[$i]} == am-* ]]; then
                printf "${YELLOW}%-5d${RESET} %-20s ${YELLOW}%-5d${RESET} %-20s\n" "$i" "${namespace_list[$i]}" "$(( i + half_length))" "${namespace_list[(i + half_length)-1]}"                 
            fi        
        done
    fi

    read -p "Select namespace to continue: " choice

    if [[ -z "$choice" || ! "$choice" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}Invalid choice, try again.${RESET}"  >&2
        exit 1  
    elif [[ -z "${namespace_list[$choice]}" ]]; then
        echo -e "${RED}Choice out of range. That namespace doesn't exist. Try again.${RESET}" >&2
        exit 1
    else
        choosed_namespace="${namespace_list[$choice]}"
        printf "selected namespace :- ${GREEN}%s${RESET}  \n" "$choosed_namespace"    
    fi      
    namespace=$(kubectl get ns --request-timeout=2s 2>&1 | awk -v env="$choosed_namespace" '$0 ~ env {print $1}')


    if  echo -e "$namespace" | grep --quiet -i "$choosed_namespace"; then
        echo -e "${GREEN}Namespace found in current context, proceeding.${RESET}"
    else 
        echo -e "${RED}Namespace not found in current context.${RESET}"
        sub_suffix=$(echo $choosed_namespace |  awk -F'-' '{print $(NF-1)"-"$NF}' | tr '[:lower:]' '[:upper:]')
        echo -e "Select ${BLUE}$sub_suffix${RESET} subscription to continue."
        sleep 2
        aks_auth    
    fi

    declare -a deployment_name

    #fetching the deployment name without parsing to fetch the main contianer from the deployment
    readarray -t raw_deployment_names < <(kubectl get deploy -n "$choosed_namespace" -o custom-columns=:metadata.name --no-headers )

    #need to check deployments are existing before listing them
    if [ -z "$raw_deployment_names" ]; then
        echo "Unable to get the pods details. try again"
        exit 1
    fi    

    echo -e "\n${YELLOW}List of Deployments${RESET}"
    echo -e "==============="
    count=0
    for deployment in "${raw_deployment_names[@]}"; do
        parsed_deploy_name=${deployment%-*}
        printf "${YELLOW}%-1d${RESET} - %-30s\n" "$count" "$parsed_deploy_name"
        ((count++))
    done
    printf "\n=== \n"
    read -p "select a Deployment to continue: " deployment_choice

    if [[ -z "$deployment_choice" || ! "$deployment_choice" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}Invalid input, try again${RESET}" >&2
        exit 1
    elif [[ -z "${raw_deployment_names[$deployment_choice]}" ]]; then
        echo -e "${RED}Selected number is out of range. Try again.${RESET}" >&2 
        exit 1  
    fi    

    chosen_deploy=${raw_deployment_names[$deployment_choice]}
    
    declare -a pods

    readarray -t pods < <(kubectl get pods -n "$choosed_namespace" --no-headers | awk -v deploy="$chosen_deploy" '$0 ~ deploy {print $1, $3}')

    # echo " length is ${#pods[@]}"

    #making sure that pods details are exist in the variable.
    if [ "${#pods[@]}" -eq 0 ]; then
        echo -e  "${RED}Unable to find the pods. Try again.${RESET}"
        exit 1
    fi

    # echo "${pods[0]}"
    # exit 1

    main_container_name=$( kubectl get deployment "$chosen_deploy"  -n "$choosed_namespace"   -o jsonpath='{.spec.template.spec.containers[0].name}')

    if [ -z "$main_container_name" ]; then
        echo -e "${RED}Unable to find the main container name. Try again.${RESET}" >&2
        exit 1
    fi    

    echo -e  "\n${YELLOW}List of Actions${RESET}"
    echo "==================================="
    echo -e "${YELLOW}1 ${RESET}- Connect A Pod."
    echo -e "${YELLOW}2 ${RESET}- Copy A File From Local Machine to Pods."
    echo -e "${YELLOW}3 ${RESET}- Copy A File From Pods To Local Machine."
    echo -e "${YELLOW}4 ${RESET}- Execute A Command In Multiple Containers."
    echo ""

    read -p "Select one action to continue:- " action

    if [[ -z "$action" || ! "$action" =~ ^[1-4]+$ ]]; then
        echo -e  "${RED}Invalid input. Try again.${RESET}" >&2
        exit 1
    fi    

    if [ "$action" -eq 2 ]; then
        read -p "Enter the local file path: " local_file_path 
        read -p "Enter the destination path in the pod: " pod_destination_path
        echo -e "${YELLOW}Enter the permission to set for the copied file (e.g. 644, 755):${RESET}"
        echo -e "${YELLOW}Default value is 644. Click enter to proceed with that.${RESET}"
        read -r -p ":> " file_permission
        file_permission=${file_permission:-644}
        if [[ -n "$local_file_path" && -n "$pod_destination_path" ]]; then 
            
            local_to_pods pods "$local_file_path" "$pod_destination_path" "$choosed_namespace" "$main_container_name" "$file_permission"
            
        else 
            if [ -z "$local_file_path" ]; then
                echo -e "${RED}Invalid input for local file path, try again${RESET}"
            elif [ -z "$pod_destination_path" ]; then
                echo -e "${RED}Invalid input for pod destination path, try again${RESET}"
            fi        

        fi

    elif [ "$action" -eq 3 ]; then
        read -p "Enter the source path from the pod: " pod_source_path
        if [ -n "$pod_source_path" ]; then 
            
            pods_to_local pods "$pod_source_path" "$choosed_namespace" "$main_container_name"
             
        else 
            echo -e "${RED}Invalid input pod source path, try again${RESET} "
        fi  

    elif [ "$action" -eq 4 ];  then
        read -p "Enter the command to execute: " user_command  
        logfile="podcopy_$(date +%F_%H-%M-%S).log"
        if [ -n "$user_command" ]; then
            for pod in "${pods[@]}"; do
                pod_name=$(echo $pod|awk '{print $1}')
	            pod_status=$(echo $pod|awk '{print $2}')  

                if [[ "$pod_status" == "Running" ]]; then  
                    echo -e "\n[info]command executing is: \nkubectl exec -it $pod_name -c $main_container_name -n $choosed_namespace -- bash -c ${user_command}" | tee -a "$logfile"
                    kubectl exec -it "$pod_name" -c "$main_container_name" -n "$choosed_namespace" -- bash -c "${user_command}" 2>&1 | tee -a "$logfile" 
                else
                    echo -e  "${YELLOW}${pod_name}${RESET}status is ${RED}${pod_status}.${RESET}\nTherefore skipping the pod from copying the file" | tee -a "$logfile"
                fi        
            done
        else
            echo -e "${RED}Invalid input for command, try again${RESET}"
        fi 

    elif [ "$action" -eq 1 ]; then
        
        connect_pod pods "$choosed_namespace" "$main_container_name"

    fi   
}

if [[ "$#" == 1 && "$1" == "update" ]]; then
    update_namespace yes 
elif [[ "$#" == 1 && "$1" != "update" ]]; then
    usage
elif [[ "$#" == 0 ]]; then
    if [ ! -s namespace.var ]; then
        update_namespace
        if [ "$?" -eq 0 ]; then
        main
        fi
    else
        main
    fi    
fi
