export BATS_TEST_SKIPPED=

# fake JBOSS_HOME
export JBOSS_HOME=$BATS_TMPDIR/jboss_home
rm -rf $JBOSS_HOME 2>/dev/null
mkdir -p $JBOSS_HOME/bin/launch

# copy scripts we are going to use
cp $BATS_TEST_DIRNAME/../../../launch-config/config/added/launch/openshift-common.sh $JBOSS_HOME/bin/launch
cp $BATS_TEST_DIRNAME/../../../launch-config/os/added/launch/launch-common.sh $JBOSS_HOME/bin/launch
cp $BATS_TEST_DIRNAME/../../../../../../test-common/logging.sh $JBOSS_HOME/bin/launch
cp $BATS_TEST_DIRNAME/../added/launch/messaging.sh $JBOSS_HOME/bin/launch
cp $BATS_TEST_DIRNAME/../added/launch/activemq-subsystem.xml $JBOSS_HOME/bin/launch
mkdir -p $JBOSS_HOME/standalone/configuration

# Set up the environment variables and load dependencies
WILDFLY_SERVER_CONFIGURATION=standalone-openshift.xml

# source the scripts needed
source $JBOSS_HOME/bin/launch/logging.sh
source $JBOSS_HOME/bin/launch/openshift-common.sh
source $JBOSS_HOME/bin/launch/messaging.sh


INPUT_CONTENT="<test-content><!-- ##MESSAGING_SUBSYSTEM_CONFIG## --><!-- ##MESSAGING_PORTS## --></test-content>"
DEFAULT_JMS_FACTORY_INPUT_CONTENT="<test-content>jms-connection-factory=\"##DEFAULT_JMS##\"<!-- ##MESSAGING_SUBSYSTEM_CONFIG## --><!-- ##MESSAGING_PORTS## --></test-content>"
DEFAULT_JMS_FACTORY_OUTPUT_CONTENT="<test-content>jms-connection-factory=\"java:jboss/DefaultJMSConnectionFactory\"<!-- ##MESSAGING_SUBSYSTEM_CONFIG## --><!-- ##MESSAGING_PORTS## --></test-content>"
SOCKET_BINDING_ONLY_INPUT_CONTENT="<test-content><!-- ##MESSAGING_PORTS## --></test-content>"
SOCKET_BINDING_ONLY_OUTPUT_CONTENT='<test-content><socket-binding name="messaging" port="5445"/><socket-binding name="messaging-throughput" port="5455"/></test-content>'


setup() {
  cp $BATS_TEST_DIRNAME/../../../../../../test-common/configuration/standalone-openshift.xml $JBOSS_HOME/standalone/configuration
}

teardown() {
  if [ -n "${CONFIG_FILE}" ] && [ -f "${CONFIG_FILE}" ]; then
    rm "${CONFIG_FILE}"
  fi
}

@test "Configure MQ config file with markers" {
    expected=$(cat $BATS_TEST_DIRNAME/standalone-openshift-configure-mq.xml | xmllint --format --noblanks -)
    echo "CONFIG_FILE: ${CONFIG_FILE}"
    echo "${INPUT_CONTENT}" > ${CONFIG_FILE}
    export MQ_CLUSTER_PASSWORD="somemqpassword"
    export MQ_QUEUES="queue1,queue2"
    export MQ_TOPICS="topic1,topic2"
    ACTIVEMQ_SUBSYSTEM_FILE=$JBOSS_HOME/bin/launch/activemq-subsystem.xml
    run configure_mq
    echo "Output: ${output}"
    result=$(cat ${CONFIG_FILE} | xmllint --format --noblanks -)
    echo "Result: ${result}"
    echo "Expected: ${expected}"
    [ "${result}" = "${expected}" ]

    echo "${lines[0]}" | grep "WARN Configuration of an embedded messaging broker"
    [ $? -eq 0 ]

    echo "${lines[1]}" | grep "INFO If you are not configuring messaging destinations"
    [ $? -eq 0 ]
}

