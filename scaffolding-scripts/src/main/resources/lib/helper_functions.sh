#!/usr/bin/env bash

###
# #%L
# GarethHealy :: JBoss Fuse Setup :: Scaffolding Scripts
# %%
# Copyright (C) 2013 - 2015 Gareth Healy
# %%
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#      http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# #L%
###

# Set colours
GREEN="\e[32m"
RED="\e[41m\e[37m\e[1m"
YELLOW="\e[33m"
WHITE="\e[0m"

# Kill all running karaf instances
function kill_karaf_instances()
{
	echo -e $GREEN"Killing all karaf processes"$WHITE
	ps -e -opid,command | grep java | grep karaf | grep -v grep | awk '{ print $1; }' | xargs kill  -KILL 2> /dev/null
}

function ssh_copy_scripts() 
{
	ENV_FUSE_HOST=$1

	echo -e $GREEN"Copying scripts to $ENV_FUSE_HOST"$WHITE

	ssh $SSH_USER@$ENV_FUSE_HOST "rm -fr $HOST_RH_HOME/scripts"
	ssh $SSH_USER@$ENV_FUSE_HOST "mkdir $HOST_RH_HOME/scripts"
	scp -r ./ $SSH_USER@$ENV_FUSE_HOST:$HOST_RH_HOME/scripts

	ssh $SSH_USER@$ENV_FUSE_HOST "chmod -R 755 $HOST_RH_HOME/scripts/*.sh $HOST_RH_HOME/scripts/lib/*.sh $HOST_RH_HOME/scripts/commands/*.sh $HOST_RH_HOME/scripts/envs/$DEPLOYMENT_ENVIRONMENT/*.sh"
} # ssh_copy_scripts

function ssh_kill_fuse() 
{	
	ENV_FUSE_HOST=$1

	echo -e $GREEN"Killing containers for $ENV_FUSE_HOST"$WHITE

	ssh $SSH_USER@$ENV_FUSE_HOST "export HOST_RH_HOME=$HOST_RH_HOME;$HOST_RH_HOME/scripts/commands/kill-fuse.sh $DEPLOYMENT_ENVIRONMENT"
} # ssh_kill_fuse()

function ssh_clear_karaf_and_containers()
{
	ENV_FUSE_HOST=$1

	echo -e $GREEN"Clearing down intermediate karaf data directories and containers for $ENV_FUSE_HOST"$WHITE

	ssh $SSH_USER@$ENV_FUSE_HOST "export HOST_RH_HOME=$HOST_RH_HOME;$HOST_RH_HOME/scripts/commands/clear_karaf.sh $DEPLOYMENT_ENVIRONMENT"
} # kill the karaf container

function clear_karaf_container() 
{
	rm -fr $HOST_FUSE_HOME/instances $HOST_FUSE_HOME/data $HOST_FUSE_HOME/lock $HOST_FUSE_HOME/processes
}

function clear_other_folders()
{
	rm -fr $HOST_RH_HOME/containers $HOME/.m2/repository/ /tmp/fabric8* /tmp/jboss-fuse*
}

function karaf_commands()
{
	CLIENT_INVOCATION="$HOST_FUSE_HOME/bin/client -u $KARAF_USER -p $KARAF_PASSWORD -r 60"
}

function karaf_client()
{
	karaf_commands
	
	# Flatten the arguments to a single string to avoid interpretation by the  
	command_string=""
	for a in "${@}"; do
		command_string+="$a "
	done
	
	echo -e $YELLOW"Executing Karaf CMD: $CLIENT_INVOCATION \"$command_string\""$WHITE
	response=$($CLIENT_INVOCATION "$command_string")
	echo -e $YELLOW"Response: $response"$WHITE
}

function start_fuse()
{
	start_and_wait_for_karaf
}

function start_and_wait_for_karaf()
{
    echo -e $GREEN"Launching Fuse"$WHITE
    echo -e $GREEN"Fuse home: '$HOST_FUSE_HOME'"$WHITE

	$HOST_FUSE_HOME/bin/start

    i=0.0
    c=0
    sleeptime=1

    echo -e $YELLOW"Waiting for Fuse to become available..."$WHITE
    echo -e $YELLOW"Executing Karaf CMD: $CLIENT_INVOCATION help 2> /dev/null| grep fabric:create | wc -l"$WHITE
    echo ""
    while [ $c -le 0 ]
    do
        sleep $sleeptime
        i=$(echo $sleeptime | bc)
        c=$($CLIENT_INVOCATION help 2> /dev/null| grep fabric:create | wc -l)
    done

    karaf_client wait-for-service --timeout 60000 --exception io.fabric8.api.BootstrapComplete
    karaf_client wait-for-command fabric create
}

