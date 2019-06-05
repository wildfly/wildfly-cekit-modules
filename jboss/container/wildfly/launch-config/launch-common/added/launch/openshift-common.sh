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

source ${JBOSS_HOME}/bin/launch/adjustment-mode.sh