@test "Configure MQ config file without markers" {
    expected=$(echo "<test-content/>" | xmllint --format --noblanks -)
    echo "CONFIG_FILE: ${CONFIG_FILE}"
    echo '<test-content/>' > ${CONFIG_FILE}
    export MQ_CLUSTER_PASSWORD="somemqpassword"
    export MQ_QUEUES="queue1,queue2"
    export MQ_TOPICS="topic1,topic2"
    run configure_mq
    echo "Output: ${output}"
    [ "${output}" = "" ]
    result=$(cat ${CONFIG_FILE} | xmllint --format --noblanks -)
    echo "Result: ${result}"
    echo "Expected: ${expected}"
    [ "${result}" = "${expected}" ]
}

@test "Configure MQ config file with markers, destinations and disabled" {
    expected=$(cat $BATS_TEST_DIRNAME/standalone-openshift-configure-mq.xml | xmllint --format --noblanks -)
    echo "CONFIG_FILE: ${CONFIG_FILE}"
    echo "${INPUT_CONTENT}" > ${CONFIG_FILE}
    export MQ_CLUSTER_PASSWORD="somemqpassword"
    export MQ_QUEUES="queue1,queue2"
    export MQ_TOPICS="topic1,topic2"
    export DISABLE_EMBEDDED_JMS_BROKER="true"
    run configure_mq
    echo "Output: ${output}"
    result=$(cat ${CONFIG_FILE} | xmllint --format --noblanks -)
    echo "Result: ${result}"
    echo "Expected: ${expected}"
    [ "${result}" = "${expected}" ]

    echo "${lines[0]}" | grep "WARN Configuration of an embedded messaging broker"
    [ $? -eq 0 ]

    [ "${lines[1]}" = "" ]
}

@test "Configure MQ config file with markers embedded disabled" {
    expected=$(echo "${INPUT_CONTENT}" | xmllint --format --noblanks -)
    echo "CONFIG_FILE: ${CONFIG_FILE}"
    echo "${INPUT_CONTENT}" > ${CONFIG_FILE}
    export MQ_CLUSTER_PASSWORD="somemqpassword"
    export DISABLE_EMBEDDED_JMS_BROKER="true"
    run configure_mq
    echo "Output: ${output}"
    [ "${output}" = "" ]
    result=$(cat ${CONFIG_FILE} | xmllint --format --noblanks -)
    echo "Result: ${result}"
    echo "Expected: ${expected}"
    [ "${result}" = "${expected}" ]
}

@test "Configure MQ config file with socket-binding marker only" {
    expected=$(echo "${SOCKET_BINDING_ONLY_OUTPUT_CONTENT}" | xmllint --format --noblanks -)
    echo "CONFIG_FILE: ${CONFIG_FILE}"
    echo "${SOCKET_BINDING_ONLY_INPUT_CONTENT}" > ${CONFIG_FILE}
    export MQ_CLUSTER_PASSWORD="somemqpassword"
    run configure_mq
    echo "Output: ${output}"
    [ "${output}" = "" ]
    result=$(cat ${CONFIG_FILE} | xmllint --format --noblanks -)
    echo "Result: ${result}"
    echo "Expected: ${expected}"
    [ "${result}" = "${expected}" ]
}

@test "Configure MQ config file with socket-binding marker only and destinations" {
    expected=$(echo "${SOCKET_BINDING_ONLY_OUTPUT_CONTENT}" | xmllint --format --noblanks -)
    echo "CONFIG_FILE: ${CONFIG_FILE}"
    echo "${SOCKET_BINDING_ONLY_INPUT_CONTENT}" > ${CONFIG_FILE}
    export MQ_CLUSTER_PASSWORD="somemqpassword"
    export MQ_QUEUES="queue1,queue2"
    export MQ_TOPICS="topic1,topic2"
    run configure_mq
    echo "Output: ${output}"
    [ "${output}" = "" ]
    result=$(cat ${CONFIG_FILE} | xmllint --format --noblanks -)
    echo "Result: ${result}"
    echo "Expected: ${expected}"
    [ "${result}" = "${expected}" ]
}

