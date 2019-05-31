#!/bin/sh
# Common Openshift WildFly scripts

source $JBOSS_HOME/bin/launch/openshift-common.sh

CONFIGURE_CLI_SCRIPTS=(
)

if [ -f $JBOSS_HOME/bin/launch/mysql.sh ]; then
    CONFIGURE_CLI_SCRIPTS+=($JBOSS_HOME/bin/launch/mysql.sh)
fi

if [ -f $JBOSS_HOME/bin/launch/postgresql.sh ]; then
    CONFIGURE_CLI_SCRIPTS+=($JBOSS_HOME/bin/launch/postgresql.sh)
fi

if [ -f $JBOSS_HOME/bin/launch/datasource.sh ]; then
    CONFIGURE_CLI_SCRIPTS+=($JBOSS_HOME/bin/launch/datasource.sh)
fi