#!/usr/bin/env bats

source $BATS_TEST_DIRNAME/../../../../../../test-common/cli_utils.sh

export BATS_TEST_SKIPPED=

# fake JBOSS_HOME
export JBOSS_HOME=$BATS_TMPDIR/jboss_home
rm -rf $JBOSS_HOME
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

@test "Configure Embedded server broker -- with markers" {
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

    local warn_lines=()
    while IFS= read -r line
    do
      echo "LINE=${line}"
      warn_lines+=("${line}")
    done < "${CONFIG_WARNING_FILE}"

    echo "${warn_lines[0]}" | grep "Configuration of an embedded messaging broker"
    [ $? -eq 0 ]

    echo "${warn_lines[1]}" | grep "If you are not configuring messaging destinations"
    [ $? -eq 0 ]
}

@test "Configure Embedded server broker -- without markers" {
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

@test "Configure Embedded server broker -- with markers, destinations and disabled" {
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

    local warn_lines=()
    while IFS= read -r line
    do
      echo "LINE=${line}"
      warn_lines+=("${line}")
    done < "${CONFIG_WARNING_FILE}"

    echo "${warn_lines[0]}" | grep "Configuration of an embedded messaging broker"
    [ $? -eq 0 ]

    [ "${warn_lines[1]}" = "" ]
}

@test "Configure Embedded server broker -- with markers embedded disabled" {
    INCLUDE_REQUIRED_SUBSYSTEM="<subsystem xmlns='urn:jboss:domain:ee:4.0'></subsystem><subsystem xmlns='urn:wildfly:elytron:4.0'></subsystem><subsystem xmlns='urn:jboss:domain:remoting:4.0'></subsystem><subsystem xmlns='urn:jboss:domain:messaging-activemq:4.0'></subsystem>"
    expected=$(echo "<root>${INPUT_CONTENT}${INCLUDE_REQUIRED_SUBSYSTEM}</root>" | xmllint --format --noblanks -)
    echo "CONFIG_FILE: ${CONFIG_FILE}"
    echo "<root>${INPUT_CONTENT}${INCLUDE_REQUIRED_SUBSYSTEM}</root>" > ${CONFIG_FILE}
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

@test "Configure Embedded server broker -- with socket-binding marker only" {
    INCLUDE_REQUIRED_SUBSYSTEM="<subsystem xmlns='urn:jboss:domain:ee:4.0'></subsystem><subsystem xmlns='urn:wildfly:elytron:4.0'></subsystem><subsystem xmlns='urn:jboss:domain:remoting:4.0'></subsystem><subsystem xmlns='urn:jboss:domain:messaging-activemq:4.0'></subsystem>"
    expected=$(echo "<root>${SOCKET_BINDING_ONLY_OUTPUT_CONTENT}${INCLUDE_REQUIRED_SUBSYSTEM}</root>" | xmllint --format --noblanks -)
    echo "CONFIG_FILE: ${CONFIG_FILE}"
    echo "<root>${SOCKET_BINDING_ONLY_INPUT_CONTENT}${INCLUDE_REQUIRED_SUBSYSTEM}</root>" > ${CONFIG_FILE}

    export MQ_CLUSTER_PASSWORD="somemqpassword"
    run configure_mq
    echo "Output: ${output}"
    [ "${output}" = "" ]
    result=$(cat ${CONFIG_FILE} | xmllint --format --noblanks -)
    echo "Result: ${result}"
    echo "Expected: ${expected}"
    [ "${result}" = "${expected}" ]
}

@test "Configure Embedded server broker -- with socket-binding marker only and destinations" {
    INCLUDE_REQUIRED_SUBSYSTEM="<subsystem xmlns='urn:jboss:domain:ee:4.0'></subsystem><subsystem xmlns='urn:wildfly:elytron:4.0'></subsystem><subsystem xmlns='urn:jboss:domain:remoting:4.0'></subsystem><subsystem xmlns='urn:jboss:domain:messaging-activemq:4.0'></subsystem>"
    expected=$(echo "<root>${SOCKET_BINDING_ONLY_OUTPUT_CONTENT}${INCLUDE_REQUIRED_SUBSYSTEM}</root>" | xmllint --format --noblanks -)
    echo "CONFIG_FILE: ${CONFIG_FILE}"
    echo "<root>${SOCKET_BINDING_ONLY_INPUT_CONTENT}${INCLUDE_REQUIRED_SUBSYSTEM}</root>" > ${CONFIG_FILE}

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

@test "Configure Embedded server broker -- with socket-binding marker only, destinations and disabled" {
    INCLUDE_REQUIRED_SUBSYSTEM="<subsystem xmlns='urn:jboss:domain:ee:4.0'></subsystem><subsystem xmlns='urn:wildfly:elytron:4.0'></subsystem><subsystem xmlns='urn:jboss:domain:remoting:4.0'></subsystem><subsystem xmlns='urn:jboss:domain:messaging-activemq:4.0'></subsystem>"
    expected=$(echo "<root>${SOCKET_BINDING_ONLY_OUTPUT_CONTENT}${INCLUDE_REQUIRED_SUBSYSTEM}</root>" | xmllint --format --noblanks -)
    echo "CONFIG_FILE: ${CONFIG_FILE}"
    echo "<root>${SOCKET_BINDING_ONLY_INPUT_CONTENT}${INCLUDE_REQUIRED_SUBSYSTEM}</root>" > ${CONFIG_FILE}

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

@test "Configure Embedded server broker -- with socket-binding marker only embedded disabled" {
    INCLUDE_REQUIRED_SUBSYSTEM="<subsystem xmlns='urn:jboss:domain:ee:4.0'></subsystem><subsystem xmlns='urn:wildfly:elytron:4.0'></subsystem><subsystem xmlns='urn:jboss:domain:remoting:4.0'></subsystem><subsystem xmlns='urn:jboss:domain:messaging-activemq:4.0'></subsystem>"
    expected=$(echo "<root>${SOCKET_BINDING_ONLY_INPUT_CONTENT}${INCLUDE_REQUIRED_SUBSYSTEM}</root>" | xmllint --format --noblanks -)
    echo "CONFIG_FILE: ${CONFIG_FILE}"
    echo "<root>${SOCKET_BINDING_ONLY_INPUT_CONTENT}${INCLUDE_REQUIRED_SUBSYSTEM}</root>" > ${CONFIG_FILE}

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

@test "Configure Embedded server broker -- with markers embedded disabled and default JMSFactory to be removed" {
    INCLUDE_REQUIRED_SUBSYSTEM="<subsystem xmlns='urn:jboss:domain:ee:4.0'></subsystem><subsystem xmlns='urn:wildfly:elytron:4.0'></subsystem><subsystem xmlns='urn:jboss:domain:remoting:4.0'></subsystem><subsystem xmlns='urn:jboss:domain:messaging-activemq:4.0'></subsystem>"
    expected=$(echo "<root>${INPUT_CONTENT}${INCLUDE_REQUIRED_SUBSYSTEM}</root>" | xmllint --format --noblanks -)
    echo "CONFIG_FILE: ${CONFIG_FILE}"
    echo "<root>${DEFAULT_JMS_FACTORY_INPUT_CONTENT}${INCLUDE_REQUIRED_SUBSYSTEM}</root>" > ${CONFIG_FILE}

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

@test "Configure Embedded server broker -- with markers embedded disabled, some destinations and default JMSFactory" {
    INCLUDE_EE_SUBSYSTEM="<subsystem xmlns='urn:jboss:domain:ee:4.0'></subsystem>"
    expected=$(echo "<root>${DEFAULT_JMS_FACTORY_OUTPUT_CONTENT}${INCLUDE_EE_SUBSYSTEM}</root>" | xmllint --format --noblanks -)
    echo "CONFIG_FILE: ${CONFIG_FILE}"
    echo "<root>${DEFAULT_JMS_FACTORY_INPUT_CONTENT}${INCLUDE_EE_SUBSYSTEM}</root>" > ${CONFIG_FILE}
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

@test "Configure legacy external broker -- Two AMQ brokers via Markers" {
  CONFIG_ADJUSTMENT_MODE="xml"

  MQ_SERVICE_PREFIX_MAPPING="messaging_bats_test-amq=TEST_MQ,messaging_bats_test_two-amq=TEST_MQ_TWO"

  MESSAGING_BATS_TEST_AMQ_TCP_SERVICE_HOST="hostone"
  MESSAGING_BATS_TEST_AMQ_TCP_SERVICE_PORT=1999
  TEST_MQ_JNDI="mq_jndi_one"
  TEST_MQ_USERNAME="mq_username_one"
  TEST_MQ_PASSWORD="mq_password_one"
  TEST_MQ_QUEUES="queue1_one,queue2_one"
  TEST_MQ_TOPICS="topic1_one,topic2_one"
  TEST_MQ_TRACKING="true"

  MESSAGING_BATS_TEST_TWO_AMQ_TCP_SERVICE_HOST="hostonetwo"
  MESSAGING_BATS_TEST_TWO_AMQ_TCP_SERVICE_PORT=2999
  TEST_MQ_TWO_JNDI="mq_jndi_two"
  TEST_MQ_TWO_USERNAME="mq_username_two"
  TEST_MQ_TWO_PASSWORD="mq_password_two"
  TEST_MQ_TWO_QUEUES="queue1_two,queue2_two"
  TEST_MQ_TWO_TOPICS="topic1_two,topic2_two"

  run inject_brokers
  echo "CONSOLE: ${output}"

  output=$(xmllint --noblanks --xpath "string(//*[local-name()='subsystem' and starts-with(namespace-uri(), 'urn:jboss:domain:ee:')]/*[local-name()='default-bindings']/@jms-connection-factory)" "${CONFIG_FILE}")
  [ "${output}" = "${TEST_MQ_JNDI}" ]

  expected=$(cat $BATS_TEST_DIRNAME/resource-adapters-for-two-amq-external-broker.xml | xmllint --format --noblanks -)
  output=$(xmllint --noblanks --xpath "//*[local-name()='subsystem' and starts-with(namespace-uri(), 'urn:jboss:domain:resource-adapters:')]/*" "${CONFIG_FILE}" | xmllint --format --noblanks -)

  [ "${output}" = "${expected}" ]
}

@test "Configure External broker type AMQ7 -- One AMQ7 broker via Markers" {
  CONFIG_ADJUSTMENT_MODE="xml"

  MQ_SERVICE_PREFIX_MAPPING="messaging_bats_test-amq7=TEST_MQ"

  MESSAGING_BATS_TEST_AMQ_TCP_SERVICE_HOST="127.0.0.1"
  MESSAGING_BATS_TEST_AMQ_TCP_SERVICE_PORT=9999
  TEST_MQ_JNDI="mq_jndi"
  TEST_MQ_USERNAME="mq_username"
  TEST_MQ_PASSWORD="mq_password"
  TEST_MQ_QUEUES="queue1,queue2"
  TEST_MQ_TOPICS="topic1,topic2"
  TEST_MQ_TRACKING="true"

  run inject_brokers
  echo "CONSOLE: ${output}"

  output=$(xmllint --noblanks --xpath "string(//*[local-name()='subsystem' and starts-with(namespace-uri(), 'urn:jboss:domain:ee:')]/*[local-name()='default-bindings']/@jms-connection-factory)" "${CONFIG_FILE}")
  [ "${output}" = "${TEST_MQ_JNDI}" ]

  output=$(xmllint --noblanks --xpath "//*[local-name()='socket-binding-group'][@name='standard-sockets']/*[local-name()='outbound-socket-binding'][@name='messaging-remote-throughput']" "${CONFIG_FILE}")
  [ "${output}" = "<outbound-socket-binding name=\"messaging-remote-throughput\"><remote-destination host=\"${MESSAGING_BATS_TEST_AMQ_TCP_SERVICE_HOST}\" port=\"${MESSAGING_BATS_TEST_AMQ_TCP_SERVICE_PORT}\"/></outbound-socket-binding>" ]


  expected=$(xmllint --xpath "//*[local-name()='server']" $BATS_TEST_DIRNAME/messaging-activemq-server-for-amq7-external-broker.xml | xmllint --format --noblanks -)
  output=$(xmllint --xpath "//*[local-name()='subsystem' and starts-with(namespace-uri(), 'urn:jboss:domain:messaging-activemq:')]/*" "${CONFIG_FILE}" | xmllint --format --noblanks -)
  [ "${output}" = "${expected}" ]

  expected=$(xmllint --xpath "//*[local-name()='bindings']" $BATS_TEST_DIRNAME/bindings-for-amq7-external-broker.xml | xmllint --format --noblanks -)
  output=$(xmllint --xpath "//*[local-name()='subsystem' and starts-with(namespace-uri(), 'urn:jboss:domain:naming:')]/*[local-name()='bindings']" "${CONFIG_FILE}" | xmllint --format --noblanks -)
  [ "${output}" = "${expected}" ]
}


@test "Configure legacy external broker -- Two AMQ brokers via CLI" {
  expected=$(cat <<EOF
    if (outcome != success) of /subsystem=resource-adapters:read-resource
      echo You have set MQ_SERVICE_PREFIX_MAPPING environment variable to configure the service name 'messaging_bats_test-amq' under 'TEST_MQ' prefix. Fix your configuration to contain resource adapters subsystem for this to happen. >> \${error_file}
      exit
    end-if

    /subsystem=resource-adapters/resource-adapter="activemq-rar.rar":add(archive=activemq-rar.rar, transaction-support=XATransaction)
    /subsystem=resource-adapters/resource-adapter="activemq-rar.rar"/config-properties=UserName:add(value="mq_username_one")
    /subsystem=resource-adapters/resource-adapter="activemq-rar.rar"/config-properties=Password:add(value="mq_password_one")
    /subsystem=resource-adapters/resource-adapter="activemq-rar.rar"/config-properties=ServerUrl:add(value="tcp://hostone:1999?jms.rmIdFromConnectionId=true")
    /subsystem=resource-adapters/resource-adapter="activemq-rar.rar"/connection-definitions="messaging_bats_test-amq-ConnectionFactory":add(tracking="true", class-name=org.apache.activemq.ra.ActiveMQManagedConnectionFactory, jndi-name="mq_jndi_one", enabled=true, min-pool-size=1, max-pool-size=20, pool-prefill=false, same-rm-override=false, recovery-username="mq_username_one", recovery-password="mq_password_one")

    /subsystem=resource-adapters/resource-adapter="activemq-rar.rar"/admin-objects="queue/queue1_one":add(class-name="org.apache.activemq.command.ActiveMQQueue", jndi-name="java:/queue/queue1_one", use-java-context=true)
    /subsystem=resource-adapters/resource-adapter="activemq-rar.rar"/admin-objects="queue/queue1_one"/config-properties=PhysicalName:add(value="queue/queue1_one")
    /subsystem=resource-adapters/resource-adapter="activemq-rar.rar"/admin-objects="queue/queue2_one":add(class-name="org.apache.activemq.command.ActiveMQQueue", jndi-name="java:/queue/queue2_one", use-java-context=true)
    /subsystem=resource-adapters/resource-adapter="activemq-rar.rar"/admin-objects="queue/queue2_one"/config-properties=PhysicalName:add(value="queue/queue2_one")
    /subsystem=resource-adapters/resource-adapter="activemq-rar.rar"/admin-objects="topic/topic1_one":add(class-name="org.apache.activemq.command.ActiveMQTopic", jndi-name="java:/topic/topic1_one", use-java-context=true)
    /subsystem=resource-adapters/resource-adapter="activemq-rar.rar"/admin-objects="topic/topic1_one"/config-properties=PhysicalName:add(value="topic/topic1_one")
    /subsystem=resource-adapters/resource-adapter="activemq-rar.rar"/admin-objects="topic/topic2_one":add(class-name="org.apache.activemq.command.ActiveMQTopic", jndi-name="java:/topic/topic2_one", use-java-context=true)
    /subsystem=resource-adapters/resource-adapter="activemq-rar.rar"/admin-objects="topic/topic2_one"/config-properties=PhysicalName:add(value="topic/topic2_one")

    if (outcome != success) of /subsystem=resource-adapters:read-resource
      echo You have set MQ_SERVICE_PREFIX_MAPPING environment variable to configure the service name 'messaging_bats_test_two-amq' under 'TEST_MQ_TWO' prefix. Fix your configuration to contain resource adapters subsystem for this to happen. >> \${error_file}
      exit
    end-if

    /subsystem=resource-adapters/resource-adapter="activemq-rar.rar-1":add(archive=activemq-rar.rar, transaction-support=XATransaction)
    /subsystem=resource-adapters/resource-adapter="activemq-rar.rar-1"/config-properties=UserName:add(value="mq_username_two")
    /subsystem=resource-adapters/resource-adapter="activemq-rar.rar-1"/config-properties=Password:add(value="mq_password_two")
    /subsystem=resource-adapters/resource-adapter="activemq-rar.rar-1"/config-properties=ServerUrl:add(value="tcp://hostonetwo:2999?jms.rmIdFromConnectionId=true")
    /subsystem=resource-adapters/resource-adapter="activemq-rar.rar-1"/connection-definitions="messaging_bats_test_two-amq-ConnectionFactory":add(class-name=org.apache.activemq.ra.ActiveMQManagedConnectionFactory, jndi-name="mq_jndi_two", enabled=true, min-pool-size=1, max-pool-size=20, pool-prefill=false, same-rm-override=false, recovery-username="mq_username_two", recovery-password="mq_password_two")

    /subsystem=resource-adapters/resource-adapter="activemq-rar.rar-1"/admin-objects="queue/queue1_two":add(class-name="org.apache.activemq.command.ActiveMQQueue", jndi-name="java:/queue/queue1_two", use-java-context=true)
    /subsystem=resource-adapters/resource-adapter="activemq-rar.rar-1"/admin-objects="queue/queue1_two"/config-properties=PhysicalName:add(value="queue/queue1_two")
    /subsystem=resource-adapters/resource-adapter="activemq-rar.rar-1"/admin-objects="queue/queue2_two":add(class-name="org.apache.activemq.command.ActiveMQQueue", jndi-name="java:/queue/queue2_two", use-java-context=true)
    /subsystem=resource-adapters/resource-adapter="activemq-rar.rar-1"/admin-objects="queue/queue2_two"/config-properties=PhysicalName:add(value="queue/queue2_two")
    /subsystem=resource-adapters/resource-adapter="activemq-rar.rar-1"/admin-objects="topic/topic1_two":add(class-name="org.apache.activemq.command.ActiveMQTopic", jndi-name="java:/topic/topic1_two", use-java-context=true)
    /subsystem=resource-adapters/resource-adapter="activemq-rar.rar-1"/admin-objects="topic/topic1_two"/config-properties=PhysicalName:add(value="topic/topic1_two")
    /subsystem=resource-adapters/resource-adapter="activemq-rar.rar-1"/admin-objects="topic/topic2_two":add(class-name="org.apache.activemq.command.ActiveMQTopic", jndi-name="java:/topic/topic2_two", use-java-context=true)
    /subsystem=resource-adapters/resource-adapter="activemq-rar.rar-1"/admin-objects="topic/topic2_two"/config-properties=PhysicalName:add(value="topic/topic2_two")
    /subsystem=ee/service=default-bindings:write-attribute(name=jms-connection-factory, value="mq_jndi_one")
EOF
)
  CONFIG_ADJUSTMENT_MODE="cli"

   MQ_SERVICE_PREFIX_MAPPING="messaging_bats_test-amq=TEST_MQ,messaging_bats_test_two-amq=TEST_MQ_TWO"

  MESSAGING_BATS_TEST_AMQ_TCP_SERVICE_HOST="hostone"
  MESSAGING_BATS_TEST_AMQ_TCP_SERVICE_PORT=1999
  TEST_MQ_JNDI="mq_jndi_one"
  TEST_MQ_USERNAME="mq_username_one"
  TEST_MQ_PASSWORD="mq_password_one"
  TEST_MQ_QUEUES="queue1_one,queue2_one"
  TEST_MQ_TOPICS="topic1_one,topic2_one"
  TEST_MQ_TRACKING="true"

  MESSAGING_BATS_TEST_TWO_AMQ_TCP_SERVICE_HOST="hostonetwo"
  MESSAGING_BATS_TEST_TWO_AMQ_TCP_SERVICE_PORT=2999
  TEST_MQ_TWO_JNDI="mq_jndi_two"
  TEST_MQ_TWO_USERNAME="mq_username_two"
  TEST_MQ_TWO_PASSWORD="mq_password_two"
  TEST_MQ_TWO_QUEUES="queue1_two,queue2_two"
  TEST_MQ_TWO_TOPICS="topic1_two,topic2_two"

  run inject_brokers
  echo "CONSOLE: ${output}"
  output=$(cat "${CLI_SCRIPT_FILE}")
  normalize_spaces_new_lines
  [ "${output}" = "${expected}" ]
}


@test "Configure External broker type AMQ7 -- One AMQ7 broker via CLI" {
   expected=$(cat <<EOF
    if (outcome != success) of /subsystem=messaging-activemq:read-resource
      echo You have set MQ_SERVICE_PREFIX_MAPPING environment variable to configure the service name 'messaging_bats_test-amq7' under 'TEST_MQ' prefix. Fix your configuration to contain messaging-activemq subsystem for this to happen. >> \${error_file}
      exit
    end-if

    if (outcome == success) of /socket-binding-group=standard-sockets/remote-destination-outbound-socket-binding="messaging-remote-throughput":read-resource
      echo You have set MQ_SERVICE_PREFIX_MAPPING environment variable to configure the service name 'messaging_bats_test-amq7' under 'TEST_MQ' prefix. Fix your configuration to not contain a remote-destination-outbound-socket-binding named 'messaging-remote-throughput' for this to happen. >> \${error_file}
      exit
    end-if

    /socket-binding-group=standard-sockets/remote-destination-outbound-socket-binding="messaging-remote-throughput":add(host="127.0.0.1", port="9999")
    /subsystem=messaging-activemq/remote-connector=netty-remote-throughput:add(socket-binding="messaging-remote-throughput")
    /subsystem=messaging-activemq/pooled-connection-factory="activemq-ra-remote":add(user="mq_username", password="mq_password", entries=["java:/JmsXA java:/RemoteJmsXA java:jboss/RemoteJmsXA mq_jndi"], connectors=["netty-remote-throughput"], transaction=xa)

    if (outcome != success) of /subsystem=naming:read-resource
      echo You have set MQ_SERVICE_PREFIX_MAPPING environment variable to configure the service name 'messaging_bats_test-amq7' under 'TEST_MQ' prefix. Fix your configuration to contain naming subsystem for this to happen. >> \${error_file}
      exit
    end-if

    if (outcome == success) of /subsystem=naming/binding="java:global/remoteContext":read-resource
      echo You have set MQ_SERVICE_PREFIX_MAPPING environment variable to configure the service name 'messaging_bats_test-amq7' under 'TEST_MQ' prefix. Fix your configuration to not contain a naming binding with name 'java:global/remoteContext' for this to happen. >> \${error_file}
      exit
    end-if

    /subsystem=naming/binding="java:global/remoteContext":add(binding-type=external-context, class=javax.naming.InitialContext, module=org.apache.activemq.artemis, environment={java.naming.provider.url="tcp://127.0.0.1:9999", java.naming.factory.initial=org.apache.activemq.artemis.jndi.ActiveMQInitialContextFactory})
    /subsystem=naming/binding="java:global/remoteContext":map-put(name=environment, key="queue.queue1", value="queue1")
    /subsystem=naming/binding="java:/queue1":add(binding-type=lookup, lookup="java:global/remoteContext/queue1")
    /subsystem=naming/binding="java:global/remoteContext":map-put(name=environment, key="queue.queue2", value="queue2")
    /subsystem=naming/binding="java:/queue2":add(binding-type=lookup, lookup="java:global/remoteContext/queue2")
    /subsystem=naming/binding="java:global/remoteContext":map-put(name=environment, key="topic.topic1", value="topic1")
    /subsystem=naming/binding="java:/topic1":add(binding-type=lookup, lookup="java:global/remoteContext/topic1")
    /subsystem=naming/binding="java:global/remoteContext":map-put(name=environment, key="topic.topic2", value="topic2")
    /subsystem=naming/binding="java:/topic2":add(binding-type=lookup, lookup="java:global/remoteContext/topic2")
    /subsystem=ee/service=default-bindings:write-attribute(name=jms-connection-factory, value="mq_jndi")
EOF

)
  CONFIG_ADJUSTMENT_MODE="cli"

  MQ_SERVICE_PREFIX_MAPPING="messaging_bats_test-amq7=TEST_MQ"

  MESSAGING_BATS_TEST_AMQ_TCP_SERVICE_HOST="127.0.0.1"
  MESSAGING_BATS_TEST_AMQ_TCP_SERVICE_PORT=9999
  TEST_MQ_JNDI="mq_jndi"
  TEST_MQ_USERNAME="mq_username"
  TEST_MQ_PASSWORD="mq_password"
  TEST_MQ_QUEUES="queue1,queue2"
  TEST_MQ_TOPICS="topic1,topic2"
  TEST_MQ_TRACKING="true"

  run inject_brokers
  echo "CONSOLE: ${output}"
  output=$(cat "${CLI_SCRIPT_FILE}")
  normalize_spaces_new_lines
  [ "${output}" = "${expected}" ]
}

@test "Configure Embedded server broker -- with CLI, with destinations but disabled" {
    CONFIG_ADJUSTMENT_MODE="cli"

    rm -f "${CONFIG_WARNING_FILE}"
    rm -f "${CLI_SCRIPT_FILE}"

    export MQ_CLUSTER_PASSWORD="somemqpassword"
    export MQ_QUEUES="queue1,queue2"
    export MQ_TOPICS="topic1,topic2"
    ACTIVEMQ_SUBSYSTEM_FILE=$JBOSS_HOME/bin/launch/activemq-subsystem.xml
    export DISABLE_EMBEDDED_JMS_BROKER="always"
    run configure_mq

    [ ! -a "${CLI_SCRIPT_FILE}" ]
    [ ! -a "${CONFIG_WARNING_FILE}" ]
}

@test "Configure Embedded server broker -- with CLI and destinations" {
    expected=$(cat << EOF
      if (outcome == success) of /subsystem=messaging-activemq/server=default:read-resource
        echo You have configured messaging queues via 'MQ_QUEUES' or 'HORNETQ_QUEUES' or topics via 'MQ_TOPICS' or 'HORNETQ_TOPICS' variables. Fix your configuration to not contain a default server configured on messaging-activemq subsystem for this to happen. >> \${error_file}
        exit
      end-if

      batch
        /subsystem=messaging-activemq/server=default:add(journal-pool-files=10, statistics-enabled="\${wildfly.messaging-activemq.statistics-enabled:\${wildfly.statistics-enabled:false}}")

        /subsystem=messaging-activemq/server="default"/jms-queue="queue1":add(entries=["/queue/queue1"])
        /subsystem=messaging-activemq/server="default"/jms-queue="queue2":add(entries=["/queue/queue2"])
        /subsystem=messaging-activemq/server="default"/jms-topic="topic1":add(entries=["/topic/topic1"])
        /subsystem=messaging-activemq/server="default"/jms-topic="topic2":add(entries=["/topic/topic2"])

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

      if (outcome == success) of /socket-binding-group=standard-sockets/socket-binding=messaging:read-resource
        echo You have configured messaging queues via 'MQ_QUEUES' or 'HORNETQ_QUEUES' or topics via 'MQ_TOPICS' or 'HORNETQ_TOPICS' variables. Fix your configuration to not contain a socket-binding named 'messaging' for this to happen. >> \${error_file}
        exit
      end-if

      if (outcome == success) of /socket-binding-group=standard-sockets/socket-binding=messaging-throughput:read-resource
        echo You have configured messaging queues via 'MQ_QUEUES' or 'HORNETQ_QUEUES' or topics via 'MQ_TOPICS' or 'HORNETQ_TOPICS' variables. Fix your configuration to not contain a socket-binding named 'messaging-throughput' for this to happen. >> \${error_file}
        exit
      end-if

      /socket-binding-group=standard-sockets/socket-binding=messaging:add(port=5445)
      /socket-binding-group=standard-sockets/socket-binding=messaging-throughput:add(port=5455)
EOF
)
    CONFIG_ADJUSTMENT_MODE="cli"

    export MQ_CLUSTER_PASSWORD="somemqpassword"
    export MQ_QUEUES="queue1,queue2"
    export MQ_TOPICS="topic1,topic2"
    run configure_mq

    echo "CONSOLE: ${output}"
    output=$(<"${CLI_SCRIPT_FILE}")
    normalize_spaces_new_lines
    [ "${output}" = "${expected}" ]
}