@test "Configure MQ config file with socket-binding marker only, destinations and disabled" {
    expected=$(echo "${SOCKET_BINDING_ONLY_OUTPUT_CONTENT}"  | xmllint --format --noblanks -)
    echo "CONFIG_FILE: ${CONFIG_FILE}"
    echo "${SOCKET_BINDING_ONLY_INPUT_CONTENT}" > ${CONFIG_FILE}
    export MQ_CLUSTER_PASSWORD="somemqpassword"
    export MQ_QUEUES="queue1,queue2"
    export MQ_TOPICS="topic1,topic2"
    export DISABLE_EMBEDDED_JMS_BROKER="true"
    run configure_mq
    echo "Output: ${output}"
    [ "${output}" = "" ]
    result=$(cat ${CONFIG_FILE} | xmllint --format --noblanks -)
    echo "Result: ${result}"
    echo "Expected: ${expected}"
    [ "${result}" = "${expected}" ]
}

@test "Configure MQ config file with socket-binding marker only embedded disabled" {
    expected=$(echo "${SOCKET_BINDING_ONLY_INPUT_CONTENT}" | xmllint --format --noblanks -)
    echo "CONFIG_FILE: ${CONFIG_FILE}"
    echo "${SOCKET_BINDING_ONLY_INPUT_CONTENT}" > ${CONFIG_FILE}
    export MQ_CLUSTER_PASSWORD="somemqpassword"
    export DISABLE_EMBEDDED_JMS_BROKER="true"
    run configure_mq
    echo "Output: ${output}"
    [ "${output}" = "" ]
    result=$(cat ${CONFIG_FILE} | xmllint --format --noblanks -)
    echo "Result: ${result}"
    echo "Expected: ${expected}"
    [ "${result}" = "${expected}" ]
}

@test "Configure MQ config file with markers embedded disabled and default JMSFactory to be removed" {
    expected=$(echo "${INPUT_CONTENT}" | xmllint --format --noblanks -)
    echo "CONFIG_FILE: ${CONFIG_FILE}"
    echo "${DEFAULT_JMS_FACTORY_INPUT_CONTENT}" > ${CONFIG_FILE}
    export MQ_CLUSTER_PASSWORD="somemqpassword"
    export DISABLE_EMBEDDED_JMS_BROKER="true"
    run inject_brokers
    echo "Output: ${output}"
    [ "${output}" = "" ]
    result=$(cat ${CONFIG_FILE} | xmllint --format --noblanks -)
    echo "Result: ${result}"
    echo "Expected: ${expected}"
    [ "${result}" = "${expected}" ]
}

@test "Configure MQ config file with markers embedded disabled, some destinations and default JMSFactory" {
    expected=$(echo "${DEFAULT_JMS_FACTORY_OUTPUT_CONTENT}" | xmllint --format --noblanks -)
    echo "CONFIG_FILE: ${CONFIG_FILE}"
    echo "${DEFAULT_JMS_FACTORY_INPUT_CONTENT}" > ${CONFIG_FILE}
    export MQ_CLUSTER_PASSWORD="somemqpassword"
    export MQ_QUEUES="queue1,queue2"
    export MQ_TOPICS="topic1,topic2"
    export DISABLE_EMBEDDED_JMS_BROKER="true"
    run inject_brokers
    echo "Output: ${output}"
    [ "${output}" = "" ]
    result=$(cat ${CONFIG_FILE} | xmllint --format --noblanks -)
    echo "Result: ${result}"
    echo "Expected: ${expected}"
    [ "${result}" = "${expected}" ]
}


