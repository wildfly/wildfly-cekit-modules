#!/usr/bin/env bats

source $BATS_TEST_DIRNAME/../../../../../../test-common/cli_utils.sh

# fake JBOSS_HOME
export JBOSS_HOME=$BATS_TMPDIR/jboss_home
rm -rf $JBOSS_HOME 2>/dev/null
mkdir -p $JBOSS_HOME/bin/launch

# copy scripts we are going to use
cp $BATS_TEST_DIRNAME/../../../launch-config/config/added/launch/openshift-common.sh $JBOSS_HOME/bin/launch
cp $BATS_TEST_DIRNAME/../../../launch-config/os/added/launch/launch-common.sh $JBOSS_HOME/bin/launch
cp $BATS_TEST_DIRNAME/../../../../../../test-common/logging.sh $JBOSS_HOME/bin/launch
cp $BATS_TEST_DIRNAME/../added/launch/tracing.sh $JBOSS_HOME/bin/launch

mkdir -p $JBOSS_HOME/standalone/configuration

# Set up the environment variables and load dependencies
WILDFLY_SERVER_CONFIGURATION=standalone-openshift.xml

# source the scripts needed
source $JBOSS_HOME/bin/launch/openshift-common.sh
source $JBOSS_HOME/bin/launch/logging.sh
source $JBOSS_HOME/bin/launch/tracing.sh

setup() {
  cp $BATS_TEST_DIRNAME/../../../../../../test-common/configuration/standalone-openshift.xml $JBOSS_HOME/standalone/configuration
}

teardown() {
  if [ -n "${CONFIG_FILE}" ] && [ -f "${CONFIG_FILE}" ]; then
    rm "${CONFIG_FILE}"
  fi
}

@test "Test Tracing -- Verify CLI operations when WILDFLY_TRACING_ENABLED is enabled" {
  expected="$(cat << EOF
    if (outcome != success) of /extension=org.wildfly.extension.microprofile.opentracing-smallrye:read-resource
      /extension=org.wildfly.extension.microprofile.opentracing-smallrye:add()
    end-if
    if (outcome != success) of /subsystem=microprofile-opentracing-smallrye:read-resource
      /subsystem=microprofile-opentracing-smallrye:add()
    end-if
EOF
)"
  CONFIG_ADJUSTMENT_MODE="cli"
  WILDFLY_TRACING_ENABLED=true
  run configure
  output=$(<"${CLI_SCRIPT_FILE}")
  normalize_spaces_new_lines
  [ "${output}" = "${expected}" ]
}

@test "Test Tracing -- Verify CLI operations when WILDFLY_TRACING_ENABLED is disabled" {
  expected="$(cat << EOF
  if (outcome == success) of /subsystem=microprofile-opentracing-smallrye:read-resource
    /subsystem=microprofile-opentracing-smallrye:remove()
  end-if
  if (outcome == success) of /extension=org.wildfly.extension.microprofile.opentracing-smallrye:read-resource
    /extension=org.wildfly.extension.microprofile.opentracing-smallrye:remove()
  end-if
EOF
)"
  CONFIG_ADJUSTMENT_MODE="cli"
  WILDFLY_TRACING_ENABLED=false
  run configure
  output=$(<"${CLI_SCRIPT_FILE}")
  normalize_spaces_new_lines
  [ "${output}" = "${expected}" ]
}


@test "Test Tracing -- Verify CLI operations when WILDFLY_TRACING_ENABLED is not set" {
  expected=
  CONFIG_ADJUSTMENT_MODE="cli"
  unset WILDFLY_TRACING_ENABLED
  run configure
  output=$(<"${CLI_SCRIPT_FILE}")
  normalize_spaces_new_lines
  [ "${output}" = "${expected}" ]
}