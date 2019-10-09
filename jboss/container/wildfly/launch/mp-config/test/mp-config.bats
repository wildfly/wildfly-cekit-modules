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
cp $BATS_TEST_DIRNAME/../added/launch/mp-config.sh $JBOSS_HOME/bin/launch

mkdir -p $JBOSS_HOME/standalone/configuration

# Set up the environment variables and load dependencies
WILDFLY_SERVER_CONFIGURATION=standalone-openshift.xml

# source the scripts needed
source $JBOSS_HOME/bin/launch/logging.sh
source $JBOSS_HOME/bin/launch/openshift-common.sh
source $JBOSS_HOME/bin/launch/mp-config.sh

BATS_PATH_TO_EXISTING_FILE=$BATS_TEST_DIRNAME/mp-config.bats

setup() {
  cp $BATS_TEST_DIRNAME/../../../../../../test-common/configuration/standalone-openshift.xml $JBOSS_HOME/standalone/configuration
}

teardown() {
  if [ -n "${CONFIG_FILE}" ] && [ -f "${CONFIG_FILE}" ]; then
    rm "${CONFIG_FILE}"
  fi
}

@test "Unconfigured" {
  run generate_microprofile_config_source
  [ "${output}" = "" ]
  [ "$status" -eq 0 ]
}

@test "Configure MICROPROFILE_CONFIG_DIR_ORDINAL=150 -- ordinal only" {
  run generate_microprofile_config_source "" "150"
  [ "${output}" = "" ]
  [ "$status" -eq 0 ]
}

@test "Configure MICROPROFILE_CONFIG_DIR=$BATS_TEST_DIRNAME" {

  run generate_microprofile_config_source "${BATS_TEST_DIRNAME}"
  echo ${output}
  [ "$status" -eq 0 ]

  result=$(check_dir_config "${BATS_TEST_DIRNAME}" "500" "${output}")
  [ -n "${result}" ]
}

@test "Configure MICROPROFILE_CONFIG_DIR=$BATS_TEST_DIRNAME MICROPROFILE_CONFIG_DIR_ORDINAL=150" {

  run generate_microprofile_config_source "${BATS_TEST_DIRNAME}" "150"
  echo ${output}
  [ "$status" -eq 0 ]

  result=$(check_dir_config "${BATS_TEST_DIRNAME}" "150" "${output}")
  [ -n "${result}" ]
}

@test "Configure MICROPROFILE_CONFIG_DIR=etc/config" {

  run generate_microprofile_config_source "etc/config"
  echo ${output}
  [ "$status" -eq 0 ]

  echo "${lines[0]}" | grep -q "WARN MICROPROFILE_CONFIG_DIR value 'etc/config' is not an absolute path"
  [ $? -eq 0 ]

  result=$(check_dir_config "etc/config" "500" "${lines[1]}")
  [ -n "${result}" ]
}

@test "Configure MICROPROFILE_CONFIG_DIR=jboss.home MICROPROFILE_CONFIG_DIR_ORDINAL=150" {

  run generate_microprofile_config_source "jboss.home" "150"
  echo ${output}
  [ "$status" -eq 0 ]

  echo "${lines[0]}" | grep -q "WARN MICROPROFILE_CONFIG_DIR value 'jboss.home' is not an absolute path"
  [ $? -eq 0 ]

  result=$(check_dir_config "jboss.home" "150" "${lines[1]}")
  [ -n "${result}" ]
}

@test "Configure MICROPROFILE_CONFIG_DIR=/bogus/beyond/belief" {

  run generate_microprofile_config_source "/bogus/beyond/belief"
  echo ${output}
  [ "$status" -eq 0 ]

  echo "${lines[0]}" | grep -q "WARN MICROPROFILE_CONFIG_DIR value '/bogus/beyond/belief' is a non-existent path"
  [ $? -eq 0 ]

  result=$(check_dir_config "/bogus/beyond/belief" "500" "${lines[1]}")
  [ -n "${result}" ]
}

@test "Configure MICROPROFILE_CONFIG_DIR=/bogus/beyond/belief MICROPROFILE_CONFIG_DIR_ORDINAL=150" {
  run generate_microprofile_config_source "/bogus/beyond/belief" "150"
  echo ${output}
  [ "$status" -eq 0 ]

  echo "${lines[0]}" | grep -q "WARN MICROPROFILE_CONFIG_DIR value '/bogus/beyond/belief' is a non-existent path"
  [ $? -eq 0 ]

  result=$(check_dir_config "/bogus/beyond/belief" "150" "${lines[1]}")
  [ -n "${result}" ]
}

