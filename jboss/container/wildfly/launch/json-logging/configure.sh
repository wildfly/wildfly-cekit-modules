#!/bin/sh

set -e

SCRIPT_DIR=$(dirname $0)
ADDED_DIR=${SCRIPT_DIR}/added

mkdir -p ${JBOSS_HOME}/standalone/configuration/
cp -p ${ADDED_DIR}/logging.properties ${JBOSS_HOME}/standalone/configuration/

mkdir -p ${JBOSS_HOME}/bin/launch/
cp -p ${ADDED_DIR}/launch/json_logging.sh ${JBOSS_HOME}/bin/launch/
