#!/bin/sh

if [ "${SCRIPT_DEBUG}" = "true" ] ; then
    set -x
    echo "Script debugging is enabled, allowing bash commands and their arguments to be printed as they are executed"
fi

SERVER_CONFIG=${WILDFLY_SERVER_CONFIGURATION:-standalone.xml}
CONFIG_FILE=$JBOSS_HOME/standalone/configuration/${SERVER_CONFIG}
LOGGING_FILE=$JBOSS_HOME/standalone/configuration/logging.properties
CLI_DRIVERS_FILE=${JBOSS_HOME}/bin/launch/drivers.cli

# Test an XpathExpression against server config file and returns
# the xmllint exit code
#
# Parameters:
# - $1      - the xpath expression to use
# - $2      - the variable which will hold the result
#
function testXpathExpression() {
  local xpath="$1"
  unset -v "$2" || echo "Invalid identifier: $2" >&2

  if [ "${SCRIPT_DEBUG}" == "true" ]; then
    eval xmllint --xpath "${xpath}" "${CONFIG_FILE}"
  else
    eval xmllint --xpath "${xpath}" "${CONFIG_FILE}" 1>/dev/null
  fi

  printf -v "$2" '%s' "$?"
}

# CONFIG_ADJUSTMENT_MODE is the mode used to do the environment variable replacement.
# The values are:
# -none     - no adjustment should be done. This cam be forced if $CONFIG_IS_FINAL = true
#               is passed in when starting the container
# -xml      - adjustment will happen via the legacy xml marker replacement
# -cli      - adjustment will happen via cli commands
# -xml_cli  - adjustment will happen via xml marker replacement if the marker is found. If not,
#               it will happen via cli commands. This is the default if not set by a consumer.
#
# Handling of the meanings of this is done by the launch scripts doing the config adjustment.
# Consumers of this script are expected to set this value.
if [ -z "${CONFIG_ADJUSTMENT_MODE}" ]; then
  CONFIG_ADJUSTMENT_MODE="xml_cli"
fi
if [ "${CONFIG_IS_FINAL^^}" = "TRUE" ]; then
    CONFIG_ADJUSTMENT_MODE="none"
fi

# Takes the following parameters:
# - $1      - the xml marker to test for
# - $2      - the variable which will hold the result
# The result holding variable, $2, will be populated with one of the following
# three values:
# - ""      - no configuration should be done
# - "xml"   - configuration should happen via marker replacement
# - "cli"   - configuration should happen via cli commands
#
function getConfigurationMode() {
  local marker="${1}"
  unset -v "$2" || echo "Invalid identifier: $2" >&2

  local attemptXml="false"
  local viaCli="false"
  if [ "${CONFIG_ADJUSTMENT_MODE,,}" = "xml" ]; then
    attemptXml="true"
  elif  [ "${CONFIG_ADJUSTMENT_MODE,,}" = "cli" ]; then
    viaCli="true"
  elif  [ "${CONFIG_ADJUSTMENT_MODE,,}" = "xml_cli" ]; then
    attemptXml="true"
    viaCli="true"
  elif [ "${CONFIG_ADJUSTMENT_MODE,,}" != "none" ]; then
    echo "Bad CONFIG_ADJUSTMENT_MODE \'${CONFIG_ADJUSTMENT_MODE}\'"
    exit 1
  fi

  local configVia=""
  if [ "${attemptXml}" = "true" ]; then
    if grep -Fq "${marker}" $CONFIG_FILE; then
        configVia="xml"
    fi
  fi

  if [ -z "${configVia}" ]; then
    if [ "${viaCli}" = "true" ]; then
        configVia="cli"
    fi
  fi

  printf -v "$2" '%s' "${configVia}"
}
