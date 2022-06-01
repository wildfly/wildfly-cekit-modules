#!/bin/sh
# Openshift EAP CD launch script routines for configuring messaging

if [ -z "${TEST_ACTIVEMQ_SUBSYSTEM_FILE_INCLUDE}" ]; then
    ACTIVEMQ_SUBSYSTEM_FILE=$JBOSS_HOME/bin/launch/activemq-subsystem.xml
else
    ACTIVEMQ_SUBSYSTEM_FILE=${TEST_ACTIVEMQ_SUBSYSTEM_FILE_INCLUDE}
fi

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
  unset MQ_SIMPLE_DEFAULT_PHYSICAL_DESTINATION
}

function configure() {
   can_add_embedded

  if [ $? -eq 1 ]; then
    DISABLE_EMBEDDED_JMS_BROKER="always"
  fi

  configure_artemis_address
  inject_brokers
  configure_mq
  configure_thread_pool
  disable_unused_rar
}

function configure_artemis_address() {
    IP_ADDR=${JBOSS_MESSAGING_HOST:-`hostname -i`}
    JBOSS_MESSAGING_ARGS="${JBOSS_MESSAGING_ARGS} -Djboss.messaging.host=${IP_ADDR}"
}
# /subsystem=messaging-activemq/server=default/jms-queue=queue_name:add(entries=[])

# Arguments:
# $1 - mode - xml or cli
# $2 - server name - Relevant only on cli mode
function configure_mq_destinations() {
  declare conf_mode="${1}" server_name="${2}"

  IFS=',' read -a queues <<< ${MQ_QUEUES:-$HORNETQ_QUEUES}
  IFS=',' read -a topics <<< ${MQ_TOPICS:-$HORNETQ_TOPICS}

  local destinations=""
  if [ "${#queues[@]}" -ne "0" -o "${#topics[@]}" -ne "0" ]; then
    if [ "${#queues[@]}" -ne "0" ]; then
      for queue in ${queues[@]}; do
        if [ "${conf_mode}" = "xml" ]; then
          destinations="${destinations}<jms-queue name=\"${queue}\" entries=\"/queue/${queue}\"/>"
        elif [ "${conf_mode}" = "cli" ]; then
          destinations="${destinations}
                        /subsystem=messaging-activemq/server=\"${server_name}\"/jms-queue=\"${queue}\":add(entries=[\"/queue/${queue}\"])"
        fi
      done
    fi
    if [ "${#topics[@]}" -ne "0" ]; then
      for topic in ${topics[@]}; do
        if [ "${conf_mode}" = "xml" ]; then
          destinations="${destinations}<jms-topic name=\"${topic}\" entries=\"/topic/${topic}\"/>"
        elif [ "${conf_mode}" = "cli" ]; then
          destinations="${destinations}
                        /subsystem=messaging-activemq/server=\"${server_name}\"/jms-topic=\"${topic}\":add(entries=[\"/topic/${topic}\"])"
        fi
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

    local messaging_subsystem_config_mode
    getConfigurationMode "<!-- ##MESSAGING_SUBSYSTEM_CONFIG## -->" "messaging_subsystem_config_mode"

    destinations=$(configure_mq_destinations "${messaging_subsystem_config_mode}" "default")

    local error_message_text
    if [ -n "${destinations}" ]; then
      error_message_text="You have configured messaging queues via 'MQ_QUEUES' or 'HORNETQ_QUEUES' or topics via 'MQ_TOPICS' or 'HORNETQ_TOPICS' variables"
    else
      error_message_text="An embedded messaging broker is added by default, to disable configuring an embedded messaging broker set the DISABLE_EMBEDDED_JMS_BROKER environment variable to true"
    fi

    local embeddedBroker="false"
    local activemq_subsystem
    if [ "${messaging_subsystem_config_mode}" = "xml" ]; then
      # We need the broker if they configured destinations or didn't explicitly disable the broker AND there's a point to doing it because the marker exists
      if ([ -n "${destinations}" ] || ([ "x${DISABLE_EMBEDDED_JMS_BROKER}" != "xtrue" ] && [ "x${DISABLE_EMBEDDED_JMS_BROKER}" != "xalways" ]) ) && grep -q '<!-- ##MESSAGING_SUBSYSTEM_CONFIG## -->' ${CONFIG_FILE}; then
        activemq_subsystem=$(sed -e "s|<!-- ##DESTINATIONS## -->|${destinations}|" <"${ACTIVEMQ_SUBSYSTEM_FILE}" | sed ':a;N;$!ba;s|\n|\\n|g')
        sed -i "s|<!-- ##MESSAGING_SUBSYSTEM_CONFIG## -->|${activemq_subsystem%$'\n'}|" "${CONFIG_FILE}"
        embeddedBroker="true"
      fi
    elif [ "${messaging_subsystem_config_mode}" = "cli" ]; then
      # We need the broker if there are destinations or it wasn't explicitly disabled.
      # In the new configuration we cannot rely on marker precense since it is not supplied by default, and not supplying it does not mean
      # we don't want the embedded server configuration.
      # If we do not want the embeded server added when there are no destinations, then DISABLE_EMBEDDED_JMS_BROKER should be explicitely set to always.
      if ([ -n "${destinations}" ] || [ "x${DISABLE_EMBEDDED_JMS_BROKER}" != "xtrue" ]) && [ "x${DISABLE_EMBEDDED_JMS_BROKER}" != "xalways" ]; then
        activemq_subsystem=$(add_messaging_default_server_cli "${error_message_text}" "${destinations}")
        if [ -n "${activemq_subsystem}" ]; then
          echo "${activemq_subsystem}" >> "${CLI_SCRIPT_FILE}"
          embeddedBroker="true"
        fi
      fi
    fi

    if [ "${embeddedBroker}" = "true" ]; then

      echo "Configuration of an embedded messaging broker within the appserver is enabled but is not recommended. Support for such a configuration will be removed in a future release." >> "${CONFIG_WARNING_FILE}"
      if [ "x${DISABLE_EMBEDDED_JMS_BROKER}" != "xtrue" ]; then
        echo "If you are not configuring messaging destinations, to disable configuring an embedded messaging broker set the DISABLE_EMBEDDED_JMS_BROKER environment variable to true." >> "${CONFIG_WARNING_FILE}"
      fi

      local messaging_ports_config_mode
      getConfigurationMode "<!-- ##MESSAGING_PORTS## -->" "messaging_ports_config_mode"

      if [ "${messaging_ports_config_mode}" = "xml" ]; then
        sed -i 's|<!-- ##MESSAGING_PORTS## -->|<socket-binding name="messaging" port="5445"/><socket-binding name="messaging-throughput" port="5455"/>|' "${CONFIG_FILE}"
      elif [ "${messaging_ports_config_mode}" = "cli" ]; then
        local cli_operations
        IFS= read -rd '' cli_operations << EOF
        if (outcome == success) of /socket-binding-group=standard-sockets/socket-binding=messaging:read-resource
          echo ${error_message_text}. Fix your configuration to not contain a socket-binding named 'messaging' for this to happen. >> \${error_file}
          exit
        end-if

        if (outcome == success) of /socket-binding-group=standard-sockets/socket-binding=messaging-throughput:read-resource
          echo ${error_message_text}. Fix your configuration to not contain a socket-binding named 'messaging-throughput' for this to happen. >> \${error_file}
          exit
        end-if

        /socket-binding-group=standard-sockets/socket-binding=messaging:add(port=5445)
        /socket-binding-group=standard-sockets/socket-binding=messaging-throughput:add(port=5455)
EOF
      echo "${cli_operations}" >> "${CLI_SCRIPT_FILE}"
      fi
    fi
  fi
}