function wait_for_container_status()
{
	local CONTAINER=$1
	local STATUS=$2

    echo -e $YELLOW"Waiting for fabric command: container-status"$WHITE
	karaf_client "wait-for-command fabric container-status"

    echo -e $YELLOW"Executing Karaf CMD: $CLIENT_INVOCATION \"fabric:container-status --status $STATUS $CONTAINER\""$WHITE
    status_message=$($CLIENT_INVOCATION "fabric:container-status --status $STATUS $CONTAINER")

    echo -e $YELLOW"Container $CONTAINER status is: $status_message"$WHITE

    is_container_failed=$(echo "$status_message" | grep -i -c "Overall Status: failed")
    is_container_success=$(echo "$status_message" | grep -i -c "Overall Status: success")
    if (( $is_container_failed == 1 || $is_container_success == 0 )); then
        echo -e $RED"$CONTAINER has not reached status $STATUS. Check logs."$WHITE
        exit 2
    fi

    echo -e $YELLOW"Executing Karaf CMD: $CLIENT_INVOCATION \"container-connect $CONTAINER list\" | grep -F -i Failed 2> /dev/null"$WHITE
	failed_bundles=$($CLIENT_INVOCATION "container-connect $CONTAINER list" | grep -F -i Failed 2> /dev/null)
	if [ "x$failed_bundles" != "x" ]; then
		echo -e $RED"$CONTAINER bundles in status \"Failed\": $failed_bundles"$WHITE
	fi

	echo -e $GREEN"$CONTAINER has status of $STATUS"$WHITE
} # wait_for_container_status

function wait_for_ensemble() 
{
	local _MAX_WAITING=180
	set +x
	local time_elapsed=0
	local is_ensemble_available=0
	local ensemble_exists=0
	((ensemble_size=${#FABRIC_HOSTS[@]}+1))

	echo -n -e $YELLOW"Waiting (max ${_MAX_WAITING}s) for fabric ensemble with" $ensemble_size "servers to be available..."$WHITE
	echo ""
	while (( $is_ensemble_available <= 0 ))
	do
		sleep 5
		time_elapsed=$((1 + $time_elapsed))
		#printf "\r%-2d sec before forced timeout..." $(( $_MAX_WAITING - ( $time_elapsed / 2 ) ))

		status_message=$(check_fabric_ensemble)
		printf "\r%-2d sec before forced timeout. Current Status: [%-60s] " "$(( $_MAX_WAITING - ( $time_elapsed / 2 ) ))" "$status_message"

	    is_ensemble_available=$(echo "$status_message" | grep -c -i healthy )
		if (( ($time_elapsed / 2 ) >= $_MAX_WAITING ))
			then
			echo -e $RED"Waited $(($time_elapsed  / 2)) seconds for ensemble. Launch aborted. "$WHITE
			exit 1
		fi
	done
	echo ""

	echo -e $GREEN"Ensemble became available in $(($time_elapsed  / 2)) seconds"$WHITE
	set -x
} # wait_for_ensemble

## useful function for initial fabric ensemble creation
function check_fabric_ensemble()
{
	## execute fabric:ensemble list command to find member names
    ENSEMBLE_LIST=$($CLIENT_INVOCATION "fabric:ensemble-list")
    ENSEMBLE_LIST_ARRAY=(${ENSEMBLE_LIST//\\n/})

	## ensemble-list command returns [id] header so reduce actual count by one. 
	num_live_nodes=${#ENSEMBLE_LIST_ARRAY[@]}
	((num_live_nodes=num_live_nodes-1))
	((ensemble_size=${#FABRIC_HOSTS[@]}+1))

	if [ $num_live_nodes -eq $ensemble_size ]; then
		echo -e $GREEN"Healthy ensemble"$WHITE
		return $num_live_nodes
	fi

	echo -e $RED"broken ensemble values are: ENSEMBLE_LIST_ARRAY: ${ENSEMBLE_LIST_ARRAY[@]},num_live_nodes=$num_live_nodes,ensemble_size=$ensemble_size"$WHITE
	return $num_live_nodes
}

function get_git_url()
{
	git_host=$($CLIENT_INVOCATION "fabric:cluster-list git")
	git_url=`echo $git_host | grep 'http://' | awk '{print $NF;}'`

	echo -e $GREEN"GitURL $git_url"$WHITE
}
