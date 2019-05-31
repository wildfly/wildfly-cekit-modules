#!/bin/sh
# Common Openshift WildFly scripts

source $JBOSS_HOME/bin/launch/openshift-common.sh

CONFIGURE_CLI_SCRIPTS=(
)

if [ -n "${CLI_SCRIPT_CANDIDATES}" ]; then
    for script in "${CLI_SCRIPT_CANDIDATES[@]}"
    do
        if [ -f "${script}" ]; then
            CONFIGURE_CLI_SCRIPTS+=(${script})
        fi
    done
else
    echo "No CLI_SCRIPT_CANDIDATES were set!"
fi
