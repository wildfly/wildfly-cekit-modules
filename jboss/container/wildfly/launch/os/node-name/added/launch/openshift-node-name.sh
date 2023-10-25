function init_node_name() {
  if [ -z "${JBOSS_NODE_NAME}" ] ; then
    if [ -n "${NODE_NAME}" ]; then
      JBOSS_NODE_NAME="${NODE_NAME}"
    elif [ -n "${container_uuid}" ]; then
      JBOSS_NODE_NAME="${container_uuid}"
    else
      JBOSS_NODE_NAME="${HOSTNAME}"
    fi
  fi
  # CLOUD-427: truncate transaction node-id JBOSS_TX_NODE_ID to the last 23 characters of the JBOSS_NODE_NAME
  if [ ${#JBOSS_NODE_NAME} -gt 23 ]; then
    JBOSS_TX_NODE_ID=${JBOSS_NODE_NAME: -23}
  else
    JBOSS_TX_NODE_ID=${JBOSS_NODE_NAME}
  fi
}