# Currently, the JVM is not cgroup aware and cannot be trusted to generate default values for
# threads pool args. Therefore, if there are resource limits specifed by the container, this function
# will configure the thread pool args using cgroups and the formulae provied by https://github.com/apache/activemq-artemis/blob/master/artemis-core-client/src/main/java/org/apache/activemq/artemis/api/core/client/ActiveMQClient.java
function configure_thread_pool() {
  source /opt/run-java/container-limits
  if [ -n "$CORE_LIMIT" ]; then
    local mtp=$(expr 8 \* $CORE_LIMIT) # max thread pool size
    local ctp=5                                  # core thread pool size
    JBOSS_MESSAGING_ARGS="${JBOSS_MESSAGING_ARGS}
    -Dactivemq.artemis.client.global.thread.pool.max.size=$mtp
    -Dactivemq.artemis.client.global.scheduled.thread.pool.core.size=$ctp"
  fi
}

# $1 - name - messaging-remote-throughput
# <!-- ##AMQ_REMOTE_CONNECTOR## -->
function generate_remote_artemis_remote_connector() {
    echo "<remote-connector name=\"netty-remote-throughput\" socket-binding=\"${1}\"/>" | sed -e ':a;N;$!ba;s|\n|\\n|g'
}

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
# <!-- ##AMQ_REMOTE_CONTEXT## -->
function generate_remote_artemis_naming() {
    echo "<bindings><external-context name=\"java:global/${1}\" module=\"org.apache.activemq.artemis\" class=\"javax.naming.InitialContext\">
              <environment>
                  <property name=\"java.naming.factory.initial\" value=\"org.apache.activemq.artemis.jndi.ActiveMQInitialContextFactory\"/>
                      <property name=\"java.naming.provider.url\" value=\"tcp://${2}:${3}\"/>
                      <!-- ##AMQ7_CONFIG_PROPERTIES## -->
              </environment>
          </external-context>
          <!-- ##AMQ_LOOKUP_OBJECTS## --></bindings>" | sed -e ':a;N;$!ba;s|\n|\\n|g'
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
# <!-- ##AMQ_POOLED_CONNECTION_FACTORY## -->
function generate_remote_artemis_connection_factory() {
    echo "<pooled-connection-factory user=\"${2}\" password=\"${3}\" name=\"${1}\" entries=\"java:/JmsXA java:/RemoteJmsXA java:jboss/RemoteJmsXA ${4}\" connectors=\"netty-remote-throughput\" transaction=\"xa\"/>" | sed -e ':a;N;$!ba;s|\n|\\n|g'
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

# $1 object type - queue / topic
# $2 object name - MyQueue / MyTopic
# <!-- ##AMQ7_CONFIG_PROPERTIES## -->
function generate_remote_artemis_property() {
  declare queue_topic="${1}" object_name="${2}"
  echo "<property name=\"${queue_topic}.${object_name}\" value=\"${object_name}\"/>" | sed -e ':a;N;$!ba;s|\n|\\n|g'
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
# <!-- ##AMQ_LOOKUP_OBJECTS## -->
function generate_remote_artemis_lookup() {
    echo "<lookup name=\"java:/${2}\" lookup=\"java:global/${1}/${2}\"/>" | sed -e ':a;N;$!ba;s|\n|\\n|g'
}

# $1 - remote context - remoteContext
# $2 - object name - MyQueue / MyTopic etc
function generate_remote_artemis_lookup_cli() {
    echo "/subsystem=naming/binding=\"java:/${2}\":add(binding-type=lookup, lookup=\"java:global/${1}/${2}\")"
}

# $1 - name - messaging-remote-throughput
# $2 - remote hostname
# $3 - remote port
# <!-- ##AMQ_MESSAGING_SOCKET_BINDING## -->
function generate_remote_artemis_socket_binding() {
    echo "<outbound-socket-binding name=\"${1}\">
            <remote-destination host=\"${2}\" port=\"${3}\"/>
         </outbound-socket-binding>" | sed -e ':a;N;$!ba;s|\n|\\n|g'
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

# Arguments:
# $1 - physical name
# $2 - jndi name
# $3 - class
function generate_object_config() {
  echo "generating object config for $1" >&2

  ao="
                        <admin-object
                              class-name=\"$3\"
                              jndi-name=\"$2\"
                              use-java-context=\"true\"
                              pool-name=\"$1\">
                            <config-property name=\"PhysicalName\">$1</config-property>
                        </admin-object>"
  echo $ao
}

# Arguments:
# $1 - physical name
# $2 - jndi name
# $3 - class
# $4 - resource adapter name
function generate_object_config_cli() {
  log_info "generating CLI object config for $1"  >&2

  local cli_operations
  IFS= read -rd '' cli_operations << EOF

  /subsystem=resource-adapters/resource-adapter="${4}"/admin-objects="${1}":add(class-name="${3}", jndi-name="${2}", use-java-context=true)
  /subsystem=resource-adapters/resource-adapter="${4}"/admin-objects="${1}"/config-properties=PhysicalName:add(value="${1}")
EOF

  echo "${cli_operations}"
}

# Arguments:
# $1 - service name
# $2 - connection factory jndi name
# $3 - broker username
# $4 - broker password
# $5 - protocol
# $6 - broker host
# $7 - broker port
# $8 - prefix
# $9 - archive
# $10 - driver
# $11 - queue names
# $12 - topic names
# $13 - ra tracking
# $14 - resource counter, incremented for each broker, starting at 0
function generate_resource_adapter() {
  log_info "Generating resource adapter configuration for service: $1 (${10})" >&2
  IFS=',' read -a queues <<< ${11}
  IFS=',' read -a topics <<< ${12}

  local ra_id=""
  # this preserves the expected behavior of the first RA, and doesn't append a number. Any additional RAs will have -count appended.
  if [ "${14}" -eq "0" ]; then
    ra_id="${9}"
  else
    ra_id="${9}-${14}"
  fi

  # if we don't declare a EJB_RESOURCE_ADAPTER_NAME, then just use the first one
  if [ -z "${EJB_RESOURCE_ADAPTER_NAME}" ]; then
    export EJB_RESOURCE_ADAPTER_NAME="${ra_id}"
  fi

  local ra_tracking
  if [ -n "${13}" ]; then
    ra_tracking="tracking=\"${13}\""
  fi

  case "${10}" in
    "amq")
      prefix=$8
      ra="
                <resource-adapter id=\"${ra_id}\">
                    <archive>$9</archive>
                    <transaction-support>XATransaction</transaction-support>
                    <config-property name=\"UserName\">$3</config-property>
                    <config-property name=\"Password\">$4</config-property>
                    <config-property name=\"ServerUrl\">tcp://$6:$7?jms.rmIdFromConnectionId=true</config-property>
                    <connection-definitions>
                        <connection-definition
                              "${ra_tracking}"
                              class-name=\"org.apache.activemq.ra.ActiveMQManagedConnectionFactory\"
                              jndi-name=\"$2\"
                              enabled=\"true\"
                              pool-name=\"$1-ConnectionFactory\">
                            <xa-pool>
                                <min-pool-size>1</min-pool-size>
                                <max-pool-size>20</max-pool-size>
                                <prefill>false</prefill>
                                <is-same-rm-override>false</is-same-rm-override>
                            </xa-pool>
                            <recovery>
                                <recover-credential>
                                    <user-name>$3</user-name>
                                    <password>$4</password>
                                </recover-credential>
                            </recovery>
                        </connection-definition>
                    </connection-definitions>
                    <admin-objects>"

      # backwards-compatability flag per CLOUD-329
      simple_def_phys_dest=$(echo "${MQ_SIMPLE_DEFAULT_PHYSICAL_DESTINATION}" | tr [:upper:] [:lower:])

      if [ "${#queues[@]}" -ne "0" ]; then
        for queue in ${queues[@]}; do
          queue_env=${prefix}_QUEUE_${queue^^}
          queue_env=${queue_env//[-\.]/_}

          if [ "${simple_def_phys_dest}" = "true" ]; then
            physical=$(find_env "${queue_env}_PHYSICAL" "$queue")
          else
            physical=$(find_env "${queue_env}_PHYSICAL" "queue/$queue")
          fi
          jndi=$(find_env "${queue_env}_JNDI" "java:/queue/$queue")
          class="org.apache.activemq.command.ActiveMQQueue"

          ra="$ra$(generate_object_config $physical $jndi $class)"
        done
      fi

      if [ "${#topics[@]}" -ne "0" ]; then
        for topic in ${topics[@]}; do
          topic_env=${prefix}_TOPIC_${topic^^}
          topic_env=${topic_env//[-\.]/_}

          if [ "${simple_def_phys_dest}" = "true" ]; then
            physical=$(find_env "${topic_env}_PHYSICAL" "$topic")
          else
            physical=$(find_env "${topic_env}_PHYSICAL" "topic/$topic")
          fi
          jndi=$(find_env "${topic_env}_JNDI" "java:/topic/$topic")
          class="org.apache.activemq.command.ActiveMQTopic"

          ra="$ra$(generate_object_config $physical $jndi $class)"
        done
      fi

      ra="$ra
                    </admin-objects>
                </resource-adapter>"
    ;;
  "amq7")
      prefix=$8
    ;;
  esac

  echo $ra | sed ':a;N;$!ba;s|\n|\\n|g'
}

# Arguments:
# $1 - service name
# $2 - connection factory jndi name
# $3 - broker username
# $4 - broker password
# $5 - protocol
# $6 - broker host
# $7 - broker port
# $8 - prefix
# $9 - archive
# $10 - driver
# $11 - queue names
# $12 - topic names
# $13 - ra tracking
# $14 - resource counter, incremented for each broker, starting at 0
function generate_resource_adapter_cli() {
  log_info "Generating CLI resource adapter configuration for service: $1 (${10})" >&2
  IFS=',' read -a queues <<< ${11}
  IFS=',' read -a topics <<< ${12}

  local cli_operations=""

  local ra_id=""
  # this preserves the expected behavior of the first RA, and doesn't append a number. Any additional RAs will have -count appended.
  if [ "${14}" -eq "0" ]; then
    ra_id="${9}"
  else
    ra_id="${9}-${14}"
  fi

  # if we don't declare a EJB_RESOURCE_ADAPTER_NAME, then just use the first one
  if [ -z "${EJB_RESOURCE_ADAPTER_NAME}" ]; then
    export EJB_RESOURCE_ADAPTER_NAME="${ra_id}"
  fi

  local ra_tracking
  if [ -n "${13}" ]; then
    ra_tracking="tracking=\"${13}\", "
  fi

  case "${10}" in
    "amq")
    IFS= read -rd '' cli_operations <<- EOF

      if (outcome != success) of /subsystem=resource-adapters:read-resource
        echo You have set MQ_SERVICE_PREFIX_MAPPING environment variable to configure the service name '${1}' under '${8}' prefix. Fix your configuration to contain resource adapters subsystem for this to happen. >> \${error_file}
        exit
      end-if

      /subsystem=resource-adapters/resource-adapter="${ra_id}":add(archive=$9, transaction-support=XATransaction)
      /subsystem=resource-adapters/resource-adapter="${ra_id}"/config-properties=UserName:add(value="${3}")
      /subsystem=resource-adapters/resource-adapter="${ra_id}"/config-properties=Password:add(value="${4}")
      /subsystem=resource-adapters/resource-adapter="${ra_id}"/config-properties=ServerUrl:add(value="tcp://${6}:${7}?jms.rmIdFromConnectionId=true")
EOF

      local connection_definition="/subsystem=resource-adapters/resource-adapter=\"${ra_id}\"/connection-definitions=\"${1}-ConnectionFactory\":add(${ra_tracking}\
class-name=org.apache.activemq.ra.ActiveMQManagedConnectionFactory, jndi-name=\"${2}\", enabled=true, min-pool-size=1, max-pool-size=20, \
pool-prefill=false, same-rm-override=false, recovery-username=\"${3}\", recovery-password=\"${4}\""


    local has_security_subsystem
    local xpath="\"//*[local-name()='subsystem' and starts-with(namespace-uri(), 'urn:jboss:domain:security:')]\""
    testXpathExpression "${xpath}" "has_security_subsystem"

    local has_elytron_subsystem
    local xpath="\"//*[local-name()='subsystem' and starts-with(namespace-uri(), 'urn:wildfly:elytron:')]\""
    testXpathExpression "${xpath}" "has_elytron_subsystem"

    if [ "${has_security_subsystem}" -ne 0 ]; then
      if [ "${has_elytron_subsystem}" -ne 0 ]; then
        echo "${error_message_text}. Fix your configuration to contain Elytron subsystem for this to happen." >> "${CONFIG_ERROR_FILE}"
        return
      fi
      connection_definition="${connection_definition}, elytron-enabled=true, recovery-elytron-enabled=true"
    fi
    connection_definition="${connection_definition})"

    cli_operations="${cli_operations}
                    ${connection_definition}"

    # backwards-compatability flag per CLOUD-329
    simple_def_phys_dest=$(echo "${MQ_SIMPLE_DEFAULT_PHYSICAL_DESTINATION}" | tr [:upper:] [:lower:])

    if [ "${#queues[@]}" -ne "0" ]; then
      for queue in ${queues[@]}; do
        queue_env=${prefix}_QUEUE_${queue^^}
        queue_env=${queue_env//[-\.]/_}

        if [ "${simple_def_phys_dest}" = "true" ]; then
          physical=$(find_env "${queue_env}_PHYSICAL" "$queue")
        else
          physical=$(find_env "${queue_env}_PHYSICAL" "queue/$queue")
        fi
        jndi=$(find_env "${queue_env}_JNDI" "java:/queue/$queue")
        class="org.apache.activemq.command.ActiveMQQueue"

        cli_operations="${cli_operations}$(generate_object_config_cli "${physical}" "${jndi}" "${class}" "${ra_id}")"
      done
    fi

    if [ "${#topics[@]}" -ne "0" ]; then
      for topic in ${topics[@]}; do
        topic_env=${prefix}_TOPIC_${topic^^}
        topic_env=${topic_env//[-\.]/_}

        if [ "${simple_def_phys_dest}" = "true" ]; then
          physical=$(find_env "${topic_env}_PHYSICAL" "$topic")
        else
          physical=$(find_env "${topic_env}_PHYSICAL" "topic/$topic")
        fi
        jndi=$(find_env "${topic_env}_JNDI" "java:/topic/$topic")
        class="org.apache.activemq.command.ActiveMQTopic"

        cli_operations="${cli_operations}$(generate_object_config_cli "${physical}" "${jndi}" "${class}" "${ra_id}")"
      done
    fi

    ;;
  "amq7")
      :
    ;;
  esac

  echo "${cli_operations}"
}

# Finds the name of the broker services and generates resource adapters
# based on this info
function inject_brokers() {
  # Find all brokers in the $MQ_SERVICE_PREFIX_MAPPING separated by ","
  IFS=',' read -a brokers <<< $MQ_SERVICE_PREFIX_MAPPING

  local subsystem_added=false
  REMOTE_AMQ_BROKER=false
  REMOTE_AMQ6=false
  REMOTE_AMQ7=false
  has_default_cnx_factory=false

  defaultJmsConnectionFactoryJndi="$DEFAULT_JMS_CONNECTION_FACTORY"

  local resource_adapters_mode
  getConfigurationMode "<!-- ##RESOURCE_ADAPTERS## -->" "resource_adapters_mode"

  local amq_messaging_socket_binding_mode
  getConfigurationMode "<!-- ##AMQ_MESSAGING_SOCKET_BINDING## -->" "amq_messaging_socket_binding_mode"

  local messaging_subsystem_config_mode
  getConfigurationMode "<!-- ##MESSAGING_SUBSYSTEM_CONFIG## -->" "messaging_subsystem_config_mode"

  local amg_remote_context_config_mode
  getConfigurationMode "<!-- ##AMQ_REMOTE_CONTEXT## -->" "amg_remote_context_config_mode"

  local default_jms_config_mode
  getConfigurationMode "##DEFAULT_JMS##" "default_jms_config_mode"

  local has_ee_subsystem
  local xpath="\"//*[local-name()='subsystem' and starts-with(namespace-uri(), 'urn:jboss:domain:ee:')]\""
  testXpathExpression "${xpath}" "has_ee_subsystem"

  local has_resource_adapters
  local xpath="\"//*[local-name()='subsystem' and starts-with(namespace-uri(), 'urn:jboss:domain:resource-adapters:')]\""
  testXpathExpression "${xpath}" "has_resource_adapters"

  if [ "${#brokers[@]}" -eq "0" ] ; then
    if [ -z "$defaultJmsConnectionFactoryJndi" ]; then
        defaultJmsConnectionFactoryJndi="java:jboss/DefaultJMSConnectionFactory"
    fi
  else
    local counter=0
    for broker in ${brokers[@]}; do
      log_info "Processing broker($counter): $broker"
      service_name=${broker%=*}
      service=${service_name^^}
      service=${service//-/_}
      type=${service##*_}
      # generally MQ
      prefix=${broker#*=}

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

      tracking=$(find_env "${prefix}_TRACKING")

      if [ -z "${username}" ] || [ -z "${password}" ]; then
        log_warning "There is a problem with your service configuration!"
        log_warning "You provided following MQ mapping (via MQ_SERVICE_PREFIX_MAPPING environment variable): $brokers. To configure resource adapters we expect ${prefix}_USERNAME and ${prefix}_PASSWORD to be set."
        log_warning
        log_warning "The ${type,,} broker for $prefix service WILL NOT be configured."
        continue
      fi

      local driver
      local archive
      case "$type" in
        "AMQ")
          # This is the legacy AMQ configuration. In this case we only configure the resource adapters subsystem adding activemq-rar.rar
          # It is possible configure more than one
          driver="amq"
          archive="activemq-rar.rar"
          REMOTE_AMQ_BROKER=true
          REMOTE_AMQ6=true

          if [ "${resource_adapters_mode}" = "xml" ]; then
            ra=$(generate_resource_adapter ${service_name} ${jndi} ${username} ${password} ${protocol} ${host} ${port} ${prefix} ${archive} ${driver} "${queues}" "${topics}" "${tracking}" ${counter})
            sed -i "s|<!-- ##RESOURCE_ADAPTERS## -->|${ra%$'\n'}<!-- ##RESOURCE_ADAPTERS## -->|" $CONFIG_FILE
          elif [ "${resource_adapters_mode}" = "cli" ]; then
            ra=$(generate_resource_adapter_cli ${service_name} ${jndi} ${username} ${password} ${protocol} ${host} ${port} ${prefix} ${archive} ${driver} "${queues}" "${topics}" "${tracking}" ${counter})
            echo "${ra}" >> "${CLI_SCRIPT_FILE}"
          fi

          ;;
        "AMQ7")
          # Currently it is not supported multi AMQ7 broker support
          if [ "${REMOTE_AMQ7}" = "true" ]; then
            echo "You provided more than one AMQ7 brokers configuration (via MQ_SERVICE_PREFIX_MAPPING environment variable): $brokers. However, multi AMQ7 broker support is not yet supported. " >> "${CONFIG_ERROR_FILE}"
            continue
          fi

          driver="amq7"
          archive=""
          REMOTE_AMQ_BROKER=true
          REMOTE_AMQ7=true

          # Insert default messaging subsystem configuration.
          # The default XML template (activemq-subsystem.xml) includes the following markers:
          # <!-- ##AMQ_REMOTE_CONNECTOR## -->, <!-- ##DESTINATIONS## -->, <!-- ##AMQ_POOLED_CONNECTION_FACTORY## -->
          if [ "$subsystem_added" != "true" ] ; then
              if [ "${messaging_subsystem_config_mode}" = "xml" ]; then
                add_messaging_default_server
                subsystem_added=true
              elif [ "${messaging_subsystem_config_mode}" = "cli" ]; then
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
          fi

          # socket binding used by remote connectors
          # this should be configurable - see CLOUD-2225 for multi broker support
          local socket_binding_name="messaging-remote-throughput"

          if [ "${amq_messaging_socket_binding_mode}" = "xml" ]; then

            socket_binding=$(generate_remote_artemis_socket_binding "${socket_binding_name}" "${host}" "${port}")
            sed -i "s|<!-- ##AMQ_MESSAGING_SOCKET_BINDING## -->|${socket_binding%$'\n'}<!-- ##AMQ_MESSAGING_SOCKET_BINDING## -->|" $CONFIG_FILE
          elif [ "${amq_messaging_socket_binding_mode}" = "cli" ]; then
            socket_binding=$(generate_remote_artemis_socket_binding_cli "${socket_binding_name}" "${host}" "${port}")
            echo "${socket_binding}" >> "${CLI_SCRIPT_FILE}"
          fi


          local amq_remote_connector_mode
          getConfigurationMode "<!-- ##AMQ_REMOTE_CONNECTOR## -->" "amq_remote_connector_mode"

          local connector
          if [ "${amq_remote_connector_mode}" = "xml" ]; then
            connector=$(generate_remote_artemis_remote_connector "${socket_binding_name}")
            sed -i "s|<!-- ##AMQ_REMOTE_CONNECTOR## -->|${connector%$'\n'}<!-- ##AMQ_REMOTE_CONNECTOR## -->|" $CONFIG_FILE
          elif [ "${amq_remote_connector_mode}" = "cli" ] && [ "${subsystem_added}" = "true" ]; then
            connector=$(generate_remote_artemis_remote_connector_cli "${socket_binding_name}")
            echo "${connector}" >> "${CLI_SCRIPT_FILE}"
          fi


          # this name should also be configurable (CLOUD-2225)
          local cnx_factory_name="activemq-ra-remote"
          EJB_RESOURCE_ADAPTER_NAME=${cnx_factory_name}.rar

          local amq_pooled_connection_factory_mode
          getConfigurationMode "<!-- ##AMQ_POOLED_CONNECTION_FACTORY## -->" "amq_pooled_connection_factory_mode"

          if [ "${amq_pooled_connection_factory_mode}" = "xml" ]; then
            cnx_factory=$(generate_remote_artemis_connection_factory "${cnx_factory_name}" "${username}" "${password}" "${jndi}")
            sed -i "s|<!-- ##AMQ_POOLED_CONNECTION_FACTORY## -->|${cnx_factory%$'\n'}<!-- ##AMQ_POOLED_CONNECTION_FACTORY## -->|" $CONFIG_FILE
          elif [ "${amq_pooled_connection_factory_mode}" = "cli" ] && [ "${subsystem_added}" = "true" ]; then
            cnx_factory=$(generate_remote_artemis_connection_factory_cli "${cnx_factory_name}" "${username}" "${password}" "${jndi}")
            echo "${cnx_factory}" >> "${CLI_SCRIPT_FILE}"
          fi


          # Naming subsystem
          # It adds the following markers:
          # <!-- ##AMQ7_CONFIG_PROPERTIES## -->
          # <!-- ##AMQ_LOOKUP_OBJECTS## -->
          local remote_context_name="remoteContext"
          if [ "${amg_remote_context_config_mode}" = "xml" ]; then
            naming=$(generate_remote_artemis_naming "${remote_context_name}" "${host}" "${port}")
            sed -i "s|<!-- ##AMQ_REMOTE_CONTEXT## -->|${naming%$'\n'}<!-- ##AMQ_REMOTE_CONTEXT## -->|" $CONFIG_FILE
          elif [ "${amg_remote_context_config_mode}" = "cli" ]; then
            naming=$(generate_remote_artemis_naming_cli "${remote_context_name}" "${host}" "${port}")
            echo "${naming}" >> "${CLI_SCRIPT_FILE}"
          fi

          local amq7_config_properties_mode
          getConfigurationMode "<!-- ##AMQ7_CONFIG_PROPERTIES## -->" "amq7_config_properties_mode"

          local amq_lookup_objects_mode
          getConfigurationMode "<!-- ##AMQ_LOOKUP_OBJECTS## -->" "amq_lookup_objects_mode"

          local lookup
          local prop
          IFS=',' read -a amq7_queues <<< ${queues:-}
          if [ "${#amq7_queues[@]}" -ne "0" ]; then
              for q in ${amq7_queues[@]}; do
                if [ "${amq7_config_properties_mode}" = "xml" ]; then
                  prop=$(generate_remote_artemis_property "queue" ${q})
                  sed -i "s|<!-- ##AMQ7_CONFIG_PROPERTIES## -->|${prop%$'\n'}<!-- ##AMQ7_CONFIG_PROPERTIES## -->|" $CONFIG_FILE
                elif [ "${amq7_config_properties_mode}" = "cli" ]; then
                  prop=$(generate_remote_artemis_property_cli "${remote_context_name}" "queue" ${q})
                  echo "${prop}" >> "${CLI_SCRIPT_FILE}"
                fi

                if [ "${amq_lookup_objects_mode}" = "xml" ]; then
                  lookup=$(generate_remote_artemis_lookup "${remote_context_name}" ${q})
                  sed -i "s|<!-- ##AMQ_LOOKUP_OBJECTS## -->|${lookup%$'\n'}<!-- ##AMQ_LOOKUP_OBJECTS## -->|" $CONFIG_FILE
                elif [ "${amq_lookup_objects_mode}" = "cli" ]; then
                  lookup=$(generate_remote_artemis_lookup_cli "${remote_context_name}" ${q})
                  echo "${lookup}" >> "${CLI_SCRIPT_FILE}"
                fi
              done
          fi

          IFS=',' read -a amq7_topics <<< ${topics:-}
          if [ "${#amq7_topics[@]}" -ne "0" ]; then
              for t in ${amq7_topics[@]}; do
                if [ "${amq7_config_properties_mode}" = "xml" ]; then
                  prop=$(generate_remote_artemis_property "topic" ${t})
                  sed -i "s|<!-- ##AMQ7_CONFIG_PROPERTIES## -->|${prop%$'\n'}<!-- ##AMQ7_CONFIG_PROPERTIES## -->|" $CONFIG_FILE
                elif [ "${amq7_config_properties_mode}" = "cli" ]; then
                  prop=$(generate_remote_artemis_property_cli "${remote_context_name}" "topic" ${t})
                  echo "${prop}" >> "${CLI_SCRIPT_FILE}"
                fi

                if [ "${amq_lookup_objects_mode}" = "xml" ]; then
                  lookup=$(generate_remote_artemis_lookup "${remote_context_name}" ${t})
                  sed -i "s|<!-- ##AMQ_LOOKUP_OBJECTS## -->|${lookup%$'\n'}<!-- ##AMQ_LOOKUP_OBJECTS## -->|" $CONFIG_FILE
                elif [ "${amq_lookup_objects_mode}" = "cli" ]; then
                  lookup=$(generate_remote_artemis_lookup_cli "${remote_context_name}" ${t})
                  echo "${lookup}" >> "${CLI_SCRIPT_FILE}"
                fi
              done
          fi

         ;;
      esac

      # first defined broker is the default.
      if [ -z "$defaultJmsConnectionFactoryJndi" ] ; then
        defaultJmsConnectionFactoryJndi="${jndi}"
      fi

      # increment RA counter
      counter=$((counter+1))
    done
    if [ "$REMOTE_AMQ_BROKER" = "true" ] ; then
      JBOSS_MESSAGING_ARGS="${JBOSS_MESSAGING_ARGS} -Dejb.resource-adapter-name=${EJB_RESOURCE_ADAPTER_NAME:-activemq-rar.rar}"
    fi
  fi

  defaultJms=""
  if [ -n "$defaultJmsConnectionFactoryJndi" ]; then
    defaultJms="jms-connection-factory=\"$defaultJmsConnectionFactoryJndi\""
  fi

  if [ "${has_ee_subsystem}" -eq 0 ]; then
    if [ "${default_jms_config_mode}" = "xml" ]; then
      if [ "$REMOTE_AMQ_BROKER" = "true" ] || ([ -n "${MQ_QUEUES}" ] || [ -n "${HORNETQ_QUEUES}" ] || [ -n "${MQ_TOPICS}" ] || [ -n "${HORNETQ_TOPICS}" ] || [ "x${DISABLE_EMBEDDED_JMS_BROKER}" != "xtrue" ]) && [ "x${DISABLE_EMBEDDED_JMS_BROKER}" != "xalways" ];
      then
        # new format
        sed -i "s|jms-connection-factory=\"##DEFAULT_JMS##\"|${defaultJms}|" $CONFIG_FILE
        # legacy format, bare ##DEFAULT_JMS##
        sed -i "s|##DEFAULT_JMS##|${defaultJms}|" $CONFIG_FILE
      else
        # new format
        sed -i "s|jms-connection-factory=\"##DEFAULT_JMS##\"||" $CONFIG_FILE
        # legacy format, bare ##DEFAULT_JMS##
        sed -i "s|##DEFAULT_JMS##||" $CONFIG_FILE
      fi
    elif [ "${default_jms_config_mode}" = "cli" ]; then
      if ([ "$REMOTE_AMQ_BROKER" = "true" ] || ([ -n "${MQ_QUEUES}" ] || [ -n "${HORNETQ_QUEUES}" ] || [ -n "${MQ_TOPICS}" ] || [ -n "${HORNETQ_TOPICS}" ] || [ "x${DISABLE_EMBEDDED_JMS_BROKER}" != "xtrue" ]) && [ "x${DISABLE_EMBEDDED_JMS_BROKER}" != "xalways" ]) && [ -n "${defaultJmsConnectionFactoryJndi}" ]; then
        echo "/subsystem=ee/service=default-bindings:write-attribute(name=jms-connection-factory, value=\"${defaultJmsConnectionFactoryJndi}\")" >> "${CLI_SCRIPT_FILE}"
      else
        echo "/subsystem=ee/service=default-bindings:undefine-attribute(name=jms-connection-factory)" >> "${CLI_SCRIPT_FILE}"
      fi
    fi
  fi

}

disable_unused_rar() {
  local resource_adapters_mode
  getConfigurationMode "<!-- ##RESOURCE_ADAPTERS## -->" "resource_adapters_mode"

  # Put down a skipdeploy marker for the legacy activemq-rar.rar unless there is a .dodeploy marker
  # or the rar is mentioned in the config file
  local base_rar="$JBOSS_HOME/standalone/deployments/activemq-rar.rar"
  if [ -e "${base_rar}" ] && [ ! -e "${base_rar}.dodeploy" ] && ! grep -q -E "activemq-rar\.rar" $CONFIG_FILE && ! ([ "${resource_adapters_mode}" = "cli" ] && [ "${REMOTE_AMQ6}" = "true" ]); then
    touch "$JBOSS_HOME/standalone/deployments/activemq-rar.rar.skipdeploy"
  fi
}

add_messaging_default_server() {
  local activemq_subsystem=$(sed -e ':a;N;$!ba;s|\n|\\n|g' <"${ACTIVEMQ_SUBSYSTEM_FILE}")
  sed -i "s|<!-- ##MESSAGING_SUBSYSTEM_CONFIG## -->|${activemq_subsystem%$'\n'}<!-- ##MESSAGING_SUBSYSTEM_CONFIG## -->|" $CONFIG_FILE
  # make sure the default connection factory isn't set on another cnx factory
  sed -i "s|java:jboss/DefaultJMSConnectionFactory||g" $CONFIG_FILE
  # this will be on the remote ConnectionFactory, so rename the local one until the embedded broker is dropped.
  sed -i "s|java:/JmsXA|java:/JmsXALocal|" $CONFIG_FILE
}


# Arguments:
# $1 - error message text describing the source
# $2 - destinations - Optional
add_messaging_default_server_cli() {
  declare error_message_text="${1}" destinations="${2}"

  local has_security_subsystem
  local xpath="\"//*[local-name()='subsystem' and starts-with(namespace-uri(), 'urn:jboss:domain:security:')]\""
  testXpathExpression "${xpath}" "has_security_subsystem"

  local has_elytron_subsystem
  local xpath="\"//*[local-name()='subsystem' and starts-with(namespace-uri(), 'urn:wildfly:elytron:')]\""
  testXpathExpression "${xpath}" "has_elytron_subsystem"

  if [ "${has_security_subsystem}" -ne 0 ]; then
    if [ "${has_elytron_subsystem}" -ne 0 ]; then
      # Just ignore
      return 0
    fi
  fi

  local has_remoting_subsystem
  local xpath="\"//*[local-name()='subsystem' and starts-with(namespace-uri(), 'urn:jboss:domain:remoting:')]\""
  testXpathExpression "${xpath}" "has_remoting_subsystem"

  if [ "${has_remoting_subsystem}" -ne 0 ]; then
      # Just ignore
      return 0
  fi

  local has_messaging_subsystem
  local xpath="\"//*[local-name()='subsystem' and starts-with(namespace-uri(), 'urn:jboss:domain:messaging-activemq:')]\""
  testXpathExpression "${xpath}" "has_messaging_subsystem"

  if [ "${has_messaging_subsystem}" -ne 0 ]; then
      # Just ignore
      return 0
  fi

  local cli_operations
  IFS= read -rd '' cli_operations << EOF

    if (outcome == success) of /subsystem=messaging-activemq/server=default:read-resource
      echo ${error_message_text}. Fix your configuration to not contain a default server configured on messaging-activemq subsystem for this to happen. >> \${error_file}
      exit
    end-if

    batch
      /subsystem=messaging-activemq/server=default:add(journal-pool-files=10, statistics-enabled="\${wildfly.messaging-activemq.statistics-enabled:\${wildfly.statistics-enabled:false}}")
EOF

  if [ -n "${destinations}" ]; then
    cli_operations="${cli_operations}
                    ${destinations}"
  fi

  IFS= read -rd '' tmp_operations << EOF

      /subsystem=messaging-activemq/server=default/http-connector=http-connector:add(socket-binding=http-messaging, endpoint=http-acceptor)
      /subsystem=messaging-activemq/server=default/http-connector=http-connector-throughput:add(socket-binding=http-messaging, endpoint=http-acceptor-throughput, params={"batch-delay"="50"})

      /subsystem=messaging-activemq/server=default/http-acceptor=http-acceptor:add(http-listener=default)
      /subsystem=messaging-activemq/server=default/http-acceptor=http-acceptor-throughput:add(http-listener=default, params={batch-delay=50,direct-deliver=false})

      /subsystem=messaging-activemq/server=default/in-vm-connector=in-vm:add(server-id=0, params={"buffer-pooling"="false"})
      /subsystem=messaging-activemq/server=default/in-vm-acceptor=in-vm:add(server-id=0, params={"buffer-pooling"="false"})

      /subsystem=messaging-activemq/server=default/jms-queue=ExpiryQueue:add(entries=["java:/jms/queue/ExpiryQueue"])
      /subsystem=messaging-activemq/server=default/jms-queue=DLQ:add(entries=["java:/jms/queue/DLQ"])

      /subsystem=messaging-activemq/server=default/connection-factory=InVmConnectionFactory:add(connectors=["in-vm"], entries=["java:/ConnectionFactory"])
      /subsystem=messaging-activemq/server=default/connection-factory=RemoteConnectionFactory:add(connectors=["http-connector"], entries=["java:jboss/exported/jms/RemoteConnectionFactory"], reconnect-attempts=-1)

      /subsystem=messaging-activemq/server=default/security-setting=#:add()
      /subsystem=messaging-activemq/server=default/security-setting=#/role=guest:add(delete-non-durable-queue=true, create-non-durable-queue=true, consume=true, send=true)

      /subsystem=messaging-activemq/server=default/address-setting=#:add(dead-letter-address=jms.queue.DLQ, expiry-address=jms.queue.ExpiryQueue, max-size-bytes=10485760L, page-size-bytes=2097152, message-counter-history-day-limit=10, redistribution-delay=1000L)
      /subsystem=messaging-activemq/server=default/pooled-connection-factory=activemq-ra:add(transaction=xa, connectors=["in-vm"], entries=["java:/JmsXA java:jboss/DefaultJMSConnectionFactory"])

    run-batch
EOF
  cli_operations="${cli_operations}${tmp_operations}"

  if [ "${has_security_subsystem}" -ne 0 ]; then
    cli_operations="${cli_operations}
      /subsystem=messaging-activemq/server=default:write-attribute(name=elytron-domain, value=ApplicationDomain)"
  fi

  echo "${cli_operations}"
}

can_add_embedded(){
  local has_security_subsystem
  local xpath="\"//*[local-name()='subsystem' and starts-with(namespace-uri(), 'urn:jboss:domain:security:')]\""
  testXpathExpression "${xpath}" "has_security_subsystem"

  local has_elytron_subsystem
  local xpath="\"//*[local-name()='subsystem' and starts-with(namespace-uri(), 'urn:wildfly:elytron:')]\""
  testXpathExpression "${xpath}" "has_elytron_subsystem"

  if [ "${has_security_subsystem}" -ne 0 ]; then
    if [ "${has_elytron_subsystem}" -ne 0 ]; then
      # Just ignore
      return 1
    fi
  fi

  local has_remoting_subsystem
  local xpath="\"//*[local-name()='subsystem' and starts-with(namespace-uri(), 'urn:jboss:domain:remoting:')]\""
  testXpathExpression "${xpath}" "has_remoting_subsystem"

  if [ "${has_remoting_subsystem}" -ne 0 ]; then
      # Just ignore
      return 1
  fi

  local has_messaging_subsystem
  local xpath="\"//*[local-name()='subsystem' and starts-with(namespace-uri(), 'urn:jboss:domain:messaging-activemq:')]\""
  testXpathExpression "${xpath}" "has_messaging_subsystem"

  if [ "${has_messaging_subsystem}" -ne 0 ]; then
      # Just ignore
      return 1
  fi

  return 0
}