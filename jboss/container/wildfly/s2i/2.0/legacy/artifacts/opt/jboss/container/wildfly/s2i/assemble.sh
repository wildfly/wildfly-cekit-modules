#!/bin/sh

set -e

source "${JBOSS_CONTAINER_UTIL_LOGGING_MODULE}/logging.sh"
source "${JBOSS_CONTAINER_MAVEN_S2I_MODULE}/maven-s2i"

if [ -n "${GALLEON_PROVISION_LAYERS}" ]; then
   if [ -z "${GALLEON_PROVISION_FEATURE_PACKS}" ]; then
     log_error "GALLEON_PROVISION_FEATURE_PACKS env variable must be set when GALLEON_PROVISION_LAYERS is set"
     exit 1
   fi
fi
if [ -n "${GALLEON_PROVISION_FEATURE_PACKS}" ]; then
   if [ -z "${GALLEON_PROVISION_LAYERS}" ]; then
     log_error "GALLEON_PROVISION_LAYERS env variable must be set when GALLEON_PROVISION_FEATURE_PACKS is set"
     exit 1
   fi
fi
# This is required in all cases
# Needed in case some drivers are installed during s2i, the CLI execution must occurs during s2i.
export CONFIG_ADJUSTMENT_MODE=cli
#For backward compatibility, in all cases allow to copy modules from the application project
source "${JBOSS_CONTAINER_WILDFLY_S2I_LEGACY_GALLEON_MODULE}/s2i-core-hooks"

# Required to handle custom feature-pack copied to local maven repo
source "${JBOSS_CONTAINER_WILDFLY_S2I_LEGACY_GALLEON_MODULE}/s2i_galleon"
if [ -n "${GALLEON_PROVISION_FEATURE_PACKS}" ] || [ -n "${GALLEON_USE_LOCAL_FILE}" ]; then
  log_warning "You have activated legacy s2i workflow by setting GALLEON_PROVISION_FEATURE_PACKS or GALLEON_USE_LOCAL_FILE env variable."
  log_warning "This support is deprecated and will be removed in a future release. Provision and configure your server during s2i from your pom.xml file by using the dedicated Maven plugin."
  # images using this module must have set these env variables.
  if [ -z "${PROVISIONING_MAVEN_PLUGIN_GROUP_ID}" ] || [ -z "${PROVISIONING_MAVEN_PLUGIN_ARTIFACT_ID}" ] || [ -z "${PROVISIONING_MAVEN_PLUGIN_VERSION}" ]; then
    log_error "PROVISIONING_MAVEN_PLUGIN_GROUP_ID,  PROVISIONING_MAVEN_PLUGIN_ARTIFACT_ID and PROVISIONING_MAVEN_PLUGIN_VERSION env variable must be set to provision a server."
    exit 1
  fi 
 # Legacy s2i workflow integration
  galleon_legacy=true;
  galleon_provision_server
else
  # include our overrides/extensions
  source "${JBOSS_CONTAINER_WILDFLY_S2I_MODULE}/s2i-core-hooks"
  source "${JBOSS_CONTAINER_WILDFLY_S2I_MODULE}/maven-s2i-overrides"
  install_custom_fps
  
fi
# invoke the build
maven_s2i_build

# We must then copy the /deployments to the server
if [ -n "$galleon_legacy" ]; then
  log_info "Copying /deployments to $JBOSS_HOME/standalone/"
  cp -prf /deployments $JBOSS_HOME/standalone/
  rm -rf /deployments/*
fi