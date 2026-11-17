##########################################
# Author = Vishnu Satheesan
# Date = 15-07-2024
##########################################

#!/bin/bash
#set -x
db_name=$1
port=$2
temp_file=$(mktemp)

if [[ "$db_name" == "qa1" || "$db_name" == "qa2" || "$db_name" == "qa3" || "$db_name" == "qa4" || "$db_name" == "qa5" || "$db_name" == "qa6" || "$db_name" == "qa7" || "$db_name" == "qa8"  || "$db_name" == "perf1" || "$db_name" == "perf2" || "$db_name" == "perf3" || "$db_name" == "perf4" || "$db_name" == "perf5" ]]; then
        db_name=rm-"$db_name"
fi  

aws s3 ls > "$temp_file"



if  cat "$temp_file"  | grep -iq  "base-common-admin-patch-logs" ; then

   echo "Authenticated to ADMIN account. Proceeding to establish connectioin..............................." 
   auth_required=n

else

  echo "Setting the authentication to ADMIN account, please provide the MFA token when the prompt displys"
  ./authenticate_am.sh --role opsnonpii --account admin --region ap-southeast-2
   auth_required=n 

fi         

if [[ "$auth_required" == "n" ]];then
  echo "Proceeding to connect the "$db_name" Database"
  echo "Choose Read or write replica when it prompt" 
  if [[ -n "$db_name" && -z "$port" ]]; then
    ./portforward_am.sh --role opsnonpii --database-name "$db_name" --local-port 56789
  elif [[ -n "$db_name" && -n "$port" ]]; then
    ./portforward_am.sh --role opsnonpii --database-name "$db_name" --local-port "$port"
  fi
fi
