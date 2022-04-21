#!/usr/bin/env bats
source $BATS_TEST_DIRNAME/../../../../../../test-common/cli_utils.sh
# fake JBOSS_HOME
export JBOSS_HOME=$BATS_TMPDIR/jboss_home
rm -rf $JBOSS_HOME 2>/dev/null
mkdir -p $JBOSS_HOME/bin/
touch $JBOSS_HOME/bin/standalone.conf

export JBOSS_CONTAINER_UTIL_LOGGING_MODULE=$BATS_TMPDIR/logging
mkdir -p "${JBOSS_CONTAINER_UTIL_LOGGING_MODULE}"
cp $BATS_TEST_DIRNAME/../../../../../../test-common/logging.sh "${JBOSS_CONTAINER_UTIL_LOGGING_MODULE}"
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

@test "Java 17" {
  expected=$(cat << EOF
#JVM modular option  --add-exports=jdk.naming.dns/com.sun.jndi.dns=ALL-UNNAMED added by image run startup script
JAVA_OPTS="\$JAVA_OPTS --add-exports=jdk.naming.dns/com.sun.jndi.dns=ALL-UNNAMED"
EOF
    )
  JAVA_VERSION=17
  run run_add_jpms_options
  output=$(<"${JBOSS_HOME}/bin/standalone.conf")
  normalize_spaces_new_lines
  echo "$output"
  echo "$expected"
  [ "${output}" = "${expected}" ]
}

@test "Java 17, jndi export disabled" {
  RUN_SCRIPT_JPMS_ADD_EXPORT_JNDI_DNS=false
  JAVA_VERSION=17
  run run_add_jpms_options
  [ "${output}" = "" ]
  confFile=$(<"${JBOSS_HOME}/bin/standalone.conf")
   [ "${confFile}" = "" ]
  [ "$status" -eq 0 ]
}

@test "Java 17, jndi export enabled" {
  expected=$(cat << EOF
#JVM modular option  --add-exports=jdk.naming.dns/com.sun.jndi.dns=ALL-UNNAMED added by image run startup script
JAVA_OPTS="\$JAVA_OPTS --add-exports=jdk.naming.dns/com.sun.jndi.dns=ALL-UNNAMED"
EOF
    )
RUN_SCRIPT_JPMS_ADD_EXPORT_JNDI_DNS=true
  JAVA_VERSION=17
  run run_add_jpms_options
  output=$(<"${JBOSS_HOME}/bin/standalone.conf")
  normalize_spaces_new_lines
  echo "$output"
  echo "$expected"
  [ "${output}" = "${expected}" ]
}

@test "JBoss Node name set" {
  JBOSS_NODE_NAME=foo
  run_init_node_name
  [ "${JBOSS_NODE_NAME}" = "foo" ]
}

@test "Node name set" {
  NODE_NAME=abcdefghijklmnopqrstuvwxyz
  run_init_node_name
  [ "${JBOSS_NODE_NAME}" = "defghijklmnopqrstuvwxyz" ]
}

@test "Host name set" {
  HOSTNAME=abcdefghijklmnopqrstuvwxyz123
  run_init_node_name
    echo $JBOSS_NODE_NAME
  [ "${JBOSS_NODE_NAME}" = "ghijklmnopqrstuvwxyz123" ]
}
