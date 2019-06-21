#!/bin/bash

SCRIPT_DIR="$(dirname $0)"
BATS_SERVER_CONFIG_FILE_DIRECTORY="${SCRIPT_DIR}/test-common/configuration"
BATS_SERVER_CONFIG_FILE_NAME="standalone-openshift.xml"
BATS_SERVER_CONFIG_FILE="${BATS_SERVER_CONFIG_FILE_DIRECTORY}/${BATS_SERVER_CONFIG_FILE_NAME}"
BATS_CONFIG_ENV_FILE="${BATS_SERVER_CONFIG_FILE_DIRECTORY}/bats-config.env"


if [ -z "${BATS_STANDALONE_XML_URL}" ] && [ -f "${BATS_CONFIG_ENV_FILE}" ]; then
    source "${BATS_CONFIG_ENV_FILE}"
fi

if [ -z "${BATS_STANDALONE_XML_URL}" ] && [ ! -f "${BATS_SERVER_CONFIG_FILE}" ]; then
    echo "No ${BATS_SERVER_CONFIG_FILE} found and no download url specified via BATS_STANDALONE_XML_URL or in ${BATS_CONFIG_ENV_FILE}"
    exit 1
fi

if [ -n "${BATS_STANDALONE_XML_URL}" ]; then
    if [ -f "${BATS_SERVER_CONFIG_FILE}" ]; then
        echo "Skipping download as ${BATS_SERVER_CONFIG_FILE} already exists!"
    else
        cd "${BATS_SERVER_CONFIG_FILE_DIRECTORY}"
        wget "${BATS_SERVER_CONFIG_FILE_NAME}" "${BATS_STANDALONE_XML_URL}"
        cd ../..
    fi
fi

rc=0
failed=()
tap=""
# passing --tap will enable TAP output for CI
if [ "${1}" = "--tap" ]; then
    echo "TAP version 13"
    tap="--tap"
fi

for testName in `find ./ -name *.bats`;
do
    echo ${testName};
    bats ${tap} ${testName}
    if [ "$?" -ne 0 ]; then
	rc=1
	failed+=(${testName})
    fi

done

if [ "${rc}" -ne 0 ]; then
    echo "There are test failures! "
    printf '[FAILED]: %s\n' "${failed[@]}"
fi

exit ${rc}
