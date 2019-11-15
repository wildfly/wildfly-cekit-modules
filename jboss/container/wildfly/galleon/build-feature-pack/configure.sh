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

deleteBuildArtifacts=${DELETE_BUILD_ARTIFACTS:-false}

ZIPPED_REPO="/tmp/artifacts/maven-repo.zip"
if [ -f "${ZIPPED_REPO}" ]; then
  echo "Found zipped repository, installing it."
  unzip ${ZIPPED_REPO} -d /tmp
  repoDir=$(find /tmp -type d -iname "*-image-builder-maven-repository")
  mv $repoDir/maven-repository "$TMP_GALLEON_LOCAL_MAVEN_REPO"
  
  if [ "x$deleteBuildArtifacts" == "xtrue"  ]; then
    echo "Build artifacts are not kept, will be removed from galleon local cache"
    cp -r $TMP_GALLEON_LOCAL_MAVEN_REPO $GALLEON_LOCAL_MAVEN_REPO
  fi
else
  # Download offliner runtime
  curl -v -L http://repo.maven.apache.org/maven2/com/redhat/red/offliner/offliner/$OFFLINER_VERSION/offliner-$OFFLINER_VERSION.jar > /tmp/offliner.jar

  # Download offliner file
  curl -v -L $WILDFLY_DIST_MAVEN_LOCATION/$WILDFLY_VERSION/wildfly-dist-$WILDFLY_VERSION-artifact-list.txt > /tmp/offliner.txt

  # Populate maven repo, in case we have errors (occur when using locally built WildFly, no md5 nor sha files), cd to /tmp where error.logs is written.
  cd /tmp
  java -jar /tmp/offliner.jar $OFFLINER_URLS \
  /tmp/offliner.txt --dir $TMP_GALLEON_LOCAL_MAVEN_REPO > /dev/null
  if [ -f ./errors.log ]; then
    echo ERRORS WHILE RETRIEVING ARTIFACTS. Offliner file is invalid or you are using a SNAPSHOT BUILD
    echo Offliner errors:
    cat ./errors.log
  fi
  cd ..

  rm /tmp/offliner.jar && rm /tmp/offliner.txt
fi

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
mvn -f "$JBOSS_CONTAINER_WILDFLY_S2I_MODULE"/galleon/provisioning/jboss-s2i-producers/pom.xml install -Dmaven.repo.local=$TMP_GALLEON_LOCAL_MAVEN_REPO \
--settings $GALLEON_MAVEN_BUILD_IMG_SETTINGS_XML
mvn -f "$JBOSS_CONTAINER_WILDFLY_S2I_MODULE"/galleon/provisioning/jboss-s2i-universe/pom.xml install -Dmaven.repo.local=$TMP_GALLEON_LOCAL_MAVEN_REPO \
--settings $GALLEON_MAVEN_BUILD_IMG_SETTINGS_XML

# Copy JBOSS_HOME content (custom os content) to common package dir
CONTENT_DIR=$GALLEON_FP_PATH/src/main/resources/packages/$GALLEON_FP_COMMON_PKG_NAME/content
mkdir -p $CONTENT_DIR
cp -r $JBOSS_HOME/* $CONTENT_DIR
rm -rf $JBOSS_HOME/*

# Build Galleon s2i feature-pack and install it in local maven repository
mvn -f $GALLEON_FP_PATH/pom.xml install \
--settings $GALLEON_MAVEN_BUILD_IMG_SETTINGS_XML -Dmaven.repo.local=$TMP_GALLEON_LOCAL_MAVEN_REPO $GALLEON_BUILD_FP_MAVEN_ARGS_APPEND

if [ "x$deleteBuildArtifacts" == "xtrue"  ]; then
  echo "Copying generated artifacts to galleon local cache"
  # Copy generated artifacts only
  mkdir -p $GALLEON_LOCAL_MAVEN_REPO/org/jboss/universe/
  cp -r $TMP_GALLEON_LOCAL_MAVEN_REPO/org/jboss/universe/s2i-universe $GALLEON_LOCAL_MAVEN_REPO/org/jboss/universe/
  mkdir -p $GALLEON_LOCAL_MAVEN_REPO/org/jboss/universe/producer
  cp -r $TMP_GALLEON_LOCAL_MAVEN_REPO/org/jboss/universe/producer/s2i-producers $GALLEON_LOCAL_MAVEN_REPO/org/jboss/universe/producer
  groupIdPath=${GALLEON_S2I_FP_GROUP_ID//./\/}
  mkdir -p $GALLEON_LOCAL_MAVEN_REPO/$groupIdPath
  cp -r $TMP_GALLEON_LOCAL_MAVEN_REPO/$groupIdPath/$GALLEON_S2I_FP_ARTIFACT_ID $GALLEON_LOCAL_MAVEN_REPO/$groupIdPath
fi

keepFP=${DEBUG_GALLEON_FP_SRC:-false}
if [ "x$keepFP" == "xfalse" ]; then
 echo Removing feature-pack src.
 # Remove the feature-pack src
 rm -rf $GALLEON_FP_PATH
fi
