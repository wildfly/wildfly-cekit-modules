#!/bin/sh

function prepareEnv() {
  unset MICROPROFILE_CONFIG_DIR
  unset MICROPROFILE_CONFIG_DIR_ORDINAL
}

function configureEnv() {
  configure
}

configure() {
  configure_microprofile_config_source
}

configure_microprofile_config_source() {
  local dirConfigSource=$(generate_microprofile_config_source "${MICROPROFILE_CONFIG_DIR}" "${MICROPROFILE_CONFIG_DIR_ORDINAL}")

  if [ -n "$dirConfigSource" ]; then

    local mpConfigMode
    getConfigurationMode "<!-- ##MICROPROFILE_CONFIG_SOURCE## -->" "mpConfigMode"

    if [ "${mpConfigMode}" = "xml" ]; then
      sed -i "s|<!-- ##MICROPROFILE_CONFIG_SOURCE## -->|${dirConfigSource}|" $CONFIG_FILE
    elif [ "${mpConfigMode}" = "cli" ]; then
      #expected to fail if config-map is already configured
      cat << EOF >> ${CLI_SCRIPT_FILE}
      if (outcome != success) of /subsystem=microprofile-config-smallrye:read-resource
          echo \"You have set MICROPROFILE_CONFIG_DIR to configure a config-source. Fix your configuration to contain the microprofile-config subsystem for this to happen.\" >> \${error_file}
          quit
      end-if

      if (outcome == success) of /subsystem=microprofile-config-smallrye/config-source=config-map:read-resource
          echo \"Cannot configure Microprofile Config. MICROPROFILE_CONFIG_DIR was specified but there is already a config-source named config-map configured.\" >> \${error_file}
          quit
      end-if

      /subsystem=microprofile-config-smallrye/config-source=config-map:add(dir={path="${MICROPROFILE_CONFIG_DIR}"}, ordinal=${MICROPROFILE_CONFIG_DIR_ORDINAL:-500})
EOF

    fi
  elif [ -n "${MICROPROFILE_CONFIG_DIR}" ]; then
    # Invalid MICROPROFILE_CONFIG_DIR -- was not an absolute path.
    # Since we don't know if the deployment will behave correctly
    # without this config source we shouldn't start.
    log_error "Exiting..."
    exit 1
  fi

}

generate_microprofile_config_source() {
  declare dirName="$1" ordinal="$2"

  local dirConfigSource=""

  if [ -n "$dirName" ]; then
    if [[ "$dirName" =~ ^/ ]]; then
      if [ ! -e "$dirName" ]; then
        log_warning "MICROPROFILE_CONFIG_DIR value '$dirName' is a non-existent path. The server may fail readiness and liveness checks and any config values expected to be derived from the Microprofile Config directory ConfigSource will not be applied."
      elif [ ! -d "$dirName" ]; then
        log_warning "MICROPROFILE_CONFIG_DIR value '$dirName' is not a directory. The server may fail readiness and liveness checks and any config values expected to be derived from the Microprofile Config directory ConfigSource will not be applied."
      fi
    else
      log_warning "MICROPROFILE_CONFIG_DIR value '$dirName' is not an absolute path. Use of a relative path is not supported, unpredictable results may occur and behavior may change in future image updates."
    fi
    dirConfigSource="<config-source ordinal=\"${ordinal:-500}\" name=\"config-map\"><dir path=\"$dirName\"/></config-source>"
  fi

  echo $dirConfigSource
}

