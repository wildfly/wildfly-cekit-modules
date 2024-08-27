#!/bin/bash

source "${JBOSS_CONTAINER_UTIL_LOGGING_MODULE}/logging.sh"

# Some JPMS arguments are specific to cloud, handle them in the main launcher.
# $JBOSS_HOME/bin/standalone.conf extends JAVA_OPTS with arguments.
function run_add_java_options() {
  local marker="${1}"
  local options="${2}"
  local conf_file="$JBOSS_HOME/bin/standalone.conf"
  if ! grep -q "$marker" "$conf_file"; then
    local jvm_options="$marker
JAVA_OPTS=\"\$JAVA_OPTS ${options}\""
    echo "$jvm_options" >> "$conf_file"
  fi
}

# Un-used, kept as an example in case we have a need to add more JPMS options.
function run_add_jpms_options() {
  # Append cloud specific modular options in standalone.conf
  SPEC_VERSION="${JAVA_VERSION//1.}"
  SPEC_VERSION="${SPEC_VERSION//.*}"
  if (( $SPEC_VERSION > 15 )); then
    MODULAR_JVM_OPTIONS=`echo $JAVA_OPTS | grep "\-\-add\-modules"`
    # if [ "x$MODULAR_JVM_OPTIONS" = "x" ]; then
      # if [ "x$RUN_SCRIPT_JPMS_ADD_EXPORT_JNDI_DNS" == "x" ] || [ "x$RUN_SCRIPT_JPMS_ADD_EXPORT_JNDI_DNS" == "xtrue" ]; then
      #  local option="--add-exports=jdk.naming.dns/com.sun.jndi.dns=ALL-UNNAMED"
      #  local marker="#JVM modular option  ${option} added by image run startup script"
      #  run_add_java_options "${marker}" "${option}"
      # fi
    # fi
  fi
}

# Logic to allow for CLI shutdown with a 60secs delay that helps transaction to terminate 
function run_clean_shutdown() {
  local management_port=""
  if [ -n "${PORT_OFFSET}" ]; then
    management_port=$((9990 + PORT_OFFSET))
  fi
  log_error "*** WildFly wrapper process ($$) received TERM signal ***"
  if [ -z ${management_port} ]; then
    $JBOSS_HOME/bin/jboss-cli.sh -c "shutdown --timeout=60"
  else
    $JBOSS_HOME/bin/jboss-cli.sh --commands="connect remote+http://localhost:${management_port},shutdown --timeout=60"
  fi
  wait $!
}

function run_setup_shutdown_hook() {
  trap "run_clean_shutdown" TERM
  trap "run_clean_shutdown" INT

  if [ -n "$CLI_GRACEFUL_SHUTDOWN" ] ; then
    trap "" TERM
    log_info "Graceful shutdown via a TERM signal has been disabled. Graceful shutdown will need to be initiated via a CLI command."
  fi
}

function run_init_node_name() {
  if [ -z "${JBOSS_NODE_NAME}" ] ; then
    if [ -n "${NODE_NAME}" ]; then
      JBOSS_NODE_NAME="${NODE_NAME}"
    elif [ -n "${container_uuid}" ]; then
      JBOSS_NODE_NAME="${container_uuid}"
    elif [ -n "${HOSTNAME}" ]; then
      JBOSS_NODE_NAME="${HOSTNAME}"
    else
      JBOSS_NODE_NAME="$(hostname)"
    fi
  fi
  # CLOUD-427: truncate transaction node-id JBOSS_TX_NODE_ID to the last 23 characters of the JBOSS_NODE_NAME
  if [ ${#JBOSS_NODE_NAME} -gt 23 ]; then
    JBOSS_TX_NODE_ID=${JBOSS_NODE_NAME: -23}
  else
    JBOSS_TX_NODE_ID=${JBOSS_NODE_NAME}
  fi
}