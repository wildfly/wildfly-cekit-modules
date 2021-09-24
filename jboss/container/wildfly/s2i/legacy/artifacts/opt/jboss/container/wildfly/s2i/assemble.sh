#!/bin/sh

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
if [ -n "${GALLEON_PROVISION_FEATURE_PACKS}" ]; then
  log_warning "You have activated legacy s2i workflow by setting GALLEON_PROVISION_FEATURE_PACKS env variable."
  log_warning "This support is deprecated and will be removed in a future release. Provision and configure your server during s2i from your pom.xml file by using the dedicated Maven plugin."
  # Legacy s2i workflow integration
  #For backward compatibility
  export CONFIG_ADJUSTMENT_MODE=cli
  source "${JBOSS_CONTAINER_WILDFLY_S2I_LEGACY_GALLEON_MODULE}/s2i-core-hooks"
  source "${JBOSS_CONTAINER_WILDFLY_S2I_LEGACY_GALLEON_MODULE}/s2i_galleon"
  
  galleon_provision_server
else
  # include our overrides/extensions
  source "${JBOSS_CONTAINER_WILDFLY_S2I_MODULE}/s2i-core-hooks"

  # inject our overridden maven_s2i_*() functions
  source "${JBOSS_CONTAINER_WILDFLY_S2I_MODULE}/maven-s2i-overrides"
fi
# invoke the build
maven_s2i_build