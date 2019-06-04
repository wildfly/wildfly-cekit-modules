#!/bin/sh

function configure() {
  configure_deployment_scanner
}

function configure_deployment_scanner() {
  local auto_deploy_exploded
  local explicitly_set=false
  if [[ -n "$JAVA_OPTS_APPEND" ]] && [[ $JAVA_OPTS_APPEND == *"Xdebug"* ]]; then
    sed -i "s|##AUTO_DEPLOY_EXPLODED##|true|" "$CONFIG_FILE"
    auto_deploy_exploded=true
  elif [ -n "$AUTO_DEPLOY_EXPLODED" ]; then
    auto_deploy_exploded="${AUTO_DEPLOY_EXPLODED}"
    explicitly_set=true
  else
    auto_deploy_exploded=false
  fi

  local configure_mode=""
  getConfigurationMode "##AUTO_DEPLOY_EXPLODED##" "configure_mode"

  echo "configure_mode ${configure_mode}"

  if [ "${configure_mode}" = "xml" ]; then
    sed -i "s|##AUTO_DEPLOY_EXPLODED##|${auto_deploy_exploded}|" "$CONFIG_FILE"
  elif [ "${configure_mode}" = "cli" ] && [ "${explicitly_set}" = "true" ]; then
    # Only do this if the variable was explicitly set. Otherwise we assume the user has provided their own configuration
    local cli_command="
    if (outcome==success) of /subsystem=deployment-scanner:read-resource
      for scannerName in /subsystem=deployment-scanner:read-children-names(child-type=scanner)
        /subsystem=deployment-scanner/scanner=\$scannerName:write-attribute(name=auto-deploy-exploded,value=true)
      done
    end-if
    "
    echo "TEMP CLI COMMAND: $cli_command"
    cat << EOF >> ${CLI_SCRIPT_FILE}
  	  ${cli_command}
EOF
  fi
}

