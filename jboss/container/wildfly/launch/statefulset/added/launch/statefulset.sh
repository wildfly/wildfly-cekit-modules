#!/bin/sh

source $JBOSS_HOME/bin/launch/logging.sh

function prepareEnv() {
  unset STATEFULSET_HEADLESS_SERVICE_NAME
}

function configure() {
  if [ -n "$STATEFULSET_HEADLESS_SERVICE_NAME" ]; then
    configure_socket_binding
  fi
}

function configureEnv() {
  configure
}

function configure_socket_binding() {
  if [ -z "$HOSTNAME" ]; then
    log_warning "Cannot define client mappings for socket binding. The remote EJB calls may not be working."
    log_warning "  Env variable \$HOSTNAME is not defined while the statefulset headless service is configured for $STATEFULSET_HEADLESS_SERVICE_NAME"
    return
  fi

  cat << EOF >> "${CLI_SCRIPT_FILE}"
  if (outcome != success) of /socket-binding-group=standard-sockets/socket-binding=http:read-resource
    echo You have set STATEFULSET_HEADLESS_SERVICE_NAME although http socket-binding is not configured. >> \${error_file}
    exit
  else
    /socket-binding-group=standard-sockets/socket-binding=http:list-add(name=client-mappings, value={destination-address="${HOSTNAME}.${STATEFULSET_HEADLESS_SERVICE_NAME}"})
  end-if

  if (outcome != success) of /socket-binding-group=standard-sockets/socket-binding=https:read-resource
    echo You have set STATEFULSET_HEADLESS_SERVICE_NAME although https socket-binding is not configured. >> \${error_file}
    exit
  else
    /socket-binding-group=standard-sockets/socket-binding=https:list-add(name=client-mappings, value={destination-address="${HOSTNAME}.${STATEFULSET_HEADLESS_SERVICE_NAME}"})
  end-if
EOF
}