## test based on CLI operations
normalize_spaces_new_lines() {
  echo "output=${output}<<"
  echo "expected=${expected}<<"
  output=$(printf '%s\n' "$output" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e '/^$/d')
  expected=$(printf '%s\n' "$expected" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e '/^$/d')

  #echo "output=${output}<<"
  #echo "expected=${expected}<<"
}

@test "Configure via CLI two legacy brokers " {
  expected=$(cat <<EOF
    if (outcome != success) of /subsystem=resource-adapters:read-resource
      echo You have set MQ_SERVICE_PREFIX_MAPPING environment variable to configure the service name 'messaging_bats_test-amq' under 'MQ' prefix. Fix your configuration to contain resource adapters subsystem for this to happen. >> \${error_file}
      exit
    end-if

    /subsystem=resource-adapters/resource-adapter=activemq-rar.rar:add(archive=activemq-rar.rar, transaction-support=XATransaction)
    /subsystem=resource-adapters/resource-adapter=activemq-rar.rar/config-properties=UserName:add(value="mq_username")
    /subsystem=resource-adapters/resource-adapter=activemq-rar.rar/config-properties=Password:add(value="mq_password")
    /subsystem=resource-adapters/resource-adapter=activemq-rar.rar/config-properties=ServerUrl:add(value="tcp://host:9999?jms.rmIdFromConnectionId=true")
    /subsystem=resource-adapters/resource-adapter=activemq-rar.rar/connection-definitions="messaging_bats_test-amq-ConnectionFactory":add(tracking="true", class-name=org.apache.activemq.ra.ActiveMQManagedConnectionFactory, jndi-name="mq_jndi", enabled=true, min-pool-size=1, max-pool-size=20, pool-prefill=false, same-rm-override=false, recovery-username="mq_username", recovery-password="mq_password")

    /subsystem=resource-adapters/resource-adapter="activemq-rar.rar"/admin-objects="queue/queue1":add(class-name="org.apache.activemq.command.ActiveMQQueue", jndi-name="java:/queue/queue1", use-java-context=true)
    /subsystem=resource-adapters/resource-adapter="activemq-rar.rar"/admin-objects="queue/queue1"/config-properties=PhysicalName:add(value="queue/queue1")
    /subsystem=resource-adapters/resource-adapter="activemq-rar.rar"/admin-objects="queue/queue2":add(class-name="org.apache.activemq.command.ActiveMQQueue", jndi-name="java:/queue/queue2", use-java-context=true)
    /subsystem=resource-adapters/resource-adapter="activemq-rar.rar"/admin-objects="queue/queue2"/config-properties=PhysicalName:add(value="queue/queue2")
    /subsystem=resource-adapters/resource-adapter="activemq-rar.rar"/admin-objects="topic/topic1":add(class-name="org.apache.activemq.command.ActiveMQTopic", jndi-name="java:/topic/topic1", use-java-context=true)
    /subsystem=resource-adapters/resource-adapter="activemq-rar.rar"/admin-objects="topic/topic1"/config-properties=PhysicalName:add(value="topic/topic1")
    /subsystem=resource-adapters/resource-adapter="activemq-rar.rar"/admin-objects="topic/topic2":add(class-name="org.apache.activemq.command.ActiveMQTopic", jndi-name="java:/topic/topic2", use-java-context=true)
    /subsystem=resource-adapters/resource-adapter="activemq-rar.rar"/admin-objects="topic/topic2"/config-properties=PhysicalName:add(value="topic/topic2")

    if (outcome != success) of /subsystem=resource-adapters:read-resource
      echo You have set MQ_SERVICE_PREFIX_MAPPING environment variable to configure the service name 'messaging_bats_test_two-amq' under 'MQT' prefix. Fix your configuration to contain resource adapters subsystem for this to happen. >> \${error_file}
      exit
    end-if

    /subsystem=resource-adapters/resource-adapter=activemq-rar.rar-1:add(archive=activemq-rar.rar, transaction-support=XATransaction)
    /subsystem=resource-adapters/resource-adapter=activemq-rar.rar-1/config-properties=UserName:add(value="mq_username")
    /subsystem=resource-adapters/resource-adapter=activemq-rar.rar-1/config-properties=Password:add(value="mq_password")
    /subsystem=resource-adapters/resource-adapter=activemq-rar.rar-1/config-properties=ServerUrl:add(value="tcp://host:9999?jms.rmIdFromConnectionId=true")
    /subsystem=resource-adapters/resource-adapter=activemq-rar.rar-1/connection-definitions="messaging_bats_test_two-amq-ConnectionFactory":add(class-name=org.apache.activemq.ra.ActiveMQManagedConnectionFactory, jndi-name="mq_jndi", enabled=true, min-pool-size=1, max-pool-size=20, pool-prefill=false, same-rm-override=false, recovery-username="mq_username", recovery-password="mq_password")

    /subsystem=resource-adapters/resource-adapter="activemq-rar.rar-1"/admin-objects="queue/queue1":add(class-name="org.apache.activemq.command.ActiveMQQueue", jndi-name="java:/queue/queue1", use-java-context=true)
    /subsystem=resource-adapters/resource-adapter="activemq-rar.rar-1"/admin-objects="queue/queue1"/config-properties=PhysicalName:add(value="queue/queue1")
    /subsystem=resource-adapters/resource-adapter="activemq-rar.rar-1"/admin-objects="queue/queue2":add(class-name="org.apache.activemq.command.ActiveMQQueue", jndi-name="java:/queue/queue2", use-java-context=true)
    /subsystem=resource-adapters/resource-adapter="activemq-rar.rar-1"/admin-objects="queue/queue2"/config-properties=PhysicalName:add(value="queue/queue2")
    /subsystem=resource-adapters/resource-adapter="activemq-rar.rar-1"/admin-objects="topic/topic1":add(class-name="org.apache.activemq.command.ActiveMQTopic", jndi-name="java:/topic/topic1", use-java-context=true)
    /subsystem=resource-adapters/resource-adapter="activemq-rar.rar-1"/admin-objects="topic/topic1"/config-properties=PhysicalName:add(value="topic/topic1")
    /subsystem=resource-adapters/resource-adapter="activemq-rar.rar-1"/admin-objects="topic/topic2":add(class-name="org.apache.activemq.command.ActiveMQTopic", jndi-name="java:/topic/topic2", use-java-context=true)
    /subsystem=resource-adapters/resource-adapter="activemq-rar.rar-1"/admin-objects="topic/topic2"/config-properties=PhysicalName:add(value="topic/topic2")
EOF
)
  CONFIG_ADJUSTMENT_MODE="cli"

  MQ_SERVICE_PREFIX_MAPPING="messaging_bats_test-amq=MQ,messaging_bats_test_two-amq=MQT"

  MESSAGING_BATS_TEST_AMQ_TCP_SERVICE_HOST="host"
  MESSAGING_BATS_TEST_AMQ_TCP_SERVICE_PORT=9999
  MQ_JNDI="mq_jndi"
  MQ_USERNAME="mq_username"
  MQ_PASSWORD="mq_password"
  MQ_QUEUES="queue1,queue2"
  MQ_TOPICS="topic1,topic2"
  MQ_TRACKING="true"

  MESSAGING_BATS_TEST_TWO_AMQ_TCP_SERVICE_HOST="host"
  MESSAGING_BATS_TEST_TWO_AMQ_TCP_SERVICE_PORT=9999
  MQT_JNDI="mq_jndi"
  MQT_USERNAME="mq_username"
  MQT_PASSWORD="mq_password"
  MQT_QUEUES="queue1,queue2"
  MQT_TOPICS="topic1,topic2"

  run inject_brokers
  echo "CONSOLE: ${output}"
  output=$(cat "${CLI_SCRIPT_FILE}")
  normalize_spaces_new_lines
  [ "${output}" = "${expected}" ]
}