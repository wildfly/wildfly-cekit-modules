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

function configure_mq_destinations() {
  IFS=',' read -a queues <<< ${MQ_QUEUES:-$HORNETQ_QUEUES}
  IFS=',' read -a topics <<< ${MQ_TOPICS:-$HORNETQ_TOPICS}

  destinations=""
  if [ "${#queues[@]}" -ne "0" -o "${#topics[@]}" -ne "0" ]; then
    if [ "${#queues[@]}" -ne "0" ]; then
      for queue in ${queues[@]}; do
        destinations="${destinations}<jms-queue name=\"${queue}\" entries=\"/queue/${queue}\"/>"
      done
    fi
    if [ "${#topics[@]}" -ne "0" ]; then
      for topic in ${topics[@]}; do
        destinations="${destinations}<jms-topic name=\"${topic}\" entries=\"/topic/${topic}\"/>"
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

function configure_mq() {
  if [ "$REMOTE_AMQ_BROKER" != "true" ] ; then
    configure_mq_cluster_password

    destinations=$(configure_mq_destinations)

    # We need the broker if they configured destinations or didn't explicitly disable the broker AND there's a point to doing it because the marker exists
    if ([ -n "${destinations}" ] || [ "x${DISABLE_EMBEDDED_JMS_BROKER}" != "xtrue" ]) && grep -q '<!-- ##MESSAGING_SUBSYSTEM_CONFIG## -->' ${CONFIG_FILE}; then

      log_warning "Configuration of an embedded messaging broker within the appserver is enabled but is not recommended. Support for such a configuration will be removed in a future release."
      if [ "x${DISABLE_EMBEDDED_JMS_BROKER}" != "xtrue" ]; then
        log_info "If you are not configuring messaging destinations, to disable configuring an embedded messaging broker set the DISABLE_EMBEDDED_JMS_BROKER environment variable to true."
      fi

      activemq_subsystem=$(sed -e "s|<!-- ##DESTINATIONS## -->|${destinations}|" <"${ACTIVEMQ_SUBSYSTEM_FILE}" | sed ':a;N;$!ba;s|\n|\\n|g')

      sed -i "s|<!-- ##MESSAGING_SUBSYSTEM_CONFIG## -->|${activemq_subsystem%$'\n'}|" "${CONFIG_FILE}"
    fi

    #Handle the messaging socket-binding separately just in case its marker is present but the subsystem one is not
    if ([ -n "${destinations}" ] || [ "x${DISABLE_EMBEDDED_JMS_BROKER}" != "xtrue" ]) && grep -q '<!-- ##MESSAGING_PORTS## -->' ${CONFIG_FILE}; then
      # We don't warn about this as socket-bindings are pretty harmless
      sed -i 's|<!-- ##MESSAGING_PORTS## -->|<socket-binding name="messaging" port="5445"/><socket-binding name="messaging-throughput" port="5455"/>|' "${CONFIG_FILE}"
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

# $1 - factory name - activemq-ra-remote
# $2 - username
# $3 - password
# $4 - default connection factory - java:jboss/DefaultJMSConnectionFactory
# <!-- ##AMQ_POOLED_CONNECTION_FACTORY## -->
function generate_remote_artemis_connection_factory() {
    echo "<pooled-connection-factory user=\"${2}\" password=\"${3}\" name=\"${1}\" entries=\"java:/JmsXA java:/RemoteJmsXA java:jboss/RemoteJmsXA ${4}\" connectors=\"netty-remote-throughput\" transaction=\"xa\"/>" | sed -e ':a;N;$!ba;s|\n|\\n|g'
}

# $1 object type - queue / topic
# $2 object name - MyQueue / MyTopic
# <!-- ##AMQ7_CONFIG_PROPERTIES## -->
function generate_remote_artemis_property() {
    echo "<property name=\"${1}.${2}\" value=\"${2}\"/>" | sed -e ':a;N;$!ba;s|\n|\\n|g'
}

# $1 - remote context - remoteContext
# $2 - object name - MyQueue / MyTopic etc
# <!-- ##AMQ_LOOKUP_OBJECTS## -->
function generate_remote_artemis_lookup() {
    echo "<lookup name=\"java:/${2}\" lookup=\"java:global/${1}/${2}\"/>" | sed -e ':a;N;$!ba;s|\n|\\n|g'
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
# <!-- ##AMQ_MESSAGING_SOCKET_BINDING## -->
function generate_remote_artemis_socket_binding_cli() {
    :
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
  log_info "generating CLI object config for $1"

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

      /subsystem=resource-adapters/resource-adapter=${ra_id}:add(archive=$9, transaction-support=XATransaction)
      /subsystem=resource-adapters/resource-adapter=${ra_id}/config-properties=UserName:add(value="${3}")
      /subsystem=resource-adapters/resource-adapter=${ra_id}/config-properties=Password:add(value="${4}")
      /subsystem=resource-adapters/resource-adapter=${ra_id}/config-properties=ServerUrl:add(value="tcp://${6}:${7}?jms.rmIdFromConnectionId=true")
      /subsystem=resource-adapters/resource-adapter=${ra_id}/connection-definitions="${1}-ConnectionFactory":add(${ra_tracking}\
class-name=org.apache.activemq.ra.ActiveMQManagedConnectionFactory, jndi-name="${2}", enabled=true, min-pool-size=1, max-pool-size=20, \
pool-prefill=false, same-rm-override=false, recovery-username="${3}", recovery-password="${4}")
EOF
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

      # remap for AMQ7 config vars, AMQ7 gets looked up as AMQ
      local host_var="${service}_${protocol_env}_SERVICE_HOST"
      local port_var="${service}_${protocol_env}_SERVICE_PORT"
      if [ "$type" = "AMQ7" ] ; then
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

      # TODO: validate MQ_USERNAME="mq_username" and  MQ_PASSWORD="mq_password" ????

      case "$type" in
        "AMQ")
          # This is the legacy AMQ configuration. In this case we only configure the resource adapters subsystem adding activemq-rar.rar
          driver="amq"

          # the name of the archive is fixed, so, it looks like we can only configure one AMQ broker
          archive="activemq-rar.rar"

          if [ "${resource_adapters_mode}" = "xml" ]; then
            ra=$(generate_resource_adapter ${service_name} ${jndi} ${username} ${password} ${protocol} ${host} ${port} ${prefix} ${archive} ${driver} "${queues}" "${topics}" "${tracking}" ${counter})
            sed -i "s|<!-- ##RESOURCE_ADAPTERS## -->|${ra%$'\n'}<!-- ##RESOURCE_ADAPTERS## -->|" $CONFIG_FILE
          elif [ "${resource_adapters_mode}" = "cli" ]; then
            ra=$(generate_resource_adapter_cli ${service_name} ${jndi} ${username} ${password} ${protocol} ${host} ${port} ${prefix} ${archive} ${driver} "${queues}" "${topics}" "${tracking}" ${counter})
            echo "${ra}" >> "${CLI_SCRIPT_FILE}"
          fi

          REMOTE_AMQ_BROKER=true
          REMOTE_AMQ6=true
          ;;
        "AMQ7")
         driver="amq7"
         archive=""
         REMOTE_AMQ_BROKER=true
         REMOTE_AMQ7=true

         if [ "$subsystem_added" != "true" ] ; then
             activemq_subsystem=$(sed -e ':a;N;$!ba;s|\n|\\n|g' <"${ACTIVEMQ_SUBSYSTEM_FILE}")
             sed -i "s|<!-- ##MESSAGING_SUBSYSTEM_CONFIG## -->|${activemq_subsystem%$'\n'}<!-- ##MESSAGING_SUBSYSTEM_CONFIG## -->|" $CONFIG_FILE
             subsystem_added=true
             # make sure the default connection factory isn't set on another cnx factory
             sed -i "s|java:jboss/DefaultJMSConnectionFactory||g" $CONFIG_FILE
             # this will be on the remote ConnectionFactory, so rename the local one until the embedded broker is dropped.
             sed -i "s|java:/JmsXA|java:/JmsXALocal|" $CONFIG_FILE
         fi

         # this should be configurable - see CLOUD-2225 for multi broker support
         socket_binding_name="messaging-remote-throughput"
         connector=$(generate_remote_artemis_remote_connector ${socket_binding_name})
         sed -i "s|<!-- ##AMQ_REMOTE_CONNECTOR## -->|${connector%$'\n'}<!-- ##AMQ_REMOTE_CONNECTOR## -->|" $CONFIG_FILE


        if [ "${amq_messaging_socket_binding_mode}" = "xml" ]; then
          :
        elif [ "${amq_messaging_socket_binding_mode}" = "cli" ]; then
          :
        fi

         socket_binding=$(generate_remote_artemis_socket_binding ${socket_binding_name} ${host} ${port})
         sed -i "s|<!-- ##AMQ_MESSAGING_SOCKET_BINDING## -->|${socket_binding%$'\n'}<!-- ##AMQ_MESSAGING_SOCKET_BINDING## -->|" $CONFIG_FILE

         # Naming subsystem
         if [ "${amg_remote_context}" = "xml" ]; then
          :
        elif [ "${amg_remote_context}" = "cli" ]; then
          :
        fi

         naming=$(generate_remote_artemis_naming "remoteContext" ${host} ${port})
         sed -i "s|<!-- ##AMQ_REMOTE_CONTEXT## -->|${naming%$'\n'}<!-- ##AMQ_REMOTE_CONTEXT## -->|" $CONFIG_FILE

         # this name should also be configurable (CLOUD-2225)
         cnx_factory_name="activemq-ra-remote"
         EJB_RESOURCE_ADAPTER_NAME=${cnx_factory_name}.rar

         cnx_factory=$(generate_remote_artemis_connection_factory ${cnx_factory_name} ${username} ${password} ${jndi})
         sed -i "s|<!-- ##AMQ_POOLED_CONNECTION_FACTORY## -->|${cnx_factory%$'\n'}<!-- ##AMQ_POOLED_CONNECTION_FACTORY## -->|" $CONFIG_FILE

         IFS=',' read -a amq7_queues <<< ${queues:-}
         if [ "${#amq7_queues[@]}" -ne "0" ]; then
            for q in ${amq7_queues[@]}; do
                prop=$(generate_remote_artemis_property "queue" ${q})
                sed -i "s|<!-- ##AMQ7_CONFIG_PROPERTIES## -->|${prop%$'\n'}<!-- ##AMQ7_CONFIG_PROPERTIES## -->|" $CONFIG_FILE

                lookup=$(generate_remote_artemis_lookup "remoteContext" ${q})
                sed -i "s|<!-- ##AMQ_LOOKUP_OBJECTS## -->|${lookup%$'\n'}<!-- ##AMQ_LOOKUP_OBJECTS## -->|" $CONFIG_FILE
            done
         fi

         IFS=',' read -a amq7_topics <<< ${topics:-}
         if [ "${#amq7_topics[@]}" -ne "0" ]; then
            for t in ${amq7_topics[@]}; do
                prop=$(generate_remote_artemis_property "topic" ${t})
                sed -i "s|<!-- ##AMQ7_CONFIG_PROPERTIES## -->|${prop%$'\n'}<!-- ##AMQ7_CONFIG_PROPERTIES## -->|" $CONFIG_FILE

                lookup=$(generate_remote_artemis_lookup "remoteContext" ${t})
                sed -i "s|<!-- ##AMQ_LOOKUP_OBJECTS## -->|${lookup%$'\n'}<!-- ##AMQ_LOOKUP_OBJECTS## -->|" $CONFIG_FILE
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

  if [ "$REMOTE_AMQ_BROKER" = "true" ] || [ -n "${MQ_QUEUES}" ] || [ -n "${HORNETQ_QUEUES}" ] || [ -n "${MQ_TOPICS}" ] || [ -n "${HORNETQ_TOPICS}" ] || [ "x${DISABLE_EMBEDDED_JMS_BROKER}" != "xtrue" ]
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

}

disable_unused_rar() {
  # Put down a skipdeploy marker for the legacy activemq-rar.rar unless there is a .dodeploy marker
  # or the rar is mentioned in the config file
  local base_rar="$JBOSS_HOME/standalone/deployments/activemq-rar.rar"
  if [ -e "${base_rar}" ] && [ ! -e "${base_rar}.dodeploy" ] && ! grep -q -E "activemq-rar\.rar" $CONFIG_FILE; then
    touch "$JBOSS_HOME/standalone/deployments/activemq-rar.rar.skipdeploy"
  fi
}