#!/bin/sh

set -e

SCRIPT_DIR=$(dirname $0)
ADDED_DIR=${SCRIPT_DIR}/added

mkdir -p ${JBOSS_HOME}/bin/launch/
cp -p ${ADDED_DIR}/launch/admin.sh ${JBOSS_HOME}/bin/launch/
cp -p ${ADDED_DIR}/launch/management-common.sh ${JBOSS_HOME}/bin/launch/
