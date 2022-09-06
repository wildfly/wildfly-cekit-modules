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

function run_add_jpms_options() {
  # Append cloud specific modular options in standalone.conf
  SPEC_VERSION="${JAVA_VERSION//1.}"
  SPEC_VERSION="${SPEC_VERSION//.*}"
  if (( $SPEC_VERSION > 15 )); then
    MODULAR_JVM_OPTIONS=`echo $JAVA_OPTS | grep "\-\-add\-modules"`
    if [ "x$MODULAR_JVM_OPTIONS" = "x" ]; then
      if [ "x$RUN_SCRIPT_JPMS_ADD_EXPORT_JNDI_DNS" == "x" ] || [ "x$RUN_SCRIPT_JPMS_ADD_EXPORT_JNDI_DNS" == "xtrue" ]; then
        local option="--add-exports=jdk.naming.dns/com.sun.jndi.dns=ALL-UNNAMED"
        local marker="#JVM modular option  ${option} added by image run startup script"
        run_add_java_options "${marker}" "${option}"
      fi
    fi
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
    log_info "Using CLI Graceful Shutdown instead of TERM signal"
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

    # CLOUD-427: truncate to 23 characters max (from the end backwards)
    if [ ${#JBOSS_NODE_NAME} -gt 23 ]; then
      JBOSS_NODE_NAME=${JBOSS_NODE_NAME: -23}
    fi
  fi
}


function source_managed_server_env_file() {
    echo "======> Checking managed server env file"
    env_file="${1}"
    # Export the contained env vars
    set -a
    source "${env_file}"
    set +a
}