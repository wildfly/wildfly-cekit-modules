#!/usr/bin/env bats

# fake JBOSS_HOME
export JBOSS_HOME=$BATS_TMPDIR/jboss_home
rm -rf $JBOSS_HOME 2>/dev/null
mkdir -p $JBOSS_HOME/bin/launch

# copy scripts we are going to use
cp $BATS_TEST_DIRNAME/../added/launch/openshift-node-name.sh $JBOSS_HOME/bin/launch


# source the scripts needed
source $JBOSS_HOME/bin/launch/openshift-node-name.sh


@test "JBoss Node name set to a value smaller than 23" {
  JBOSS_NODE_NAME=foo
  init_node_name
  [ "${JBOSS_NODE_NAME}" = "foo" ]
  [ "${JBOSS_TX_NODE_ID}" = "foo" ]
}

@test "JBOSS_NODE_NAME set" {
  JBOSS_NODE_NAME=abcdefghijklmnopqrstuvwxyz123
  init_node_name
  echo $JBOSS_NODE_NAME

  # Verify that jboss.node.name is untouched
  [ "${JBOSS_NODE_NAME}" = "abcdefghijklmnopqrstuvwxyz123" ]
  # Verify that jboss.tx.node.id is truncated to last 23 characters
  [ "${JBOSS_TX_NODE_ID}" = "ghijklmnopqrstuvwxyz123" ]
}

@test "Node name set" {
  NODE_NAME=abcdefghijklmnopqrstuvwxyz
  init_node_name

  # Verify that jboss.node.name is untouched
  [ "${JBOSS_NODE_NAME}" = "abcdefghijklmnopqrstuvwxyz" ]
  # Verify that jboss.tx.node.id is truncated to last 23 characters
  [ "${JBOSS_TX_NODE_ID}" = "defghijklmnopqrstuvwxyz" ]
}

@test "Node name set to value smaller than 23" {
  NODE_NAME=abcdef
  init_node_name

  # Verify that jboss.node.name is untouched
  [ "${JBOSS_NODE_NAME}" = "abcdef" ]
  # Verify that jboss.tx.node.id is untouched
  [ "${JBOSS_TX_NODE_ID}" = "abcdef" ]
}

@test "Host name set" {
  HOSTNAME=abcdefghijklmnopqrstuvwxyz123
  init_node_name
  echo $JBOSS_NODE_NAME

  # Verify that jboss.node.name is untouched
  [ "${JBOSS_NODE_NAME}" = "abcdefghijklmnopqrstuvwxyz123" ]
  # Verify that jboss.tx.node.id is truncated to last 23 characters
  [ "${JBOSS_TX_NODE_ID}" = "ghijklmnopqrstuvwxyz123" ]
}
