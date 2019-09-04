#!/usr/bin/env bats

# bug in bats with set -eu?
export BATS_TEST_SKIPPED=

export JBOSS_HOME=$BATS_TMPDIR/jboss_home

rm -rf $JBOSS_HOME 2>/dev/null
mkdir -p $JBOSS_HOME/bin/launch
cp $BATS_TEST_DIRNAME/../../../launch-config/config/added/launch/openshift-common.sh $JBOSS_HOME/bin/launch
cp $BATS_TEST_DIRNAME/../../../../../../test-common/logging.sh $JBOSS_HOME/bin/launch
cp $BATS_TEST_DIRNAME/../added/launch/configure_logger_category.sh $JBOSS_HOME/bin/launch

# Set up the environment variables and load dependencies
WILDFLY_SERVER_CONFIGURATION=standalone-openshift.xml
source $JBOSS_HOME/bin/launch/openshift-common.sh
source $JBOSS_HOME/bin/launch/configure_logger_category.sh

setup() {
  mkdir -p $JBOSS_HOME/standalone/configuration
  cp $BATS_TEST_DIRNAME/../../../../../../test-common/configuration/standalone-openshift.xml $JBOSS_HOME/standalone/configuration
}

teardown() {
  rm -rf $JBOSS_HOME
}

run_logger_category_script() {
  preConfigure
  configure
  postConfigure
}

# note the <test>...</test> wrapper is used to allow xmllint to reformat (it requires a root node) so comparisons are more robust between different versions
# of xmllint etc.
@test "Add 1 logger category" {
  #this is the return of xmllint --xpath "//*[local-name()='subsystem']//*[local-name()='logger'][@category='com.my.package']" $CONFIG_FILE
  expected=$(cat <<EOF
<logger category="com.my.package"><level name="DEBUG"/></logger>
EOF
)
  LOGGER_CATEGORIES=com.my.package:DEBUG
  run run_logger_category_script
  result=$(xmllint --xpath "//*[local-name()='subsystem']//*[local-name()='logger'][@category='com.my.package']" $CONFIG_FILE)
  result="$(echo "<test>${result}</test>" | sed 's|\\n||g' | xmllint --format --noblanks -)"
  expected=$(echo "<test>${expected}</test>" | sed 's|\\n||g' | xmllint --format --noblanks -)
  echo "Expected: ${expected}"
  echo "Result: ${result}"
  [ "${result}" = "${expected}" ]
}

@test "Add 2 logger categories" {
  #this is the return of xmllint --xpath "//*[local-name()='subsystem']//*[local-name()='logger'][@category='com.my.package' or @category='my.other.package']" $CONFIG_FILE
  expected=$(cat <<EOF
<logger category="com.my.package"><level name="DEBUG"/></logger>
<logger category="my.other.package"><level name="ERROR"/></logger>
EOF
)
  LOGGER_CATEGORIES=com.my.package:DEBUG,my.other.package:ERROR
  run run_logger_category_script
  result=$(xmllint -xpath "//*[local-name()='subsystem']//*[local-name()='logger'][@category='com.my.package' or @category='my.other.package']" $CONFIG_FILE)
  result="$(echo "<test>${result}</test>" | sed 's|\\n||g' | xmllint --format --noblanks -)"
  expected=$(echo "<test>${expected}</test>" | sed 's|\\n||g' | xmllint --format --noblanks -)
  echo "Expected: ${expected}"
  echo "Result: ${result}"
  [ "${result}" = "${expected}" ]
}

