#!/bin/sh
set -e

SCRIPT_DIR=$(dirname $0)
ADDED_DIR=${SCRIPT_DIR}/added

mkdir -p ${JBOSS_HOME}/bin/launch
cp -r ${ADDED_DIR}/launch/deploymentScanner.sh ${JBOSS_HOME}/bin/launch

chmod g+rwX $JBOSS_HOME/bin/launch/deploymentScanner.sh
