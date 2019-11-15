#!/bin/sh
# Configure module
set -e

if [ ! -d "$GALLEON_DEFAULT_SERVER" ]; then
  echo "GALLEON_DEFAULT_SERVER must be set to the absolute path to directory that contains galleon default server provisioning file."
  exit 1
fi

if [ -f $JBOSS_CONTAINER_MAVEN_35_MODULE/scl-enable-maven ]; then
  # required to have maven enabled.
  source $JBOSS_CONTAINER_MAVEN_35_MODULE/scl-enable-maven
fi

# Provision the default server
# The active profiles are jboss-community-repository and securecentral
cp "$GALLEON_DEFAULT_SERVER"/provisioning.xml "$JBOSS_CONTAINER_WILDFLY_S2I_GALLEON_PROVISION"
mvn -f "$JBOSS_CONTAINER_WILDFLY_S2I_GALLEON_PROVISION"/pom.xml package -Dmaven.repo.local=$TMP_GALLEON_LOCAL_MAVEN_REPO \
--settings $GALLEON_MAVEN_BUILD_IMG_SETTINGS_XML $GALLEON_DEFAULT_SERVER_PROVISION_MAVEN_ARGS_APPEND

TARGET_DIR="$JBOSS_CONTAINER_WILDFLY_S2I_GALLEON_PROVISION"/target
SERVER_DIR=$TARGET_DIR/server

if [ ! -d "$GALLEON_LOCAL_MAVEN_REPO" ]; then
  cp -r $TMP_GALLEON_LOCAL_MAVEN_REPO $GALLEON_LOCAL_MAVEN_REPO
fi

rm -rf $TMP_GALLEON_LOCAL_MAVEN_REPO

if [ ! -d $SERVER_DIR ]; then
  echo "Error, no server provisioned in $SERVER_DIR"
  exit 1
fi
# Install WildFly server
rm -rf $JBOSS_HOME
cp -r $SERVER_DIR $JBOSS_HOME
rm -r $TARGET_DIR

chown -R jboss:root $JBOSS_HOME && chmod -R ug+rwX $JBOSS_HOME 

# Remove java tmp perf data dir owned by 185
rm -rf /tmp/hsperfdata_jboss
