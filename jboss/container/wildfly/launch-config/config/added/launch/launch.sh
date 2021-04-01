#!/bin/bash
# This script must be sourced by external projects. It prepares all the environment to work with wildfly-cekit-modules

if [ "${SCRIPT_DEBUG}" = "true" ] ; then
    set -x
    echo "Script debugging is enabled, allowing bash commands and their arguments to be printed as they are executed"
fi

source "$JBOSS_HOME"/bin/launch/logging.sh
# sources external project configuration file. External projects will configure the common modules using launch-config.sh file.
# Specifically, they have to add the scripts they want to run into CONFIG_SCRIPT_CANDIDATES array
if [[ -s $JBOSS_HOME/bin/launch/launch-config.sh ]]; then
  source "$JBOSS_HOME"/bin/launch/launch-config.sh
fi
# Common environment variables, functions and configurations
source "$JBOSS_HOME"/bin/launch/openshift-common.sh


# Configure scripts. It takes all the scripts added by the external projects in CONFIG_SCRIPT_CANDIDATES arrays
# and copy them to the array used by the common modules. Later it executes all the modules and finally run any
# possible cli operation added by the modules
function configure_server() {

  configure_scripts

  if [ "${DISABLE_BOOT_SCRIPT_INVOKER}" = "true" ]; then
    configure_embedded_cli_script
  else
    configure_boot_script "${CLI_SCRIPT_FILE}"
  fi
}

# Configure the server using CLI + embedded server.
function configure_server_with_cli() {
  # prepare the cli properties files
  createConfigExecutionContext
  # cli for drivers are needed to be added to script file as well
  if [ -s "${S2I_CLI_DRIVERS_FILE}" ] && [ "${CONFIG_ADJUSTMENT_MODE,,}" != "cli" ]; then
    cat "${S2I_CLI_DRIVERS_FILE}" > "${CLI_SCRIPT_FILE}"
  fi

  configure_scripts
  configure_embedded_cli_script
}

function configure_scripts() {
  CONFIGURE_CONFIG_SCRIPTS=(
  )

  if [[ -n "${CONFIG_SCRIPT_CANDIDATES}" ]]; then
      for script in "${CONFIG_SCRIPT_CANDIDATES[@]}"
      do
          if [ -f "${script}" ]; then
              CONFIGURE_SCRIPTS+=(${script})
          fi
      done
  else
      echo "No CONFIG_SCRIPT_CANDIDATES were set!"
  fi

  # Sources the configure-modules, it also will invoke all the modules configured in the CONFIGURE_SCRIPTS array
  source "$JBOSS_HOME"/bin/launch/configure-modules.sh

  # Process any errors and warnings generated while running the launch configuration scripts
  processErrorsAndWarnings
  if [ $? -ne 0 ]; then
    exit 1
  fi
}

function configure_embedded_cli_script() {
  # The scripts will add the operations in a special file, invoke the embedded server if it is necessary
  # and run the CLI scripts
  exec_cli_scripts "${CLI_SCRIPT_FILE}"

  configure_extensions
  if [ $? -ne 0 ]; then
    exit 1
  fi
  # re-run CLI scipts just in case a delayed postinstall updated it
  exec_cli_scripts "${CLI_SCRIPT_FILE}"
}

function configure_extensions() {
  # run the delayed postinstall of modules
  createConfigExecutionContext
  executeModules delayedPostConfigure

  # Process any errors and warnings generated while running the launch configuration scripts
  processErrorsAndWarnings
}

# Launch server functions

function clean_shutdown() {
  local management_port=""
  if [ -n "${PORT_OFFSET}" ]; then
    management_port=$((9990 + PORT_OFFSET))
  fi
  log_error "*** WildFly wrapper process ($$) received TERM signal ***"
  if [ -z ${management_port} ]; then
    "$JBOSS_HOME"/bin/jboss-cli.sh -c "shutdown --timeout=60"
  else
    "$JBOSS_HOME"/bin/jboss-cli.sh --commands="connect remote+http://localhost:${management_port},shutdown --timeout=60"
  fi
  wait $!
}

function setupShutdownHook() {
  trap "clean_shutdown" TERM
  trap "clean_shutdown" INT

  if [ -n "$CLI_GRACEFUL_SHUTDOWN" ] ; then
    trap "" TERM
    log_info "Using CLI Graceful Shutdown instead of TERM signal"
  fi
}

