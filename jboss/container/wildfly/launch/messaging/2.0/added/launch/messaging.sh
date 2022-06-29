#!/bin/sh
# Openshift EAP launch script routines for configuring messaging

# Messaging doesn't currently support configuration using env files, but this is
# a start at what it would need to do to clear the env.  The reason for this is
# that the HornetQ subsystem is automatically configured if no service mappings
# are specified.  This could result in the configuration of both queuing systems.
function prepareEnv() {
  # HornetQ configuration
  unset HORNETQ_QUEUES
  unset MQ_QUEUES
  unset HORNETQ_TOPICS
  unset MQ_TOPICS
  unset HORNETQ_CLUSTER_PASSWORD
  unset MQ_CLUSTER_PASSWORD
  unset DEFAULT_JMS_CONNECTION_FACTORY
  unset JBOSS_MESSAGING_HOST

  # A-MQ configuration
  IFS=',' read -a brokers <<< $MQ_SERVICE_PREFIX_MAPPING
  for broker in ${brokers[@]}; do
    service_name=${broker%=*}
    service=${service_name^^}
    service=${service//-/_}
    type=${service##*_}
    prefix=${broker#*=}

    unset ${prefix}_PROTOCOL
    protocol_env=${protocol//[-+.]/_}
    protocol_env=${protocol_env^^}
    unset ${service}_${protocol_env}_SERVICE_HOST
    unset ${service}_${protocol_env}_SERVICE_PORT

    unset ${prefix}_JNDI
    unset ${prefix}_USERNAME
    unset ${prefix}_PASSWORD

    for queue in ${queues[@]}; do
      queue_env=${prefix}_QUEUE_${queue^^}
      queue_env=${queue_env//[-\.]/_}
      unset ${queue_env}_PHYSICAL
      unset ${queue_env}_JNDI
    done
    unset ${prefix}_QUEUES

    for topic in ${topics[@]}; do
      topic_env=${prefix}_TOPIC_${topic^^}
      topic_env=${topic_env//[-\.]/_}
      unset ${topic_env}_PHYSICAL
      unset ${topic_env}_JNDI
    done
    unset ${prefix}_TOPICS
  done

  unset MQ_SERVICE_PREFIX_MAPPING
}

function configureEnv() {
  configure
}

function configure() {
  configure_artemis_address
  inject_brokers
  configure_mq
  # This is no more needed, the JVM is cgroup aware and computes the defaults.
  #configure_thread_pool
}

function configure_artemis_address() {
    IP_ADDR=${JBOSS_MESSAGING_HOST:-`hostname -i`}
    JBOSS_MESSAGING_ARGS="${JBOSS_MESSAGING_ARGS} -Djboss.messaging.host=${IP_ADDR}"
}
# /subsystem=messaging-activemq/server=default/jms-queue=queue_name:add(entries=[])

function configure_mq_destinations() {
  declare server_name="default"

  IFS=',' read -a queues <<< ${MQ_QUEUES:-$HORNETQ_QUEUES}
  IFS=',' read -a topics <<< ${MQ_TOPICS:-$HORNETQ_TOPICS}

  local destinations=""
  if [ "${#queues[@]}" -ne "0" -o "${#topics[@]}" -ne "0" ]; then
    if [ "${#queues[@]}" -ne "0" ]; then
      for queue in ${queues[@]}; do
          destinations="${destinations}
                        /subsystem=messaging-activemq/server=\"${server_name}\"/jms-queue=\"${queue}\":add(entries=[\"/queue/${queue}\"])"
      done
    fi
    if [ "${#topics[@]}" -ne "0" ]; then
      for topic in ${topics[@]}; do
          destinations="${destinations}
                        /subsystem=messaging-activemq/server=\"${server_name}\"/jms-topic=\"${topic}\":add(entries=[\"/topic/${topic}\"])"
      done
    fi
  fi

  echo "${destinations}"
}

function configure_mq_cluster_password() {
  if [ -n "${MQ_CLUSTER_PASSWORD:-HORNETQ_CLUSTER_PASSWORD}" ] ; then
    JBOSS_MESSAGING_ARGS="${JBOSS_MESSAGING_ARGS} -Djboss.messaging.cluster.password=${MQ_CLUSTER_PASSWORD:-HORNETQ_CLUSTER_PASSWORD}"
  fi
}

# Configures by default the embedded broker only if a remote one has not been already added
function configure_mq() {
  if [ "$REMOTE_AMQ_BROKER" != "true" ] ; then
    configure_mq_cluster_password

    destinations=$(configure_mq_destinations)
    if [ -n "${destinations}" ]; then
      IFS= read -rd '' cli_operations << EOF

        if (outcome != success) of /subsystem=messaging-activemq/server=default:read-resource
            echo You have set MQ_QUEUES and/or MQ_TOPICS but no default embedded broker is present in the server configuration. You must provision a default server for the queues and topics to be registered. >> \${error_file}
            exit
        end-if

EOF
      echo "${cli_operations}" >> "${CLI_SCRIPT_FILE}"
      echo "${destinations}" >> "${CLI_SCRIPT_FILE}"
    fi
  fi
}

# Kept for reference, we can now trust JVM for default values.
# Currently, the JVM is not cgroup aware and cannot be trusted to generate default values for
# threads pool args. Therefore, if there are resource limits specifed by the container, this function
# will configure the thread pool args using cgroups and the formulae provied by https://github.com/apache/activemq-artemis/blob/master/artemis-core-client/src/main/java/org/apache/activemq/artemis/api/core/client/ActiveMQClient.java
#function configure_thread_pool() {
#  source /opt/run-java/container-limits
#  if [ -n "$CORE_LIMIT" ]; then
#    local mtp=$(expr 8 \* $CORE_LIMIT) # max thread pool size
#    local ctp=5                                  # core thread pool size
#    JBOSS_MESSAGING_ARGS="${JBOSS_MESSAGING_ARGS}
#    -Dactivemq.artemis.client.global.thread.pool.max.size=$mtp
#    -Dactivemq.artemis.client.global.scheduled.thread.pool.core.size=$ctp"
#  fi
#}

# $1 - name - messaging-remote-throughput
# $2 - server name Optional
function generate_remote_artemis_remote_connector_cli() {
    local resource="/subsystem=messaging-activemq"
    if [ -n "${2}" ]; then
        resource="${resource}/server=${2}"
    fi
    echo "${resource}/remote-connector=netty-remote-throughput:add(socket-binding=\"${1}\")"
}

# Arguments:
# $1 - remote context name - default remoteContext
# $2 - remote host
# $3 - remote port - 61616
function generate_remote_artemis_naming_cli() {
  local cli_operations
  IFS= read -rd '' cli_operations << EOF

    if (outcome != success) of /subsystem=naming:read-resource
      echo You have set MQ_SERVICE_PREFIX_MAPPING environment variable to configure the service name '${service_name}' under '${prefix}' prefix. Fix your configuration to contain naming subsystem for this to happen. >> \${error_file}
      exit
    end-if

    if (outcome == success) of /subsystem=naming/binding="java:global/${1}":read-resource
      echo You have set MQ_SERVICE_PREFIX_MAPPING environment variable to configure the service name '${service_name}' under '${prefix}' prefix. Fix your configuration to not contain a naming binding with name 'java:global/${remote_context_name}' for this to happen. >> \${error_file}
      exit
    end-if

    /subsystem=naming/binding="java:global/${1}":add(binding-type=external-context, class=javax.naming.InitialContext, module=org.apache.activemq.artemis, environment={java.naming.provider.url="tcp://${2}:${3}", java.naming.factory.initial=org.apache.activemq.artemis.jndi.ActiveMQInitialContextFactory})
EOF

    echo "${cli_operations}"
}

# $1 - factory name - activemq-ra-remote
# $2 - username
# $3 - password
# $4 - default connection factory - java:jboss/DefaultJMSConnectionFactory
# $5 - server name Optional
function generate_remote_artemis_connection_factory_cli() {
  local resource="/subsystem=messaging-activemq"
  if [ -n "${5}" ]; then
      resource="${resource}/server=${5}"
  fi

  echo "${resource}/pooled-connection-factory=\"${1}\":add(user=\"${2}\", password=\"${3}\", entries=[\"java:/JmsXA java:/RemoteJmsXA java:jboss/RemoteJmsXA ${4}\"], connectors=[\"netty-remote-throughput\"], transaction=xa)"
}

# $1 remote context name
# $2 object type - queue / topic
# $3 object name - MyQueue / MyTopic
function generate_remote_artemis_property_cli() {
  declare remote_context="${1}" queue_topic="${2}" object_name="${3}"
  echo "/subsystem=naming/binding=\"java:global/${remote_context}\":map-put(name=environment, key=\"${queue_topic}.${object_name}\", value=\"${object_name}\")"
}

# $1 - remote context - remoteContext
# $2 - object name - MyQueue / MyTopic etc
function generate_remote_artemis_lookup_cli() {
    echo "/subsystem=naming/binding=\"java:/${2}\":add(binding-type=lookup, lookup=\"java:global/${1}/${2}\")"
}

# $1 - name - messaging-remote-throughput
# $2 - remote hostname
# $3 - remote port
function generate_remote_artemis_socket_binding_cli() {
  local cli_operations
  IFS= read -rd '' cli_operations << EOF

  if (outcome == success) of /socket-binding-group=standard-sockets/remote-destination-outbound-socket-binding="${1}":read-resource
    echo You have set MQ_SERVICE_PREFIX_MAPPING environment variable to configure the service name '${service_name}' under '${prefix}' prefix. Fix your configuration to not contain a remote-destination-outbound-socket-binding named '${1}' for this to happen. >> \${error_file}
    exit
  end-if

  /socket-binding-group=standard-sockets/remote-destination-outbound-socket-binding="${1}":add(host="${2}", port="${3}")
EOF

    echo "${cli_operations}"
}

# Finds the name of the broker services and generates resource adapters
# based on this info
function inject_brokers() {
  # Find all brokers in the $MQ_SERVICE_PREFIX_MAPPING separated by ","
  IFS=',' read -a brokers <<< $MQ_SERVICE_PREFIX_MAPPING

  local subsystem_added=false
  REMOTE_AMQ_BROKER=false

  defaultJmsConnectionFactoryJndi="$DEFAULT_JMS_CONNECTION_FACTORY"

  local has_ee_subsystem
  local xpath="\"//*[local-name()='subsystem' and starts-with(namespace-uri(), 'urn:jboss:domain:ee:')]\""
  testXpathExpression "${xpath}" "has_ee_subsystem"

  if [ "${#brokers[@]}" -gt "0" ] ; then
    for broker in ${brokers[@]}; do
      log_info "Processing broker: $broker"
      service_name=${broker%=*}
      service=${service_name^^}
      service=${service//-/_}
      type=${service##*_}
      # generally MQ
      prefix=${broker#*=}

      if [ "${type}" == "AMQ" ]; then
         log_warning "You provided amq as broker type (via MQ_SERVICE_PREFIX_MAPPING environment variable): $brokers. However, AMQ6 is not supported. " >> "${CONFIG_ERROR_FILE}"
         continue
      fi
      # XXX: only tcp (openwire) is supported by EAP
      # Protocol environment variable name format: [NAME]_[BROKER_TYPE]_PROTOCOL
      protocol=$(find_env "${prefix}_PROTOCOL" "tcp")

      if [ "${protocol}" == "openwire" ]; then
        protocol="tcp"
      fi

      if [ "${protocol}" != "tcp" ]; then
        log_warning "There is a problem with your service configuration!"
        log_warning "Only openwire (tcp) transports are supported."
        continue
      fi

      protocol_env=${protocol//[-+.]/_}
      protocol_env=${protocol_env^^}

      # These environment entries are auto generated by Opensift processing the services configured in the image templates.
      local host_var="${service}_${protocol_env}_SERVICE_HOST"
      local port_var="${service}_${protocol_env}_SERVICE_PORT"
      if [ "$type" = "AMQ7" ] ; then
        # remap for AMQ7 config vars, AMQ7 gets looked up as AMQ
        host_var="${service/%AMQ7/AMQ}_${protocol_env}_SERVICE_HOST"
        port_var="${service/%AMQ7/AMQ}_${protocol_env}_SERVICE_PORT"
      fi
      host=$(find_env "${host_var}")
      port=$(find_env "${port_var}")

      if [ -z $host ] || [ -z $port ]; then
        log_warning "There is a problem with your service configuration!"
        log_warning "You provided following MQ mapping (via MQ_SERVICE_PREFIX_MAPPING environment variable): $brokers. To configure resource adapters we expect ${host_var} and ${port_var} to be set."
        log_warning
        log_warning "Current values:"
        log_warning
        log_warning "${host_var}: $host"
        log_warning "${port_var}: $port"
        log_warning
        log_warning "Please make sure you provided correct service name and prefix in the mapping. Additionally please check that you do not set portalIP to None in the $service_name service. Headless services are not supported at this time."
        log_warning
        log_warning "The ${type,,} broker for $prefix service WILL NOT be configured."
        continue
      fi

      # Custom JNDI environment variable name format: [NAME]_[BROKER_TYPE]_JNDI
      jndi=$(find_env "${prefix}_JNDI" "java:/$service_name/ConnectionFactory")

      # username environment variable name format: [NAME]_[BROKER_TYPE]_USERNAME
      username=$(find_env "${prefix}_USERNAME")

      # password environment variable name format: [NAME]_[BROKER_TYPE]_PASSWORD
      password=$(find_env "${prefix}_PASSWORD")

      # queues environment variable name format: [NAME]_[BROKER_TYPE]_QUEUES
      queues=$(find_env "${prefix}_QUEUES")

      # topics environment variable name format: [NAME]_[BROKER_TYPE]_TOPICS
      topics=$(find_env "${prefix}_TOPICS")

      if [ -z "${username}" ] || [ -z "${password}" ]; then
        log_warning "There is a problem with your service configuration!"
        log_warning "You provided following MQ mapping (via MQ_SERVICE_PREFIX_MAPPING environment variable): $brokers. To configure resource adapters we expect ${prefix}_USERNAME and ${prefix}_PASSWORD to be set."
        log_warning
        log_warning "The ${type,,} broker for $prefix service WILL NOT be configured."
        continue
      fi

      case "$type" in
        "AMQ7")
          # Currently it is not supported multi AMQ7 broker support
          if [ "${REMOTE_AMQ_BROKER}" = "true" ]; then
            echo "You provided more than one AMQ7 brokers configuration (via MQ_SERVICE_PREFIX_MAPPING environment variable): $brokers. However, multi AMQ7 broker support is not yet supported. " >> "${CONFIG_ERROR_FILE}"
            continue
          fi

          REMOTE_AMQ_BROKER=true

          if [ "$subsystem_added" != "true" ] ; then
                local cli_operations
                IFS= read -rd '' cli_operations << EOF

                  if (outcome != success) of /subsystem=messaging-activemq:read-resource
                    echo You have set MQ_SERVICE_PREFIX_MAPPING environment variable to configure the service name '${service_name}' under '${prefix}' prefix. Fix your configuration to contain messaging-activemq subsystem for this to happen. >> \${error_file}
                    exit
                  end-if
EOF
                echo "${cli_operations}" >> "${CLI_SCRIPT_FILE}"
                subsystem_added=true
          fi

          # socket binding used by remote connectors
          # this should be configurable - see CLOUD-2225 for multi broker support
          local socket_binding_name="messaging-remote-throughput"
          socket_binding=$(generate_remote_artemis_socket_binding_cli "${socket_binding_name}" "${host}" "${port}")
          echo "${socket_binding}" >> "${CLI_SCRIPT_FILE}"

          if [ "${subsystem_added}" = "true" ]; then
            local connector=$(generate_remote_artemis_remote_connector_cli "${socket_binding_name}")
            echo "${connector}" >> "${CLI_SCRIPT_FILE}"
          fi

          # this name should also be configurable (CLOUD-2225)
          local cnx_factory_name="activemq-ra-remote"
          EJB_RESOURCE_ADAPTER_NAME=${cnx_factory_name}.rar
          if [ "${subsystem_added}" = "true" ]; then
            cnx_factory=$(generate_remote_artemis_connection_factory_cli "${cnx_factory_name}" "${username}" "${password}" "${jndi}")
            echo "${cnx_factory}" >> "${CLI_SCRIPT_FILE}"
          fi

          # Naming subsystem
          local remote_context_name="remoteContext"
          naming=$(generate_remote_artemis_naming_cli "${remote_context_name}" "${host}" "${port}")
          echo "${naming}" >> "${CLI_SCRIPT_FILE}"

          local lookup
          local prop
          IFS=',' read -a amq7_queues <<< ${queues:-}
          if [ "${#amq7_queues[@]}" -ne "0" ]; then
              for q in ${amq7_queues[@]}; do
                  prop=$(generate_remote_artemis_property_cli "${remote_context_name}" "queue" ${q})
                  echo "${prop}" >> "${CLI_SCRIPT_FILE}"

                  lookup=$(generate_remote_artemis_lookup_cli "${remote_context_name}" ${q})
                  echo "${lookup}" >> "${CLI_SCRIPT_FILE}"
              done
          fi

          IFS=',' read -a amq7_topics <<< ${topics:-}
          if [ "${#amq7_topics[@]}" -ne "0" ]; then
              for t in ${amq7_topics[@]}; do
                  prop=$(generate_remote_artemis_property_cli "${remote_context_name}" "topic" ${t})
                  echo "${prop}" >> "${CLI_SCRIPT_FILE}"

                  lookup=$(generate_remote_artemis_lookup_cli "${remote_context_name}" ${t})
                  echo "${lookup}" >> "${CLI_SCRIPT_FILE}"
              done
          fi

         ;;
      esac

      # first defined broker is the default.
      if [ -z "$defaultJmsConnectionFactoryJndi" ] ; then
        defaultJmsConnectionFactoryJndi="${jndi}"
      fi

    done
    if [ "$REMOTE_AMQ_BROKER" = "true" ] ; then
      JBOSS_MESSAGING_ARGS="${JBOSS_MESSAGING_ARGS} -Dejb.resource-adapter-name=${EJB_RESOURCE_ADAPTER_NAME:-activemq-rar.rar}"
    fi
  fi

  if [ "${has_ee_subsystem}" -eq 0 ]; then
      if [ "$REMOTE_AMQ_BROKER" = "true" ] && [ -n "${defaultJmsConnectionFactoryJndi}" ]; then
        echo "/subsystem=ee/service=default-bindings:write-attribute(name=jms-connection-factory, value=\"${defaultJmsConnectionFactoryJndi}\")" >> "${CLI_SCRIPT_FILE}"
      fi
  fi

}