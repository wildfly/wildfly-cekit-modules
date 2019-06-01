#!/bin/sh
# Common Openshift WildFly scripts
if [ -z "${CONFIG_FILE}" ]; then
    echo "Make sure that launch/openshift-common.sh has been sourced before using launch/openshift-env-modules.sh"
    exit 1
fi

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