function launchServer() {
  local cmd=$1

  move_history_directory
  configure_server
  setupShutdownHook
  local imgName=${JBOSS_IMAGE_NAME:-$IMAGE_NAME}
  local imgVersion=${JBOSS_IMAGE_VERSION:-$IMAGE_VERSION}
  log_info "Running $imgName image, version $imgVersion"

  ${cmd} "${JAVA_PROXY_OPTIONS}" "${JBOSS_HA_ARGS}" "${JBOSS_MESSAGING_ARGS}" "${CLI_EXECUTION_OPTS}"  &

  local pid=$!

  # In case a script is generated by extensions and needs to be run against server started in admin mode. NB: server will be reloaded in normal mode or asked to be restarted.
  handleExtensions
  if [ $? -ne 0 ]; then
    log_info "Restarting the server"
    ${cmd} ${JAVA_PROXY_OPTIONS} ${JBOSS_HA_ARGS} ${JBOSS_MESSAGING_ARGS} &
    pid=$!
  fi
  wait $pid 2>/dev/null
  wait $pid 2>/dev/null
}

# The server requires to move some directories under ${JBOSS_HOME}/standalone/configuration/standalone_xml_history
# The docker image could have the soure and target directories mounted on a different overlay filesystem, which ends
# up in different paritions that java code Files.move() cannot move if source is not empty.
# We force a movement at OS level to keep the content in the same overlay filesystem before launching the server.
# There is a feature request that should fix this
function move_history_directory() {
  if [ -d "${JBOSS_HOME}/standalone/configuration/standalone_xml_history" ]; then
    mv "${JBOSS_HOME}/standalone/configuration/standalone_xml_history" "${JBOSS_HOME}/standalone/configuration/standalone_xml_history-temp"
    mv "${JBOSS_HOME}/standalone/configuration/standalone_xml_history-temp" "${JBOSS_HOME}/standalone/configuration/standalone_xml_history"
  fi
}

# Functions to handle CLI execution during boot

function configure_boot_script() {
  local script="$1"
  # remove any empty line
  if [ -f "${script}" ]; then
    sed -i '/^$/d' "$script"
  fi

  if [ -f "$JBOSS_HOME/extensions/postconfigure.sh" ] || [ -f "$JBOSS_HOME/extensions/delayedpostconfigure.sh" ]; then
    CLI_BOOT_HANDLE_EXTENSIONS="true"
    # Corner case, no main script although extensions.
    if ! [ -f "${script}" ]; then
      # we need an existing empty script file for the server to generate the marker file advertising that it is ready to receive extensions script CLI operations.
      echo "" > "${script}"
    fi
  fi

  if [ -s "${script}" ] || [ -n "${CLI_BOOT_HANDLE_EXTENSIONS}" ]; then
    local t=$(date +%s)
    CLI_BOOT_RELOAD_MARKER_DIR=/tmp/cli-boot-reload-marker-${t}
    mkdir -p "${CLI_BOOT_RELOAD_MARKER_DIR}"
    CLI_EXECUTION_OPTS="--start-mode=admin-only -Dorg.wildfly.internal.cli.boot.hook.script=${script} \
      -Dorg.wildfly.internal.cli.boot.hook.marker.dir=${CLI_BOOT_RELOAD_MARKER_DIR} \
      -Dorg.wildfly.internal.cli.boot.hook.script.properties=${CLI_SCRIPT_PROPERTY_FILE} \
      -Dorg.wildfly.internal.cli.boot.hook.script.output.file=${CLI_SCRIPT_OUTPUT_FILE} \
      -Dorg.wildfly.internal.cli.boot.hook.script.error.file=${CONFIG_ERROR_FILE} \
      -Dorg.wildfly.internal.cli.boot.hook.script.warn.file=${CONFIG_WARNING_FILE}"

    if [ -n "${CLI_BOOT_HANDLE_EXTENSIONS}" ]; then
      CLI_EXECUTION_OPTS="${CLI_EXECUTION_OPTS} -Dorg.wildfly.internal.cli.boot.hook.reload.skip=true"
      log_info "Extensions detected, server will be reloaded from remote CLI script."
    fi
    log_info "Server started in admin mode, CLI script executed during server boot."

    if [ "${SCRIPT_DEBUG}" = "true" ] ; then
      log_info "Server options: ${CLI_EXECUTION_OPTS}"
      log_info "CLI Script generated by launch: ${script}"
      log_info "CLI Script property file: ${CLI_SCRIPT_PROPERTY_FILE}"
      log_info "CLI Script error file: ${CONFIG_ERROR_FILE}"
      log_info "CLI Script output file: ${CLI_SCRIPT_OUTPUT_FILE}"
    fi
  else
    if [ "${SCRIPT_DEBUG}" = "true" ]; then
      log_info "================= CLI files debug ================="
      log_info "No CLI commands were found in ${script}"
    fi
  fi
}

function handleExtensions {
  if [ -n "${CLI_BOOT_HANDLE_EXTENSIONS}" ]; then
    local marker_file=${CLI_BOOT_RELOAD_MARKER_DIR}/wf-cli-invoker-result
    wait_marker "${marker_file}"
    if [ $? -ne 0 ]; then
      log_error "Error, server never advertised configuration done. Can't proceed with custom extensions script."
      exit 1
    else
      read -r status<"${marker_file}"
      rm -rf "${CLI_BOOT_RELOAD_MARKER_DIR}"
      if [ "success" = "${status}" ]; then
        configure_extensions
        if [ $? = 0 ]; then
          reload_server
          return $?
        else
          shutdown_server
        fi
      else
        log_error "Error, server failed to configure. Can't proceed with custom extensions script."
        exit 1
      fi
    fi
  fi
  return 0;
}

