#!/bin/sh

set -e

SCRIPT_DIR=$(dirname $0)
ADDED_DIR=${SCRIPT_DIR}/added

mkdir -p ${JBOSS_HOME}/bin/launch/
cp -p ${ADDED_DIR}/https.sh ${JBOSS_HOME}/bin/launch/
