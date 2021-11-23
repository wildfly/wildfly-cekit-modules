#!/bin/bash

SCRIPT_DIR=$(dirname $0)
ADDED_DIR=${SCRIPT_DIR}/added

mkdir -p $JBOSS_HOME/bin/launch

cp ${ADDED_DIR}/* $JBOSS_HOME/bin/launch
