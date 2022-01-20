#!/usr/bin/env bats

source $BATS_TEST_DIRNAME/../../../../../../../test-common/cli_utils.sh

export BATS_TEST_SKIPPED=

# fake JBOSS_HOME
export JBOSS_HOME=$BATS_TMPDIR/jboss_home
rm -rf $JBOSS_HOME
mkdir -p $JBOSS_HOME/bin/launch

# copy scripts we are going to use
cp $BATS_TEST_DIRNAME/../../../../launch-config/config/1.0/added/launch/openshift-common.sh $JBOSS_HOME/bin/launch
cp $BATS_TEST_DIRNAME/../../../../launch-config/os/added/launch/launch-common.sh $JBOSS_HOME/bin/launch
cp $BATS_TEST_DIRNAME/../../../../../../../test-common/logging.sh $JBOSS_HOME/bin/launch
cp $BATS_TEST_DIRNAME/../added/launch/messaging.sh $JBOSS_HOME/bin/launch
mkdir -p $JBOSS_HOME/standalone/configuration

# Set up the environment variables and load dependencies
WILDFLY_SERVER_CONFIGURATION=standalone-openshift.xml

# source the scripts needed
source $JBOSS_HOME/bin/launch/logging.sh
source $JBOSS_HOME/bin/launch/openshift-common.sh
source $JBOSS_HOME/bin/launch/messaging.sh

setup() {
  cp $BATS_TEST_DIRNAME/../../../../../../../test-common/configuration/standalone-openshift.xml $JBOSS_HOME/standalone/configuration
}

teardown() {
  if [ -n "${CONFIG_FILE}" ] && [ -f "${CONFIG_FILE}" ]; then
    rm "${CONFIG_FILE}"
  fi
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

@test "Configure destinations for embedded broker -- with CLI" {
    expected=$(cat << EOF
        if (outcome != success) of /subsystem=messaging-activemq/server=default:read-resource
            echo You have set MQ_QUEUES and/or MQ_TOPICS but no default embedded broker is present in the server configuration. You must provision a default server for the queues and topics to be registered. >> \${error_file}
            exit
        end-if

        /subsystem=messaging-activemq/server="default"/jms-queue="queue1":add(entries=["/queue/queue1"])
        /subsystem=messaging-activemq/server="default"/jms-queue="queue2":add(entries=["/queue/queue2"])
        /subsystem=messaging-activemq/server="default"/jms-topic="topic1":add(entries=["/topic/topic1"])
        /subsystem=messaging-activemq/server="default"/jms-topic="topic2":add(entries=["/topic/topic2"])
EOF
)
    CONFIG_ADJUSTMENT_MODE="cli"

    export MQ_CLUSTER_PASSWORD="somemqpassword"
    export MQ_QUEUES="queue1,queue2"
    export MQ_TOPICS="topic1,topic2"
    run configure_mq

    echo "CONSOLE: ${output}"
    output=$(<"${CLI_SCRIPT_FILE}")
    echo "SCRIPT:${output}"
    normalize_spaces_new_lines
    [ "${output}" = "${expected}" ]
}