#!/usr/bin/env bats
source $BATS_TEST_DIRNAME/../../../../../../../test-common/cli_utils.sh
# fake JBOSS_HOME
export JBOSS_HOME=$BATS_TMPDIR/jboss_home
rm -rf $JBOSS_HOME 2>/dev/null
mkdir -p $JBOSS_HOME/bin/
touch $JBOSS_HOME/bin/standalone.conf

export JBOSS_CONTAINER_UTIL_LOGGING_MODULE=$BATS_TMPDIR/logging
mkdir -p "${JBOSS_CONTAINER_UTIL_LOGGING_MODULE}"
cp $BATS_TEST_DIRNAME/../../../../../../../test-common/logging.sh "${JBOSS_CONTAINER_UTIL_LOGGING_MODULE}"
source $BATS_TEST_DIRNAME/../artifacts/opt/jboss/container/wildfly/run/run-utils.sh

setup() {
 rm -f $JBOSS_HOME/bin/standalone.conf
 touch $JBOSS_HOME/bin/standalone.conf
}

@test "Java 8" {
  JAVA_VERSION=1.8
  run run_add_jpms_options
  [ "${output}" = "" ]
  confFile=$(<"${JBOSS_HOME}/bin/standalone.conf")
   [ "${confFile}" = "" ]
  [ "$status" -eq 0 ]
}

@test "Java 11" {
  JAVA_VERSION=11
  run run_add_jpms_options
  [ "${output}" = "" ]
  confFile=$(<"${JBOSS_HOME}/bin/standalone.conf")
   [ "${confFile}" = "" ]
  [ "$status" -eq 0 ]
}

@test "JBoss Node name set to a value smaller than 23" {
  JBOSS_NODE_NAME=foo
  run_init_node_name
  [ "${JBOSS_NODE_NAME}" = "foo" ]
  [ "${JBOSS_TX_NODE_ID}" = "foo" ]
}

@test "JBOSS_NODE_NAME set" {
  JBOSS_NODE_NAME=abcdefghijklmnopqrstuvwxyz123
  run_init_node_name
  echo $JBOSS_NODE_NAME

  # Verify that jboss.node.name is untouched
  [ "${JBOSS_NODE_NAME}" = "abcdefghijklmnopqrstuvwxyz123" ]
  # Verify that jboss.tx.node.id is truncated to last 23 characters
  [ "${JBOSS_TX_NODE_ID}" = "ghijklmnopqrstuvwxyz123" ]
}

@test "Node name set" {
  NODE_NAME=abcdefghijklmnopqrstuvwxyz
  run_init_node_name

  # Verify that jboss.node.name is untouched
  [ "${JBOSS_NODE_NAME}" = "abcdefghijklmnopqrstuvwxyz" ]
  # Verify that jboss.tx.node.id is truncated to last 23 characters
  [ "${JBOSS_TX_NODE_ID}" = "defghijklmnopqrstuvwxyz" ]
}

@test "Node name set to value smaller than 23" {
  NODE_NAME=abcdef
  run_init_node_name

  # Verify that jboss.node.name is untouched
  [ "${JBOSS_NODE_NAME}" = "abcdef" ]
  # Verify that jboss.tx.node.id is untouched
  [ "${JBOSS_TX_NODE_ID}" = "abcdef" ]
}

@test "Host name set" {
  HOSTNAME=abcdefghijklmnopqrstuvwxyz123
  run_init_node_name
  echo $JBOSS_NODE_NAME

  # Verify that jboss.node.name is untouched
  [ "${JBOSS_NODE_NAME}" = "abcdefghijklmnopqrstuvwxyz123" ]
  # Verify that jboss.tx.node.id is truncated to last 23 characters
  [ "${JBOSS_TX_NODE_ID}" = "ghijklmnopqrstuvwxyz123" ]
}
