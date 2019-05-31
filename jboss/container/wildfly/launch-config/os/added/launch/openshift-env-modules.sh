#!/bin/sh
# Common Openshift WildFly scripts

source $JBOSS_HOME/bin/launch/openshift-common.sh

CONFIGURE_ENV_SCRIPTS=(
)

if [ -f /opt/run-java/proxy-options ]; then
    CONFIGURE_ENV_SCRIPTS+=(/opt/run-java/proxy-options)
fi

if [ -f $JBOSS_HOME/bin/launch/jboss_modules_system_pkgs.sh ]; then
    CONFIGURE_ENV_SCRIPTS+=($JBOSS_HOME/bin/launch/jboss_modules_system_pkgs.sh)
fi