@test "Configure MICROPROFILE_CONFIG_DIR=$BATS_PATH_TO_EXISTING_FILE" {

  run generate_microprofile_config_source "${BATS_PATH_TO_EXISTING_FILE}"
  echo "CONSOLE:${output}"
  [ "$status" -eq 0 ]

  echo "${lines[0]}" | grep "WARN MICROPROFILE_CONFIG_DIR value '${BATS_PATH_TO_EXISTING_FILE}' is not a directory"
  [ $? -eq 0 ]

  result=$(check_dir_config "${BATS_PATH_TO_EXISTING_FILE}" "500" "${lines[1]}")
  [ -n "${result}" ]
}

@test "Configure MICROPROFILE_CONFIG_DIR=BATS_PATH_TO_EXISTING_FILE MICROPROFILE_CONFIG_DIR_ORDINAL=150" {
  run generate_microprofile_config_source "${BATS_PATH_TO_EXISTING_FILE}" "150"
echo "CONFIG_FILE $CONFIG_FILE"
  echo ${output}
  [ "$status" -eq 0 ]
  echo "${lines[0]}" | grep -q "WARN MICROPROFILE_CONFIG_DIR value '${BATS_PATH_TO_EXISTING_FILE}' is not a directory"
  [ $? -eq 0 ]

  result=$(check_dir_config "${BATS_PATH_TO_EXISTING_FILE}" "150" "${lines[1]}")
  [ -n "${result}" ]
}

check_dir_config() {
  declare dir_name=$1 ordinal=$2 toCheck=$3
  expected=$(cat <<EOF
<?xml version="1.0"?>
   <config-source ordinal="$ordinal" name="config-map"><dir path="$dir_name"/></config-source>
EOF
)
  result=$(echo ${toCheck} | sed 's|\\n||g' | xmllint --format --noblanks -)
  expected=$(echo "${expected}" | sed 's|\\n||g' | xmllint --format --noblanks -)
  if [ "${result}" = "${expected}" ]; then
    echo $result
  fi
}


@test "Configure MICROPROFILE_CONFIG_DIR -- Verify CLI operations with ordinal" {
    expected=$(cat << EOF
      if (outcome != success) of /subsystem=microprofile-config-smallrye:read-resource
        echo \"You have set MICROPROFILE_CONFIG_DIR to configure a config-source. Fix your configuration to contain the microprofile-config subsystem for this to happen.\" >> \${error_file}
        quit
      end-if

      if (outcome == success) of /subsystem=microprofile-config-smallrye/config-source=config-map:read-resource
        echo \"Cannot configure Microprofile Config. MICROPROFILE_CONFIG_DIR was specified but there is already a config-source named config-map configured.\" >> \${error_file}
        quit
      end-if

      /subsystem=microprofile-config-smallrye/config-source=config-map:add(dir={path="/test/dir"}, ordinal=22)
EOF
    )

    CONFIG_ADJUSTMENT_MODE="cli"
    MICROPROFILE_CONFIG_DIR="/test/dir"
    MICROPROFILE_CONFIG_DIR_ORDINAL=22

    run configure_microprofile_config_source
    echo "CONSOLE:${output}"
    output=$(<"${CLI_SCRIPT_FILE}")
    normalize_spaces_new_lines
    [ "${output}" = "${expected}" ]
}

@test "Configure MICROPROFILE_CONFIG_DIR -- Verify CLI operations without configure an ordinal" {
    expected=$(cat << EOF
      if (outcome != success) of /subsystem=microprofile-config-smallrye:read-resource
        echo \"You have set MICROPROFILE_CONFIG_DIR to configure a config-source. Fix your configuration to contain the microprofile-config subsystem for this to happen.\" >> \${error_file}
        quit
      end-if

      if (outcome == success) of /subsystem=microprofile-config-smallrye/config-source=config-map:read-resource
        echo \"Cannot configure Microprofile Config. MICROPROFILE_CONFIG_DIR was specified but there is already a config-source named config-map configured.\" >> \${error_file}
        quit
      end-if

      /subsystem=microprofile-config-smallrye/config-source=config-map:add(dir={path="/test/dir"}, ordinal=500)
EOF
    )

    CONFIG_ADJUSTMENT_MODE="cli"
    MICROPROFILE_CONFIG_DIR="/test/dir"

    run configure_microprofile_config_source
    echo "CONSOLE:${output}"
    output=$(<"${CLI_SCRIPT_FILE}")
    normalize_spaces_new_lines
    [ "${output}" = "${expected}" ]
}