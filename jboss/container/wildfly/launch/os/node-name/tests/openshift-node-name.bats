#!/usr/bin/env bats

# fake JBOSS_HOME
export JBOSS_HOME=$BATS_TMPDIR/jboss_home
rm -rf $JBOSS_HOME 2>/dev/null
mkdir -p $JBOSS_HOME/bin/launch
# copy scripts we are going to use
cp $BATS_TEST_DIRNAME/../../../../../../../test-common/logging.sh $JBOSS_HOME/bin/launch

source $BATS_TEST_DIRNAME/../added/launch/openshift-node-name.sh

@test "init_node_name: NODE_NAME defined the value is expected to be adopted" {
  unset JBOSS_NODE_NAME
  NODE_NAME=12345678912345678912345 init_node_name
  [ "${#JBOSS_NODE_NAME}" -lt 24 ]
  [ "$JBOSS_NODE_NAME" = "12345678912345678912345" ]
}

@test "init_node_name: NODE_NAME defined the value has to be shortened to 23 characters" {
  unset JBOSS_NODE_NAME
  NODE_NAME=abcdefghijklmnopqrstvuwxyz init_node_name
  [ "${#JBOSS_NODE_NAME}" -eq 23 ]
  [ "$JBOSS_NODE_NAME" = "abcdefghijkB4FAF216ADB2" ]
}

@test "init_node_name: truncation collision" {
  unset JBOSS_NODE_NAME
  NODE_NAME=abcdefghijklmnopqrstvuwxyz init_node_name
  [ "${#JBOSS_NODE_NAME}" -eq 23 ]
  [ "$JBOSS_NODE_NAME" = "abcdefghijkB4FAF216ADB2" ]
  prev=$JBOSS_NODE_NAME
  unset JBOSS_NODE_NAME
  NODE_NAME=abcdefghijklmnopqrstvuwxy1 init_node_name
  [ "${#JBOSS_NODE_NAME}" -eq 23 ]
  [ "$JBOSS_NODE_NAME" != "${prev}" ]
 }