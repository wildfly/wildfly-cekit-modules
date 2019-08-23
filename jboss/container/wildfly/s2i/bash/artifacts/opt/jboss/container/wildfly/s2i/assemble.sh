#!/bin/sh

set -e

function copy_server_s2i_output() {
  isSlim="$(galleon_is_slim_server)"
  if [ "$isSlim" != "true" ]; then
    if [ "x$S2I_COPY_SERVER" == "xtrue" ]; then
      mkdir -p $WILDFLY_S2I_OUTPUT_DIR
      log_info "Copying server to $WILDFLY_S2I_OUTPUT_DIR"
      cp -r -L $JBOSS_HOME $WILDFLY_S2I_OUTPUT_DIR/server
    fi
  else
    if [ "x$S2I_COPY_SERVER" == "xtrue" ]; then
      log_warning "Server not copied to $WILDFLY_S2I_OUTPUT_DIR, provisioned server is bound to local repository and can't be used in chained build."
    fi
  fi
}

function replace_default_settings_with_s2i {
  cp "$HOME/.m2/settings-s2i.xml" "$HOME/.m2/settings.xml"
}

function replace_default_settings_with_galleon_s2i {
  cp "$HOME/.m2/settings-galleon.xml" "$HOME/.m2/settings.xml"
}

function replace_default_settings_with_startup {
  cp "$HOME/.m2/settings.xml" "$HOME/.m2/settings-s2i.xml"
  cp "$HOME/.m2/settings-startup.xml" "$HOME/.m2/settings.xml"
}

source "${JBOSS_CONTAINER_UTIL_LOGGING_MODULE}/logging.sh"
source "${JBOSS_CONTAINER_MAVEN_S2I_MODULE}/maven-s2i"

# include our overrides/extensions
source "${JBOSS_CONTAINER_WILDFLY_S2I_MODULE}/s2i-core-hooks"

# When provisioning with galleon, local repository in settings is set to the galleon one
# that is required when doing slim server provisioning, embedded server requires a proper default settings.xml.
replace_default_settings_with_galleon_s2i

# Galleon integration
source "${JBOSS_CONTAINER_WILDFLY_S2I_MODULE}/galleon/s2i_galleon"

galleon_provision_server

# Reset settings to be the one for app s2i, galleon provisioning has altered the local repository.
replace_default_settings_with_s2i

# invoke the build
maven_s2i_build

# At this point the settings are no more valid to start a server although by default wildfly and CLI will
# use these settings. Replace s2i with startup one.
replace_default_settings_with_startup

copy_server_s2i_output

galleon_cleanup
