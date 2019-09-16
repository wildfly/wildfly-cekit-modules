#!/bin/sh
set -e

SCRIPT_DIR=$(dirname $0)
ADDED_DIR=${SCRIPT_DIR}/added

cp -p ${ADDED_DIR}/launch/security-domains.sh ${JBOSS_HOME}/bin/launch/
chmod ug+x ${JBOSS_HOME}/bin/launch/security-domains.sh
cp -p ${ADDED_DIR}/launch/login-modules-common.sh ${JBOSS_HOME}/bin/launch/
chmod ug+x ${JBOSS_HOME}/bin/launch/login-modules-common.sh