function wait_marker() {
  local timeout=${BOOT_SCRIPT_INVOKER_TIMEOUT:-30}
  local file=$1
  local t=0
  while [ ! -f "${file}" ];
  do
    sleep 1;
    ((t=t+1))
    if [ $t -gt "${timeout}" ]; then
      return 1
    fi
  done;
  return 0
}

function shutdown_server() {
  log_error "Shutdown server"
  #Check we are able to use the jboss-cli.sh
  if ! [ -f "${JBOSS_HOME}/bin/jboss-cli.sh" ]; then
    log_error "Cannot find ${JBOSS_HOME}/bin/jboss-cli.sh. Can't shutdown server"
    exit 1
  fi
  # Whatever the PORT_OFFSET, server started in admin mode listen on default port.
  "$JBOSS_HOME"/bin/jboss-cli.sh -c ":shutdown"
}

function reload_server() {
  #Check we are able to use the jboss-cli.sh
  if ! [ -f "${JBOSS_HOME}/bin/jboss-cli.sh" ]; then
    log_error "Cannot find ${JBOSS_HOME}/bin/jboss-cli.sh. Can't reload server"
    exit 1
  fi
  systime=$(date +%s)
  CLI_SCRIPT_FILE_FOR_RELOAD=/tmp/cli-reload-configuration-script-${systime}.cli
  local script="${CLI_SCRIPT_FILE}"
  # remove any empty line
  if [ -f "${script}" ]; then
    sed -i '/^$/d' "$script"
  fi
  if [ -s "${script}" ]; then
    cat "${script}" > "${CLI_SCRIPT_FILE_FOR_RELOAD}"
    echo "" >> "${CLI_SCRIPT_FILE_FOR_RELOAD}"
  fi

  restart_marker=/tmp/cli-restart-marker-${systime}
  reload_ops="if (result == restart-required) of :read-attribute(name=server-state)
                echo restart > ${restart_marker}
                :shutdown
              else
                :reload(start-mode=normal)
              end-if"
  echo "$reload_ops" >> "${CLI_SCRIPT_FILE_FOR_RELOAD}"
  log_info "Configuring the server with custom extensions script ${CLI_SCRIPT_FILE_FOR_RELOAD}"
  start=$(date +%s%3N)
  # Whatever the PORT_OFFSET, server started in admin mode listen on default port.
  eval "$JBOSS_HOME/bin/jboss-cli.sh" "-c --file=${CLI_SCRIPT_FILE_FOR_RELOAD}" "--properties=${CLI_SCRIPT_PROPERTY_FILE}" "&>${CLI_SCRIPT_OUTPUT_FILE}"
  cli_result=$?
  end=$(date +%s%3N)

  if [ "${SCRIPT_DEBUG}" == "true" ] ; then
    cat "${CLI_SCRIPT_OUTPUT_FILE}"
  fi

  log_info "Duration: $((end-start)) milliseconds"

  if [ $cli_result -ne 0 ]; then
    log_error "Error applying ${CLI_SCRIPT_FILE_FOR_RELOAD} CLI script."
    cat "${CLI_SCRIPT_OUTPUT_FILE}"
    shutdown_server
    exit 1
  else
    processErrorsAndWarnings
    if [ $? -ne 0 ]; then
      shutdown_server
      exit 1
    fi
    # finally need to restart the server if asked to.
    if [ -f "${restart_marker}" ]; then
      log_info "Server has been shutdown and must be restarted."
      rm "${restart_marker}"
      return 1
    fi
    if [ "${SCRIPT_DEBUG}" != "true" ] ; then
      rm "${script}" 2> /dev/null
      rm "${CLI_SCRIPT_PROPERTY_FILE}" 2> /dev/null
      rm "${CONFIG_ERROR_FILE}" 2> /dev/null
      rm "${CONFIG_WARNING_FILE}" 2> /dev/null
      rm "${CLI_SCRIPT_FILE_FOR_RELOAD}" 2> /dev/null
      rm "${CLI_SCRIPT_OUTPUT_FILE}" 2> /dev/null
    else
      log_info "CLI Script used to configure the server: ${CLI_SCRIPT_FILE_FOR_RELOAD}"
      log_info "CLI Script generated by custom extensions script: ${script}"
      log_info "CLI Script property file: ${CLI_SCRIPT_PROPERTY_FILE}"
      log_info "CLI Script error file: ${CONFIG_ERROR_FILE}"
      log_info "CLI Script output file: ${CLI_SCRIPT_OUTPUT_FILE}"
    fi
  fi
  return 0
}

# End CLI execution during boot
