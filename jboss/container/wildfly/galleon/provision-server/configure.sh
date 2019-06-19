#!/bin/sh
# Configure module
set -e
SCRIPT_DIR=$(dirname $0)

if [ ! -d "$GALLEON_DEFAULT_SERVER" ]; then
  echo "GALLEON_DEFAULT_SERVER must be set to the absolute path to directory that contains galleon default server provisioning maven project."
  exit 1
fi

if [ -f $JBOSS_CONTAINER_MAVEN_35_MODULE/scl-enable-maven ]; then
  # required to have maven enabled.
  source $JBOSS_CONTAINER_MAVEN_35_MODULE/scl-enable-maven
fi

# Provision the default server
# The active profiles are jboss-community-repository and securecentral
mvn -f $GALLEON_DEFAULT_SERVER/pom.xml package -Dmaven.repo.local=$MAVEN_LOCAL_REPO \
--settings $HOME/.m2/settings.xml $GALLEON_DEFAULT_SERVER_PROVISION_MAVEN_ARGS_APPEND

TARGET_DIR=$GALLEON_DEFAULT_SERVER/target
SERVER_DIR=$TARGET_DIR/server

if [ ! -d $SERVER_DIR ]; then
  echo "Error, no server provisioned in $SERVER_DIR"
  exit 1
fi
# Install WildFly server
rm -rf $JBOSS_HOME
cp -r $SERVER_DIR $JBOSS_HOME
rm -r $TARGET_DIR

chown -R jboss:root $JBOSS_HOME && chmod -R ug+rwX $JBOSS_HOME 
chown -R jboss:root $HOME
chmod -R ug+rwX $MAVEN_LOCAL_REPO
