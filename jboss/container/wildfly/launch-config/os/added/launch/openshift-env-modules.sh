#!/bin/sh
# Common Openshift WildFly scripts

source $JBOSS_HOME/bin/launch/openshift-common.sh

CONFIGURE_ENV_SCRIPTS=(
)

if [ -n "${ENV_SCRIPT_CANDIDATES}" ]; then
    for script in "${ENV_SCRIPT_CANDIDATES[@]}"
    do
        if [ -f "${script}" ]; then
            CONFIGURE_ENV_SCRIPTS+=(${script})
        fi
    done
else
    echo "No ENV_SCRIPT_CANDIDATES were set!"
fi
