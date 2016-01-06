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

echo -e $GREEN"Creating ensemble"$WHITE

karaf_client fabric:container-create-ssh --host machine2.jbossfuse621.vagrant.local --resolver manualip --manual-ip=machine2.jbossfuse621.vagrant.local --path $HOST_RH_HOME/containers --user $SSH_USER --jvm-opts \"$JVM_APP_OPTS\" --profile jboss-fuse-minimal fabric-002
karaf_client fabric:container-create-ssh --host machine3.jbossfuse621.vagrant.local --resolver manualip --manual-ip=machine3.jbossfuse621.vagrant.local --path $HOST_RH_HOME/containers --user $SSH_USER --jvm-opts \"$JVM_APP_OPTS\" --profile jboss-fuse-minimal fabric-003

wait_for_container_status "fabric-002" "started" "--wait 300000"
wait_for_container_status "fabric-003" "started" "--wait 300000"

karaf_client fabric:ensemble-add --force fabric-002 fabric-003
wait_for_ensemble