@test "Add 3 logger categories, one with no log level" {
  #this is the return of xmllint --xpath "//*[local-name()='subsystem']//*[local-name()='logger'][@category='com.my.package' or @category='my.other.package' or @category='my.another.package']" $CONFIG_FILE
  expected=$(cat <<EOF
<logger category="com.my.package"><level name="DEBUG"/></logger>
<logger category="my.other.package"><level name="ERROR"/></logger>
<logger category="my.another.package"><level name="FINE"/></logger>
EOF
)
  LOGGER_CATEGORIES=com.my.package:DEBUG,my.other.package:ERROR,my.another.package
  run run_logger_category_script
  result=$(xmllint --xpath "//*[local-name()='subsystem']//*[local-name()='logger'][@category='com.my.package' or @category='my.other.package' or @category='my.another.package']" $CONFIG_FILE)
  result="$(echo "<test>${result}</test>" | sed 's|\\n||g' | xmllint --format --noblanks -)"
  expected=$(echo "<test>${expected}</test>" | sed 's|\\n||g' | xmllint --format --noblanks -)
  echo "Expected: ${expected}"
  echo "Result: ${result}"
  [ "${result}" = "${expected}" ]
}

@test "Add 3 logger categories with spaces" {
  #this is the return of xmllint --xpath "//*[local-name()='subsystem']//*[local-name()='logger'][@category='com.my.package' or @category='my.other.package' or @category='my.another.package']" $CONFIG_FILE '
  expected=$(cat <<EOF
<logger category="com.my.package"><level name="DEBUG"/></logger>
<logger category="my.other.package"><level name="ERROR"/></logger>
<logger category="my.another.package"><level name="FINE"/></logger>
EOF
)
  LOGGER_CATEGORIES=" com.my.package:DEBUG, my.other.package:ERROR, my.another.package"
  run run_logger_category_script
  result=$(xmllint --xpath "//*[local-name()='subsystem']//*[local-name()='logger'][@category='com.my.package' or @category='my.other.package' or @category='my.another.package']" $CONFIG_FILE)
  result="$(echo "<test>${result}</test>" | sed 's|\\n||g' | xmllint --format --noblanks -)"
  expected=$(echo "<test>${expected}</test>" | sed 's|\\n||g' | xmllint --format --noblanks -)
  echo "Expected: ${expected}"
  echo "Result: ${result}"
  [ "${result}" = "${expected}" ]
}

@test "Add 2 logger categories one with invalid log level" {
  #this is the return of xmllint --xpath "//*[local-name()='subsystem']//*[local-name()='logger'][@category='com.my.package' or @category='my.other.package']" $CONFIG_FILE
  expected=$(cat <<EOF
<logger category="com.my.package"><level name="DEBUG"/></logger>
EOF
)
  LOGGER_CATEGORIES=com.my.package:DEBUG,my.other.package:UNKNOWN_LOG_LEVEL
  run run_logger_category_script
  result=$(xmllint --format --noblanks --xpath "//*[local-name()='subsystem']//*[local-name()='logger'][@category='com.my.package' or @category='my.other.package']" $CONFIG_FILE)
  result="$(echo "<test>${result}</test>" | sed 's|\\n||g' | xmllint --format --noblanks -)"
  expected=$(echo "<test>${expected}</test>" | sed 's|\\n||g' | xmllint --format --noblanks -)
  echo "Expected: ${expected}"
  echo "Result: ${result}"
  [ "${result}" = "${expected}" ]
}

@test "Test error when no subsystem is present" {
  #this is the return of xmllint --xpath "//*[local-name()='subsystem']//*[local-name()='logger'][@category='com.my.package' or @category='my.other.package']" $CONFIG_FILE
  expected="You have set LOGGER_CATEGORIES to configure a looger. Fix your configuration to contain the logging subsystem for this to happen."
  cp $BATS_TEST_DIRNAME/server-configs/no-logger-subsystem.xml $JBOSS_HOME/standalone/configuration/standalone-openshift.xml
  LOGGER_CATEGORIES=com.my.package:DEBUG,my.other.package:UNKNOWN_LOG_LEVEL
  run run_logger_category_script
  local line=""
  while read -r line; do
      if [ "${line}" = "${expected}" ]; then
        break;
      fi
  done < "$CLI_SCRIPT_ERROR_FILE"
  echo "${line}"
  [ "${line}" = "${expected}" ]
}
