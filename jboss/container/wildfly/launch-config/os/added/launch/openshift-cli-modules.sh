#!/bin/sh
# Common Openshift WildFly scripts

if [ -z "${CONFIG_FILE}" ]; then
    echo "Make sure that launch/openshift-common.sh has been sourced before using launch/openshift-cli-modules.sh"
    exit 1
fi

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
