#!/bin/sh

source $JBOSS_HOME/bin/launch/logging.sh

function init_node_name() {
  if [ -z "${JBOSS_NODE_NAME}" ] ; then
    if [ -n "${NODE_NAME}" ]; then
      JBOSS_NODE_NAME="${NODE_NAME}"
    elif [ -n "${container_uuid}" ]; then
      JBOSS_NODE_NAME="${container_uuid}"
    else
      JBOSS_NODE_NAME="${HOSTNAME}"
    fi

    # CLOUD-2268: truncate to 23 characters max
    if [ ${#JBOSS_NODE_NAME} -gt 23 ]; then
      local prefix=${JBOSS_NODE_NAME::11}
      local suffix=${JBOSS_NODE_NAME#$prefix}
      suffix=$(echo -n $suffix | md5sum | cut -c -12 )
      local jbossNodeNamePrevious="${JBOSS_NODE_NAME}"
      JBOSS_NODE_NAME="${prefix}${suffix^^}"
      log_info "The JBOSS_NODE_NAME was adjusted to 23 bytes long string '${JBOSS_NODE_NAME}' from the original value '${jbossNodeNamePrevious}'"
    fi
  fi
}
