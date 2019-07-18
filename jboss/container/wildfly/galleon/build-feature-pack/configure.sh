#!/bin/sh
# Configure module
set -e
if [ -z "$WILDFLY_VERSION" ]; then
  echo "WILDFLY_VERSION must be set"
  exit 1
fi

if [ -z "$WILDFLY_DIST_MAVEN_LOCATION" ]; then
  echo "WILDFLY_DIST_MAVEN_LOCATION must be set to the URL to WildFly dist maven artifact"
  exit 1
fi

if [ -z "$OFFLINER_URLS" ]; then
  echo "OFFLINER_URLS must be set, format \"--url <maven repo url> [--url <maven repo url>]"
  exit 1
fi

if [ -z "$GALLEON_FP_PATH" ]; then
  echo "GALLEON_FP_PATH must be set to the galleon feature-pack maven project location"
  exit 1
fi

if [ -z "$GALLEON_FP_COMMON_PKG_NAME" ]; then
  echo "GALLEON_FP_COMMON_PKG_NAME must be set to the name of the galleon package containing common content"
  exit 1
fi

# Download offliner runtime
curl -v -L http://repo.maven.apache.org/maven2/com/redhat/red/offliner/offliner/$OFFLINER_VERSION/offliner-$OFFLINER_VERSION.jar > /tmp/offliner.jar

# Download offliner file
curl -v -L $WILDFLY_DIST_MAVEN_LOCATION/$WILDFLY_VERSION/wildfly-dist-$WILDFLY_VERSION-artifact-list.txt > /tmp/offliner.txt

# Populate maven repo, in case we have errors (occur when using locally built WildFly, no md5 nor sha files), cd to /tmp where error.logs is written.
cd /tmp
java -jar /tmp/offliner.jar $OFFLINER_URLS \
/tmp/offliner.txt --dir $GALLEON_LOCAL_MAVEN_REPO > /dev/null
cd ..

rm /tmp/offliner.jar && rm /tmp/offliner.txt

if [ -f $JBOSS_CONTAINER_MAVEN_35_MODULE/scl-enable-maven ]; then
  # required to have maven enabled.
  source $JBOSS_CONTAINER_MAVEN_35_MODULE/scl-enable-maven
fi

if [ -d "$JBOSS_HOME/modules" ]; then
  # Copy JBOSS_HOME/modules content (custom os modules) to modules.
  MODULES_DIR=$GALLEON_FP_PATH/src/main/resources/modules/
  mkdir -p $MODULES_DIR
  cp -r $JBOSS_HOME/modules/* $MODULES_DIR
  rm -rf $JBOSS_HOME/modules/
fi


# Install the producers and universe
mvn -f "$JBOSS_CONTAINER_WILDFLY_S2I_MODULE"/galleon/provisioning/jboss-s2i-producers/pom.xml install -Dmaven.repo.local=$GALLEON_LOCAL_MAVEN_REPO \
--settings $HOME/.m2/settings.xml
mvn -f "$JBOSS_CONTAINER_WILDFLY_S2I_MODULE"/galleon/provisioning/jboss-s2i-universe/pom.xml install -Dmaven.repo.local=$GALLEON_LOCAL_MAVEN_REPO \
--settings $HOME/.m2/settings.xml

# Copy JBOSS_HOME content (custom os content) to common package dir
CONTENT_DIR=$GALLEON_FP_PATH/src/main/resources/packages/$GALLEON_FP_COMMON_PKG_NAME/content
mkdir -p $CONTENT_DIR
cp -r $JBOSS_HOME/* $CONTENT_DIR
rm -rf $JBOSS_HOME/*

# Build Galleon s2i feature-pack and install it in local maven repository
mvn -f $GALLEON_FP_PATH/pom.xml install \
--settings $HOME/.m2/settings.xml -Dmaven.repo.local=$GALLEON_LOCAL_MAVEN_REPO $GALLEON_BUILD_FP_MAVEN_ARGS_APPEND

keepFP=${DEBUG_GALLEON_FP_SRC:-false}
if [ "x$keepFP" == "xfalse" ]; then
 echo Removing feature-pack src.
 # Remove the feature-pack src
 rm -rf $GALLEON_FP_PATH
fi
