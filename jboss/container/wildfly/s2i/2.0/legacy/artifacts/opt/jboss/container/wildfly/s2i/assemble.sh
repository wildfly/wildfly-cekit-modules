#!/bin/sh

set -e

source "${JBOSS_CONTAINER_UTIL_LOGGING_MODULE}/logging.sh"
source "${JBOSS_CONTAINER_MAVEN_S2I_MODULE}/maven-s2i"

# This is required in all cases
# Needed in case some drivers are installed during s2i, the CLI execution must occurs during s2i.
export CONFIG_ADJUSTMENT_MODE=cli
#For backward compatibility, in all cases allow to copy modules from the application project
source "${JBOSS_CONTAINER_WILDFLY_S2I_LEGACY_GALLEON_MODULE}/s2i-core-hooks"

if [ -d "${JBOSS_HOME}" ]; then
  log_info "Builder image already contains a server, will only build and deploy applications."
  cp "${JBOSS_CONTAINER_WILDFLY_S2I_LEGACY_GALLEON_MODULE}"/clean-settings.xml "${HOME}/.m2/settings.xml"
else
  if [ -n "$WILDFLY_S2I_GENERATE_SERVER_BUILDER" ] && [[ "$WILDFLY_S2I_GENERATE_SERVER_BUILDER" == "true" ]]; then
    log_info "Generating server builder."
    # Env variables we don't want to see exposed in the generated builder have been prefixed, we need to remove the suffix and export them.
    # Env variables containing the suffix are exported for this server build without the suffix.
    suffix=_WILDFLY_SERVER_BUILDER
    unset IFS
    for var in $(compgen -e); do
      if [[ $var == *$suffix ]]; then
        s2i_name=${var%"$suffix"}
        export ${s2i_name}="${!var}"
        log_info "Exported env ${s2i_name}=${!var}"
      fi
    done
    # Disable incremental has the side effect to clean the local mven repo that is useless in an S2I builder context
    if [ -z "$S2I_ENABLE_INCREMENTAL_BUILDS" ]; then
      export S2I_ENABLE_INCREMENTAL_BUILDS="false";
      log_info "Disabling incremental build, local maven cache will be deleted."
    fi
  fi
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

  # Required to handle custom feature-pack copied to local maven repo
  source "${JBOSS_CONTAINER_WILDFLY_S2I_LEGACY_GALLEON_MODULE}/s2i_galleon"
  if [ -n "${GALLEON_PROVISION_FEATURE_PACKS}" ] || [ -n "${GALLEON_USE_LOCAL_FILE}" ]; then
    log_info "You have activated legacy s2i workflow by setting GALLEON_PROVISION_FEATURE_PACKS or GALLEON_USE_LOCAL_FILE env variable."
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
fi
# invoke the build
maven_s2i_build

# We must then copy the /deployments to the server
if [ -n "$galleon_legacy" ]; then
  log_info "Copying $S2I_TARGET_DEPLOYMENTS_DIR to $JBOSS_HOME/standalone/"
  cp -prf "$S2I_TARGET_DEPLOYMENTS_DIR" "$JBOSS_HOME/standalone/"
else
  # Some extra deployments could have been set in the deployments dir (or custom S2I_SOURCE_DEPLOYMENTS_DIR)
  # These deployments have been copied during s2i build to the S2I_TARGET_DEPLOYMENTS_DIR
  if [ -d "$S2I_TARGET_DEPLOYMENTS_DIR" ]; then
    deployments_count="$( find $S2I_TARGET_DEPLOYMENTS_DIR -mindepth 1 -maxdepth 1 | wc -l )"
    if [ $deployments_count -gt 0 ] ; then
      log_info "Copying extra deployments found in $S2I_TARGET_DEPLOYMENTS_DIR to $JBOSS_HOME/standalone/deployments"
      mkdir -p "$JBOSS_HOME/standalone/deployments"
      cp "$S2I_TARGET_DEPLOYMENTS_DIR"/* "$JBOSS_HOME/standalone/deployments"
    fi
  fi
fi
rm -rf "$S2I_TARGET_DEPLOYMENTS_DIR"/*