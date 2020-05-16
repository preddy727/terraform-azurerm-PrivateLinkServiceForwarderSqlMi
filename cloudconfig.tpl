#!/bin/bash
echo "$(date) starting cloud_init script" > /tmp/cloud_init.out
mkdir -p /usr/bin/configureForwarding
echo "$(date) adding variable sqlManagedInstance=${sql_mi_fqdn} to .sql_mi.vars"
echo "export sqlManagedInstance=${sql_mi_fqdn}" > /usr/bin/configureForwarding/.sql_mi.vars
{
cat <<-"EOF" > /usr/bin/configureForwarding/configureForwarding.sh
#!/bin/bash
# Reference
#  + https://unix.stackexchange.com/questions/20784/how-can-i-resolve-a-hostname-to-an-ip-address-in-a-bash-script
#

# source variables from file
DIR="$( cd "$( dirname "$BASH_SOURCE[0]" )" >/dev/null 2>&1 && pwd )"
. $DIR/.sql_mi.vars

for h in $sqlManagedInstance
do
   host $h 2>&1 > /dev/null
  if [ $? -eq 0 ] 
  then
    ip=`host $h | awk '/has address/ { print $4 }'`

    if [ -n "$ip" ]; then
      echo "$h IP is $ip"
    else
      echo "ERROR: $h is a FQDN but could not resolve hostname $h".
      exit 1
    fi
  else
    echo "ERROR: $h is not a FQDN"
    exit 2
  fi

  forwardPorts=`sudo firewall-cmd --zone=public --list-forward-ports`

  if [ -n "$forwardPorts" ]
  then
    toaddr=""
    for property in $(echo $forwardPorts | tr ":" "\n")
    do
      toaddr=`echo $property | awk -F"=" '/toaddr/ { print $2 }'`
    done
    if [ $ip == $toaddr ]
    then
      echo "No changes in IP $ip for $h"
    else
      echo "Changing port forwarding for $h from $toaddr to $ip"
      sudo firewall-cmd --permanent --zone=public --remove-forward-port=port=1433:proto=tcp:toport=1433:toaddr=$toaddr > /dev/null
      sudo firewall-cmd --permanent --zone=public --add-forward-port=port=1433:proto=tcp:toport=1433:toaddr=$ip > /dev/null
      sudo firewall-cmd --reload > /dev/null
    fi
  else
    echo "Configuring port forwarding for $h to $ip"
    sudo firewall-cmd --permanent --zone=public --add-service=mssql > /dev/null
    sudo firewall-cmd --permanent --zone=public --add-masquerade > /dev/null
    sudo firewall-cmd --permanent --zone=public --add-forward-port=port=1433:proto=tcp:toport=1433:toaddr=$ip > /dev/null
    sudo firewall-cmd --reload > /dev/null
  fi

done
EOF
} 2>&1 | tee -a /tmp/cloud_init.out
chmod +x /usr/bin/configureForwarding/configureForwarding.sh
echo "* * * * * /usr/bin/configureForwarding/configureForwarding.sh" > ~/mycron
crontab ~/mycron
/bin/rm -rf ~/mycron
echo "$(date) done with cloud_init script" >> /tmp/cloud_init.out
