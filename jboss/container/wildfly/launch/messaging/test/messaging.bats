export BATS_TEST_SKIPPED=

# fake JBOSS_HOME
export JBOSS_HOME=$BATS_TMPDIR/jboss_home
rm -rf $JBOSS_HOME 2>/dev/null
mkdir -p $JBOSS_HOME/bin/launch

# copy scripts we are going to use
cp $BATS_TEST_DIRNAME/../../../launch-config/config/added/launch/openshift-common.sh $JBOSS_HOME/bin/launch
cp $BATS_TEST_DIRNAME/../../../../../../test-common/logging.sh $JBOSS_HOME/bin/launch
cp $BATS_TEST_DIRNAME/../added/launch/messaging.sh $JBOSS_HOME/bin/launch
cp $BATS_TEST_DIRNAME/../added/launch/activemq-subsystem.xml $JBOSS_HOME/bin/launch
mkdir -p $JBOSS_HOME/standalone/configuration

# Set up the environment variables and load dependencies
WILDFLY_SERVER_CONFIGURATION=standalone-openshift.xml

# source the scripts needed
source $JBOSS_HOME/bin/launch/openshift-common.sh
source $JBOSS_HOME/bin/launch/logging.sh
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
