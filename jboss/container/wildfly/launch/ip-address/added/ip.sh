#!/bin/sh
# only processes a single environment as the placeholder is not preserved

source $JBOSS_HOME/bin/launch/logging.sh

function prepareEnv() {
  unset SERVER_USE_IPV6
}

function configure() {
  configure_ip
}

function configureEnv() {
  configure
}

function configure_ip() {
  SERVER_IP_ADDR=
  get_host_ip_address "SERVER_IP_ADDR"
  export SERVER_IP_ADDR
  SERVER_BIND_ALL_ADDR=$(get_bind_all_address)
  export SERVER_BIND_ALL_ADDR
  SERVER_LOOPBACK_ADDRESS=$(get_loopback_address)
  export SERVER_LOOPBACK_ADDRESS
  log_info "Server IP address $SERVER_IP_ADDR, bindAll adress $SERVER_BIND_ALL_ADDR"
  if [ "xxx$SERVER_USE_IPV6" == "xxxtrue" ]; then
    JAVA_OPTS_APPEND="-Djava.net.preferIPv4Stack=false -Djava.net.preferIPv6Addresses=true $JAVA_OPTS_APPEND"
    export JAVA_OPTS_APPEND
  fi
}